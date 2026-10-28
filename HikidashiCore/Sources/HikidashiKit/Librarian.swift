// アプリ本体の司令塔。共有シートから届いたものをメモにし、AI で整理し、問いかけに合うメモを取り出す。
// 使う AI の順: 自分の API キーか購読があれば Claude、無ければ iPhone の中の AI（無料）。
// どちらも使えないときは、簡易の整理とキーワード検索で動く。

import Foundation
import Observation

/// いま使っている AI
public enum AIKind: Sendable, Equatable {
    /// Claude（自分の API キーか Mindrawer Plus）
    case claude
    /// iPhone の中の AI（Apple Intelligence。無料）
    case onDevice
    /// AI なし（簡易の整理とキーワード検索）
    case none
}

public struct RecallOutcome: Sendable, Equatable {
    public var query: String
    public var answer: String
    public var noteIDs: [String]
    /// AI を使わずキーワードで探した結果か
    public var keywordOnly: Bool
}

@Observable
@MainActor
public final class Librarian {
    public let store: NoteStore
    /// 整理中のメモの id
    public private(set) var filing: Set<String> = []
    public private(set) var lastError: String?
    /// メモ風モード: コピペした文を、整理のときに AI が箇条書きのメモに整える（元の文は original に残す）
    public static let memoModeKey = "memoMode"
    public var memoMode: Bool = UserDefaults.standard.bool(forKey: Librarian.memoModeKey) {
        didSet { UserDefaults.standard.set(memoMode, forKey: Self.memoModeKey) }
    }

    /// AI を使えるか（Claude か iPhone の中の AI）
    public var hasAI: Bool { aiKind != .none }

    public var aiKind: AIKind {
        if credentialProvider() != nil { return .claude }
        return onDevice != nil ? .onDevice : .none
    }

    private let credentialProvider: @MainActor () -> ClaudeClient.Credential?
    private let onDevice: (any NoteAI)?
    private let linkFetcher: @Sendable (String) async -> LinkPreview?
    private let textExtractor: @Sendable (Data, String) async -> String?

    /// credentialProvider: Claude の呼び方を返す（無ければ nil）
    /// onDevice: iPhone の中の AI（使えない端末では nil）
    public init(store: NoteStore,
                credentialProvider: @escaping @MainActor () -> ClaudeClient.Credential? = Librarian.apiKeyCredential,
                onDevice: (any NoteAI)? = OnDeviceAI.make(),
                linkFetcher: @escaping @Sendable (String) async -> LinkPreview? = { await LinkFetcher.fetch($0) },
                textExtractor: @escaping @Sendable (Data, String) async -> String? = { await TextExtractor.text(fromFile: $0, extension: $1) }) {
        self.store = store
        self.credentialProvider = credentialProvider
        self.onDevice = onDevice
        self.linkFetcher = linkFetcher
        self.textExtractor = textExtractor
    }

    /// 端末に保存した自分の API キーを使う
    public static func apiKeyCredential() -> ClaudeClient.Credential? {
        guard let key = APIKeyStore.load(), !key.isEmpty else { return nil }
        return .apiKey(key)
    }

    var ai: (any NoteAI)? {
        if let credential = credentialProvider() {
            if case let .apiKey(key) = credential, key.isEmpty { return onDevice }
            return Filer(client: ClaudeClient(credential: credential))
        }
        return onDevice
    }

    static var today: String { Heuristics.dayFormatter.string(from: Date()) }

    // MARK: 保存

    /// 共有シートから届いたものをメモにする。追加した件数を返す
    @discardableResult
    public func ingestInbox() -> Int {
        let items = Inbox.drain(root: store.root)
        for item in items {
            var note = Note(text: item.noteText, url: item.url, createdAt: item.createdAt, filed: false, imageFile: item.imageFile,
                            file: item.file, fileTitle: item.fileTitle)
            Heuristics.file(&note)
            store.add(note)
        }
        return items.count
    }

    /// アプリ内で書いたメモを保存する（すぐ一覧に出し、整理は後から）
    @discardableResult
    public func save(text: String, url: String?, image: Data?, file: (data: Data, name: String)? = nil) -> Note {
        var imageFile: String?
        var fileName: String?
        let id = UUID().uuidString
        if let image {
            let name = id + ".jpg"
            if (try? image.write(to: store.imageURL(name), options: .atomic)) != nil { imageFile = name }
        }
        if let file {
            let ext = (file.name as NSString).pathExtension
            let name = id + (ext.isEmpty ? "" : "." + ext.lowercased())
            if (try? file.data.write(to: store.imageURL(name), options: .atomic)) != nil { fileName = name }
        }
        var note = Note(id: id, text: text.trimmingCharacters(in: .whitespacesAndNewlines), url: Note.nonEmpty(url), filed: false, imageFile: imageFile,
                        file: fileName, fileTitle: file?.name)
        Heuristics.file(&note)
        store.add(note)
        return note
    }

    // MARK: 整理

    /// 未整理のメモをまとめて整理する（AI が無くても、画像・ファイル・リンク先の文字は取り出す）
    public func fileAll() async {
        let pending = store.notes.filter { (!$0.filed || !$0.enriched) && !filing.contains($0.id) }.map(\.id)
        for id in pending {
            await file(id)
        }
    }

    /// 1 件を AI で整理する（再整理にも使う）
    public func file(_ id: String) async {
        guard var note = store.note(id), !filing.contains(id) else { return }
        filing.insert(id)
        defer { filing.remove(id) }
        if !note.enriched {
            await enrich(id)
            if let updated = store.note(id) { note = updated }
        }
        guard let ai = ai else { return }
        // スクショだけのメモは、文字を読めない AI では整理できない
        if !ai.readsImages, note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        // スクショの文字は Claude だけが読める
        let image = ai.readsImages
            ? note.imageFile.flatMap { try? Data(contentsOf: store.imageURL($0)) }.map { ClaudeClient.Image(data: $0) }
            : nil
        let folders = store.folders.filter { $0 != note.category || note.filed }
        do {
            // メモ風に整えるのは、初めて整理する、ある程度長い文だけ
            let memo = memoMode && !note.filed && Self.worthMemo(note.text)
            let r = try await ai.file(note, folders: folders, image: image, today: Self.today, language: .current, memo: memo)
            store.update(id) { $0.apply(r, replaceText: image != nil || memo) }
            lastError = nil
        } catch {
            // iPhone の中の AI が失敗したときは、簡易の整理のまま黙って続ける
            if aiKind == .claude { lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
        }
    }

    /// メモ風に整える価値がある長さか（短いメモはそのまま）
    static func worthMemo(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count >= 80 || t.components(separatedBy: "\n").count >= 4
    }

    /// メモ風に整える前の文に戻す
    public func restoreOriginal(_ id: String) {
        store.update(id) { n in
            guard let o = n.original else { return }
            n.text = o
            n.original = nil
        }
    }

    /// 画像の文字（OCR）・添付ファイルの文字・リンク先のタイトルと説明を本文に足す（1 回だけ、端末の中で）
    func enrich(_ id: String) async {
        guard let note = store.note(id), !note.enriched else { return }
        let before = note.text
        var text = note.text
        if let url = note.url, !text.contains(LinkFetcher.marker), let preview = await linkFetcher(url) {
            text = LinkFetcher.merge(text, preview)
        }
        if let img = note.imageFile, !text.contains(TextExtractor.imageMarker),
           let data = try? Data(contentsOf: store.imageURL(img)), let t = await textExtractor(data, "jpg") {
            text = TextExtractor.merge(text, extracted: t, marker: TextExtractor.imageMarker)
        }
        if let f = note.file, !text.contains(TextExtractor.fileMarker),
           let data = try? Data(contentsOf: store.imageURL(f)), let t = await textExtractor(data, (f as NSString).pathExtension) {
            text = TextExtractor.merge(text, extracted: t, marker: TextExtractor.fileMarker)
        }
        let wasEmpty = before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        store.update(id) { n in
            n.text = text
            n.enriched = true
            // 本文が空だったメモは、取り出した文字でタイトルとフォルダを付け直す（AI が無いときのため）
            if wasEmpty, !n.filed, text != before {
                n.title = Heuristics.title(for: text.replacingOccurrences(of: TextExtractor.imageMarker, with: "")
                    .replacingOccurrences(of: TextExtractor.fileMarker, with: "")
                    .replacingOccurrences(of: LinkFetcher.marker, with: ""))
                n.category = Heuristics.folder(for: text)
            }
        }
    }

    // MARK: 取り出し

    public func recall(_ query: String) async -> RecallOutcome {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = store.notes
        guard !notes.isEmpty else {
            return RecallOutcome(query: q, answer: L("まだメモがありません。先にいくつかしまってください。", "Nothing saved yet. Save a few tips first."), noteIDs: [], keywordOnly: true)
        }
        if let ai = ai {
            do {
                let r = try await ai.recall(q, notes: notes, today: Self.today, language: .current)
                lastError = nil
                return RecallOutcome(query: q, answer: r.answer, noteIDs: r.ids, keywordOnly: false)
            } catch {
                // iPhone の中の AI が失敗したときは、簡易の整理のまま黙って続ける
            if aiKind == .claude { lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
            }
        }
        let hits = Heuristics.search(notes, query: q)
        let answer = hits.isEmpty
            ? L("関係しそうなメモは見つかりませんでした。", "Nothing related turned up.")
            : L("キーワードが近いメモが \(hits.count) 件あります。", "\(hits.count) notes look related by keyword.")
        return RecallOutcome(query: q, answer: answer, noteIDs: hits.map(\.id), keywordOnly: true)
    }

    public func clearError() { lastError = nil }

    // MARK: 見本

    public func addExamples() {
        let day: TimeInterval = 86400
        let examples: [Note] = AppLanguage.current == .ja ? [
            Note(text: "醤油やコーヒーをこぼしたら、こすらずに水を含ませた布で外側から内側へ叩く。最後に中性洗剤を少し。", title: "シミは叩いて落とす", summary: "こすらず外→内に叩き、仕上げに中性洗剤。", category: "暮らし・家事", tags: ["シミ抜き", "洗濯"], situations: ["服を汚したとき", "洗濯するとき"], createdAt: Date().addingTimeInterval(-17 * day), example: true, filed: true),
            Note(text: "iPhone のテキスト入力中にスペースキーを長押しすると、カーソルを自由に動かせる。", title: "スペース長押しでカーソル移動", summary: "スペースキー長押しでトラックパッドのように動かせる。", category: "PC・ガジェット", tags: ["iPhone", "小技"], situations: ["長文を直すとき"], createdAt: Date().addingTimeInterval(-34 * day), example: true, filed: true),
            Note(text: "引っ越し見積もりは同じ日に複数社を時間ずらして呼ぶと、相見積もりで値下げしやすい。3月は避ける。", title: "引っ越し見積もりは同日に複数社", summary: "同じ日に複数社を呼ぶと値下げ交渉が効く。", category: "お金・節約", tags: ["引っ越し", "相見積もり"], situations: ["引っ越しの準備", "値段交渉するとき"], createdAt: Date().addingTimeInterval(-51 * day), example: true, filed: true),
        ] : [
            Note(text: "Coffee or soy sauce spill: don't rub. Blot with a damp cloth from the outside in, then a drop of dish soap.", title: "Blot stains, never rub", summary: "Work from the outside in with a damp cloth, finish with dish soap.", category: "Home", tags: ["stains", "laundry"], situations: ["Spilled on clothes", "Doing laundry"], createdAt: Date().addingTimeInterval(-17 * day), example: true, filed: true),
            Note(text: "On iPhone, press and hold the space bar while typing to move the cursor like a trackpad.", title: "Hold space to move the cursor", summary: "The space bar turns into a trackpad.", category: "Tech", tags: ["iPhone", "typing"], situations: ["Editing a long message"], createdAt: Date().addingTimeInterval(-34 * day), example: true, filed: true),
            Note(text: "Book movers' estimates on the same day, an hour apart. Competing quotes drop fast. Avoid end of month.", title: "Get moving quotes on one day", summary: "Back-to-back estimates make movers undercut each other.", category: "Money", tags: ["moving", "quotes"], situations: ["Planning a move", "Negotiating a price"], createdAt: Date().addingTimeInterval(-51 * day), example: true, filed: true),
        ]
        for n in examples { store.add(n) }
    }
}

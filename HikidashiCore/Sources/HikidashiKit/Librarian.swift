// アプリ本体の司令塔。共有シートから届いたものをメモにし、AI で整理し、問いかけに合うメモを取り出す。
// API キーが無いときは、簡易の整理とキーワード検索で動く。

import Foundation
import Observation

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
    /// AI（Claude）を使えるか。自分の API キーか、購読があれば true
    public var hasAI: Bool { credentialProvider() != nil }

    private let credentialProvider: @MainActor () -> ClaudeClient.Credential?

    /// credentialProvider: Claude の呼び方を返す（無ければ nil で、簡易の整理とキーワード検索になる）
    public init(store: NoteStore, credentialProvider: @escaping @MainActor () -> ClaudeClient.Credential? = Librarian.apiKeyCredential) {
        self.store = store
        self.credentialProvider = credentialProvider
    }

    /// 端末に保存した自分の API キーを使う
    public static func apiKeyCredential() -> ClaudeClient.Credential? {
        guard let key = APIKeyStore.load(), !key.isEmpty else { return nil }
        return .apiKey(key)
    }

    var filer: Filer? {
        guard let credential = credentialProvider() else { return nil }
        if case let .apiKey(key) = credential, key.isEmpty { return nil }
        return Filer(client: ClaudeClient(credential: credential))
    }

    static var today: String { Heuristics.dayFormatter.string(from: Date()) }

    // MARK: 保存

    /// 共有シートから届いたものをメモにする。追加した件数を返す
    @discardableResult
    public func ingestInbox() -> Int {
        let items = Inbox.drain(root: store.root)
        for item in items {
            var note = Note(text: item.noteText, url: item.url, createdAt: item.createdAt, filed: false, imageFile: item.imageFile)
            Heuristics.file(&note)
            store.add(note)
        }
        return items.count
    }

    /// アプリ内で書いたメモを保存する（すぐ一覧に出し、整理は後から）
    @discardableResult
    public func save(text: String, url: String?, image: Data?) -> Note {
        var imageFile: String?
        let id = UUID().uuidString
        if let image {
            let name = id + ".jpg"
            if (try? image.write(to: store.imageURL(name), options: .atomic)) != nil { imageFile = name }
        }
        var note = Note(id: id, text: text.trimmingCharacters(in: .whitespacesAndNewlines), url: Note.nonEmpty(url), filed: false, imageFile: imageFile)
        Heuristics.file(&note)
        store.add(note)
        return note
    }

    // MARK: 整理

    /// 未整理のメモをまとめて整理する
    public func fileAll() async {
        guard filer != nil else { return }
        let pending = store.notes.filter { !$0.filed && !filing.contains($0.id) }.map(\.id)
        for id in pending {
            await file(id)
        }
    }

    /// 1 件を AI で整理する（再整理にも使う）
    public func file(_ id: String) async {
        guard let filer = filer, let note = store.note(id), !filing.contains(id) else { return }
        filing.insert(id)
        defer { filing.remove(id) }
        let image = note.imageFile.flatMap { try? Data(contentsOf: store.imageURL($0)) }.map { ClaudeClient.Image(data: $0) }
        let folders = store.folders.filter { $0 != note.category || note.filed }
        do {
            let r = try await filer.file(note, folders: folders, image: image, today: Self.today)
            store.update(id) { $0.apply(r, replaceText: image != nil) }
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: 取り出し

    public func recall(_ query: String) async -> RecallOutcome {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = store.notes
        guard !notes.isEmpty else {
            return RecallOutcome(query: q, answer: L("まだメモがありません。先にいくつかしまってください。", "Nothing saved yet. Save a few tips first."), noteIDs: [], keywordOnly: true)
        }
        if let filer = filer {
            do {
                let r = try await filer.recall(q, notes: notes, today: Self.today)
                lastError = nil
                return RecallOutcome(query: q, answer: r.answer, noteIDs: r.ids, keywordOnly: false)
            } catch {
                lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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

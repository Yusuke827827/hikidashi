// iPhone の中で動く AI（Apple Intelligence の Foundation Models）での整理と取り出し。
// 無料の利用者向け。端末の外に何も送らず、料金もかからない。
// 使えるのは iOS 26 以降の Apple Intelligence 対応機種で、Apple Intelligence がオンのときだけ。
// 扱える長さが短い（約 4000 トークン）ので、本文は短く切り、取り出しはメモを絞ってから渡す。
// スクショの文字は読めない（読み取りは Claude だけ）。

import Foundation

/// 整理と取り出しをする AI（Claude か、iPhone の中の AI）
public protocol NoteAI: Sendable {
    /// スクショの文字を読み取れるか
    var readsImages: Bool { get }
    /// memo: 本文をメモ風に整える（FilingResult.text に入れて返す。整えないときは空）
    func file(_ note: Note, folders: [String], image: ClaudeClient.Image?, today: String, language: AppLanguage, memo: Bool) async throws -> FilingResult
    func recall(_ query: String, notes: [Note], today: String, language: AppLanguage) async throws -> RecallResult
}

extension Filer: NoteAI {
    public var readsImages: Bool { true }
}

public enum OnDeviceAI {
    /// この端末で iPhone の中の AI が使えれば返す
    public static func make() -> (any NoteAI)? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), SystemLanguageModel.default.isAvailable {
            return OnDeviceFiler()
        }
        #endif
        return nil
    }

    /// 取り出しで渡すメモの数（扱える長さに収めるため）
    static let recallPoolSize = 40

    /// 取り出しで渡すメモを選ぶ。キーワードが近いもの、ピン留め・役立ったもの、新しいものの順
    static func recallPool(_ notes: [Note], query: String) -> [Note] {
        let ranked = notes.sorted { a, b in
            let sa = Heuristics.score(a, query: query) + (a.pinned ? 0.5 : 0) + Double(min(a.helpful, 3)) * 0.2
            let sb = Heuristics.score(b, query: query) + (b.pinned ? 0.5 : 0) + Double(min(b.helpful, 3)) * 0.2
            return sa != sb ? sa > sb : a.createdAt > b.createdAt
        }
        return Array(ranked.prefix(recallPoolSize))
    }

    /// 取り出しで渡す一覧。id の代わりに短い番号を使う
    static func recallList(_ pool: [Note]) -> String {
        pool.enumerated().map { i, n in
            let about = n.summary.isEmpty ? String(n.text.prefix(60)) : String(n.summary.prefix(60))
            let when = n.situations.prefix(3).joined(separator: " / ")
            return "\(i + 1). \(n.title.prefix(40)) — \(about)" + (when.isEmpty ? "" : "（\(when)）")
        }.joined(separator: "\n")
    }

    /// 番号を id に戻す。範囲外や重複は捨てる
    static func ids(from numbers: [Int], pool: [Note]) -> [String] {
        var seen = Set<Int>()
        return numbers.compactMap { k in
            guard k >= 1, k <= pool.count, seen.insert(k).inserted else { return nil }
            return pool[k - 1].id
        }.prefix(8).map { $0 }
    }
}

#if canImport(FoundationModels)
@_weakLinked import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct OnDeviceFiling {
    @Guide(description: "A short title for the note, under 40 characters")
    var title: String
    @Guide(description: "One sentence that sums up the note")
    var summary: String
    @Guide(description: "A broad folder name of 1 to 3 words. Reuse an existing folder when it fits")
    var folder: String
    @Guide(description: "Up to 5 keywords")
    var tags: [String]
    @Guide(description: "2 to 4 moments when this note would help, phrased as what the user is doing, e.g. Doing laundry")
    var situations: [String]
    @Guide(description: "If the note mentions a date or deadline, the date as YYYY-MM-DD; otherwise an empty string")
    var remindAt: String
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct OnDeviceMemo {
    @Guide(description: "The note rewritten as a concise memo: short lines starting with ・, keeping key facts, numbers, steps, names and dates, dropping filler")
    var memo: String
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct OnDeviceRecall {
    @Guide(description: "2 to 3 short sentences of practical advice built only from the chosen notes")
    var answer: String
    @Guide(description: "Numbers of the notes that help, most relevant first, at most 8. Empty if none fit")
    var numbers: [Int]
}

@available(iOS 26.0, macOS 26.0, *)
struct OnDeviceFiler: NoteAI {
    var readsImages: Bool { false }

    func file(_ note: Note, folders: [String], image: ClaudeClient.Image?, today: String, language: AppLanguage, memo: Bool) async throws -> FilingResult {
        let session = LanguageModelSession(instructions: """
            You file notes for a personal "tips drawer" app. The user saves tips they find on X, the web, or in daily life, \
            and wants them handed back at the moment they need them. Write every field in \(language.promptName).
            """)
        let folderList = folders.isEmpty ? "(none yet)" : folders.prefix(30).joined(separator: " / ")
        let prompt = """
            Today: \(today)
            Existing folders: \(folderList)

            Note:
            \(note.text.prefix(1500))\(note.url.map { "\nSource: " + $0 } ?? "")
            """
        let r = try await session.respond(to: prompt, generating: OnDeviceFiling.self).content
        var memoText = ""
        if memo {
            let s = LanguageModelSession(instructions: "You turn pasted text into a concise personal memo. Write in \(language.promptName).")
            memoText = (try? await s.respond(to: String(note.text.prefix(2500)), generating: OnDeviceMemo.self).content.memo) ?? ""
        }
        return FilingResult(text: memoText, title: r.title, summary: r.summary, category: r.folder,
                            tags: r.tags, situations: r.situations, remindAt: r.remindAt)
    }

    func recall(_ query: String, notes: [Note], today: String, language: AppLanguage) async throws -> RecallResult {
        let pool = OnDeviceAI.recallPool(notes, query: query)
        let session = LanguageModelSession(instructions: """
            You pull the right notes out of a user's personal tips drawer at the moment they need them. \
            The input may be something they're about to do, a problem, a question, or a plain search. \
            Pick notes that would genuinely help now, even without shared words. Answer in \(language.promptName).
            """)
        let prompt = """
            Today: \(today)
            Input: \(query.prefix(300))

            Notes:
            \(OnDeviceAI.recallList(pool))
            """
        let r = try await session.respond(to: prompt, generating: OnDeviceRecall.self).content
        return RecallResult(answer: r.answer, ids: OnDeviceAI.ids(from: r.numbers, pool: pool))
    }
}
#endif

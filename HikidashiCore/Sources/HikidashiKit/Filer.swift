// Claude への頼み方。指示文と返事の形（JSON スキーマ）は Web 版と同じ考え方。
//   整理: タイトル・要約・フォルダ・タグ・使う場面・リマインド日を付ける（スクショがあれば文字を読み取る）
//   取り出し: 「これからすること」「困りごと」「質問」から、役立つメモを選んで短い助言を返す

import Foundation

public struct FilingResult: Codable, Sendable, Equatable {
    public var text: String
    public var title: String
    public var summary: String
    public var category: String
    public var tags: [String]
    public var situations: [String]
    /// YYYY-MM-DD。無ければ空文字
    public var remindAt: String
}

public struct RecallResult: Codable, Sendable, Equatable {
    public var answer: String
    public var ids: [String]
}

public enum Prompts {
    static let stringArray: [String: Any] = ["type": "array", "items": ["type": "string"]]

    public static let filingSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "text": ["type": "string"],
            "title": ["type": "string"],
            "summary": ["type": "string"],
            "category": ["type": "string"],
            "tags": stringArray,
            "situations": stringArray,
            "remindAt": ["type": "string"],
        ],
        "required": ["text", "title", "summary", "category", "tags", "situations", "remindAt"],
        "additionalProperties": false,
    ]

    public static let recallSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "answer": ["type": "string"],
            "ids": stringArray,
        ],
        "required": ["answer", "ids"],
        "additionalProperties": false,
    ]

    /// メモ風に整えるときの書き方
    static let memoRule = "Rewrite it as a concise memo the user can scan in seconds: short lines that each start with \"・\", keeping every key fact, number, step, name, date and URL, and dropping filler, greetings and repetition. Keep the original language. If the note is already a short memo (about 3 lines or fewer), return it unchanged."

    public static func filing(text: String, url: String?, hasImage: Bool, folders: [String], today: String, language: AppLanguage, memo: Bool = false) -> String {
        let textRule: String
        switch (hasImage, memo) {
        case (true, false):
            textRule = "\"text\": transcribe the useful content of the attached screenshot (for example a post on X) as clean plain text, merged with the typed note below. Drop UI chrome, usernames and counts unless they matter."
        case (true, true):
            textRule = "\"text\": read the useful content of the attached screenshot together with the typed note below. " + memoRule
        case (false, true):
            textRule = "\"text\": " + memoRule
        case (false, false):
            textRule = "\"text\": return the note text unchanged."
        }
        let folderList = folders.isEmpty ? "(none yet)" : folders.joined(separator: " / ")
        let body = text.isEmpty ? "(see screenshot)" : text
        let source = url.map { "\nSource: " + $0 } ?? ""
        return """
        You file notes for a personal "tips drawer" app. The user saves tips they find on X, the web, or in daily life, and wants them handed back at the moment they need them.
        Today: \(today). Write every field in \(language.promptName) (keep proper nouns and code as-is).
        Existing folders: \(folderList)
        Reuse an existing folder name exactly when it fits; otherwise invent a short, broad folder name (1–3 words) that future notes could share.
        "situations": 2–4 moments when this note would help, phrased the way the user would describe what they're doing (e.g. "Doing laundry", "Before a presentation").
        "remindAt": if the note mentions a date or deadline, give it as YYYY-MM-DD resolved against today; otherwise an empty string.
        \(textRule)
        "title": under 60 characters. "summary": one sentence. "tags": up to 5 keywords.

        Note:
        \(body)\(source)
        """
    }

    public static func recall(query: String, notes: [Note], today: String, language: AppLanguage) -> String {
        let pool: [[String: Any]] = notes.map { n -> [String: Any] in
            var d: [String: Any] = [
                "id": n.id, "title": n.title, "summary": n.summary.isEmpty ? String(n.text.prefix(140)) : n.summary,
                "folder": n.category, "tags": n.tags, "situations": n.situations, "helpful": n.helpful, "pinned": n.pinned,
            ]
            if let r = n.remindAt { d["remindAt"] = r }
            return d
        }
        let json = (try? JSONSerialization.data(withJSONObject: pool, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return """
        You pull the right notes out of a user's personal tips drawer at the moment they need them.
        The input may be something they're about to do, a problem, a question, or a plain search. Infer the intent and pick notes that would genuinely help now, even without shared words. Prefer notes marked helpful or pinned when relevance is equal.
        Today: \(today). Answer in \(language.promptName).
        "answer": 2–4 short sentences of practical advice built only from the chosen notes; if none fit, say so plainly.
        "ids": the chosen note ids, most relevant first, at most 8.

        Input: \(query)

        Notes (JSON):
        \(json)
        """
    }
}

public struct Filer: Sendable {
    public var client: ClaudeClient

    public init(client: ClaudeClient) {
        self.client = client
    }

    public func file(_ note: Note, folders: [String], image: ClaudeClient.Image?, today: String, language: AppLanguage = .current, memo: Bool = false) async throws -> FilingResult {
        let prompt = Prompts.filing(text: note.text, url: note.url, hasImage: image != nil, folders: folders, today: today, language: language, memo: memo)
        return try await client.json(FilingResult.self, prompt: prompt, schema: Prompts.filingSchema, images: image.map { [$0] } ?? [], effort: .low)
    }

    public func recall(_ query: String, notes: [Note], today: String, language: AppLanguage = .current) async throws -> RecallResult {
        // 多すぎるときは、キーワードで近い順に 150 件まで送る
        let pool = notes.count > 150
            ? notes.sorted { Heuristics.score($0, query: query) > Heuristics.score($1, query: query) }.prefix(150).map { $0 }
            : notes
        let prompt = Prompts.recall(query: query, notes: pool, today: today, language: language)
        var r = try await client.json(RecallResult.self, prompt: prompt, schema: Prompts.recallSchema, effort: .medium)
        let known = Set(notes.map(\.id))
        r.ids = r.ids.filter { known.contains($0) }
        return r
    }
}

extension Note {
    /// 整理の結果を当てはめる。本文は、スクショから読み取ったときだけ置き換える
    public mutating func apply(_ r: FilingResult, replaceText: Bool) {
        if replaceText, !r.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, r.text != text {
            if original == nil { original = text }
            text = r.text
        }
        if !r.title.isEmpty { title = String(r.title.prefix(80)) }
        summary = r.summary
        if !r.category.isEmpty { category = String(r.category.prefix(32)) }
        tags = Array(r.tags.prefix(6))
        situations = Array(r.situations.prefix(5))
        remindAt = Note.validDay(r.remindAt)
        filed = true
    }
}

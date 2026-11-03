// メモの一生: 直す前の内容（履歴）、秘密のメモ、期限つきのメモ、チャットのスクショの読み取り。

import Foundation

/// 直す前のメモの内容
public struct NoteVersion: Codable, Sendable, Hashable {
    public var at: Date
    public var title: String
    public var text: String

    public init(at: Date = Date(), title: String, text: String) {
        self.at = at
        self.title = title
        self.text = text
    }

    enum CodingKeys: String, CodingKey { case at, title, text }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        at = Date(timeIntervalSince1970: ((try? c.decode(Double.self, forKey: .at)) ?? 0) / 1000)
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode((at.timeIntervalSince1970 * 1000).rounded(), forKey: .at)
        try c.encode(title, forKey: .title)
        try c.encode(text, forKey: .text)
    }
}

extension Note {
    public static let historyLimit = 10

    /// 本文かタイトルが変わったら、前の内容を履歴に残す
    mutating func rememberVersion(from before: Note) {
        guard before.text != text || before.title != title else { return }
        let v = NoteVersion(at: before.updatedAt ?? before.createdAt, title: before.title, text: before.text)
        history = Array(([v] + (history ?? [])).prefix(Self.historyLimit))
    }

    public var isLocked: Bool { locked == true }

    /// 期限まであと何日か（期限が無ければ nil）
    public func daysLeft(now: Date = Date()) -> Int? {
        guard let e = expiresAt else { return nil }
        return max(0, Int(ceil(e.timeIntervalSince(now) / 86400)))
    }
}

extension NoteStore {
    /// 履歴の内容に戻す（今の内容も履歴に残る）
    public func restoreVersion(_ id: String, _ v: NoteVersion) {
        update(id) { $0.title = v.title; $0.text = v.text }
    }

    /// 期限が過ぎたメモをゴミ箱へ。移した数を返す
    @discardableResult
    public func purgeExpired(now: Date = Date()) -> Int {
        let gone = notes.filter { ($0.expiresAt ?? .distantFuture) <= now }.map(\.id)
        for id in gone { remove(id) }
        return gone.count
    }
}

extension Heuristics {
    /// チャット（LINE など）のスクショから読み取った文の、画面の飾り（時刻・既読・日付の区切り・入力欄）を除く
    public static func cleanChatText(_ raw: String) -> String {
        let drop = try? NSRegularExpression(pattern: #"^(?:(?:午前|午後)?\s*\d{1,2}[:：]\d{2}|既読(?:\s*\d+)?|Read(?: \d+)?|\d{4}[./年]\d{1,2}[./月]\d{1,2}日?(?:\s*\([^)]*\))?|(?:今日|昨日|Today|Yesterday)|\d{1,2}/\d{1,2}\s*\([^)]*\)|メッセージを入力|Aa|トーク|送信取消.*|.*がメッセージの送信を取り消しました|\d+%|[<＜]\s*\d*)$"#,
                                           options: [.caseInsensitive])
        var out: [String] = []
        for line in raw.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { continue }
            let range = NSRange(t.startIndex..., in: t)
            if drop?.firstMatch(in: t, range: range) != nil { continue }
            // 行の終わりの時刻・既読を外す
            let trimmed = t.replacingOccurrences(of: #"\s*(?:既読\s*\d*)?\s*(?:(?:午前|午後)\s*)?\d{1,2}[:：]\d{2}$"#, with: "", options: .regularExpression)
            if !trimmed.isEmpty, out.last != trimmed { out.append(trimmed) }
        }
        return out.joined(separator: "\n")
    }

    /// チャットのスクショらしいか（時刻や既読の行が多い）
    public static func looksLikeChat(_ raw: String) -> Bool {
        let lines = raw.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 3 else { return false }
        let marks = lines.filter { $0.range(of: #"既読|Read|(?:午前|午後)?\s*\d{1,2}[:：]\d{2}"#, options: .regularExpression) != nil }.count
        return Double(marks) / Double(lines.count) >= 0.2
    }
}

// MARK: カレンダー

/// カレンダーの 1 日に並ぶメモ（しまった日か、予定の日か）
public struct CalendarEntry: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case saved, planned }
    public var note: Note
    public var kind: Kind
}

extension Heuristics {
    /// その月の日ごと（"yyyy-MM-dd"）のメモ: しまった日と、予定（リマインド・今日のリスト・通知・期限）。Web 版と同じ
    public static func calendarDays(_ notes: [Note], month: Date, calendar cal: Calendar = .current) -> [String: [CalendarEntry]] {
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: month)),
              let end = cal.date(byAdding: .month, value: 1, to: start) else { return [:] }
        let startKey = dayFormatter.string(from: start), endKey = dayFormatter.string(from: end)
        var out: [String: [CalendarEntry]] = [:]
        func add(_ key: String, _ n: Note, _ kind: CalendarEntry.Kind) {
            if out[key, default: []].contains(where: { $0.note.id == n.id && $0.kind == kind }) { return }
            out[key, default: []].append(CalendarEntry(note: n, kind: kind))
        }
        for n in notes where !n.example {
            if n.createdAt >= start, n.createdAt < end { add(dayFormatter.string(from: n.createdAt), n, .saved) }
            for d in [n.remindAt, n.plannedDay].compactMap({ $0 }) where d >= startKey && d < endKey { add(d, n, .planned) }
            if let e = n.expiresAt, e >= start, e < end { add(dayFormatter.string(from: e), n, .planned) }
            if let a = n.alarm, a.hasSchedule {
                for t in a.occurrences(after: start.addingTimeInterval(-1), count: 40) {
                    if t >= end { break }
                    add(dayFormatter.string(from: t), n, .planned)
                }
            }
        }
        return out
    }
}

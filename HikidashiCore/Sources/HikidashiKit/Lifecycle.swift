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

// MARK: 時間帯（よく見る時間を覚える）

public enum TimeBucket: String, CaseIterable, Sendable {
    case morning, day, evening, night

    public init(_ date: Date = Date(), calendar cal: Calendar = .current) {
        let h = cal.component(.hour, from: date)
        switch h {
        case 5..<10: self = .morning
        case 10..<17: self = .day
        case 17..<22: self = .evening
        default: self = .night
        }
    }

    public var title: String {
        switch self {
        case .morning: return L("朝によく見るメモ", "Often viewed in the morning")
        case .day: return L("昼によく見るメモ", "Often viewed during the day")
        case .evening: return L("夕方によく見るメモ", "Often viewed in the evening")
        case .night: return L("夜によく見るメモ", "Often viewed at night")
        }
    }

    /// その時間に合う言葉（使う場面・タイトルに含まれていれば少し上げる）
    var words: String {
        switch self {
        case .morning: return "朝|起き|通勤|出勤|出かけ|morning|commute"
        case .day: return "昼|ランチ|仕事|会議|lunch|work|meeting"
        case .evening: return "夕|帰り|買い物|料理|夕飯|evening|dinner|shopping|cook"
        case .night: return "夜|寝|睡眠|お風呂|明日の準備|night|sleep|bath|bed"
        }
    }
}

public enum UsageLog {
    static let key = "usageLog"

    public static func load(_ d: UserDefaults = .standard) -> [String: [String: Int]] {
        (d.dictionary(forKey: key) as? [String: [String: Int]]) ?? [:]
    }

    /// メモを開いた・役立った・チェックした、を時間帯ごとに数える
    public static func record(_ id: String, at date: Date = Date(), _ d: UserDefaults = .standard) {
        var log = load(d)
        let b = TimeBucket(date).rawValue
        log[id, default: [:]][b, default: 0] += 1
        d.set(log, forKey: key)
    }
}

extension Heuristics {
    /// 今の時間によく見るメモ（3 件まで）。Web 版と同じ点数の付け方
    public static func forNow(_ notes: [Note], log: [String: [String: Int]], now: Date = Date()) -> [Note] {
        let b = TimeBucket(now)
        return notes.filter { !$0.example && !$0.isLocked }.compactMap { n -> (Note, Int)? in
            var s = (log[n.id]?[b.rawValue] ?? 0) * 2
            if (n.situations + [n.title]).joined(separator: " ").range(of: b.words, options: [.regularExpression, .caseInsensitive]) != nil { s += 3 }
            return s >= 3 ? (n, s) : nil
        }
        .sorted { $0.1 > $1.1 }
        .prefix(3)
        .map(\.0)
    }
}

// MARK: 場所の種類で知らせる

/// 場所の種類と、そこで役立ちそうなメモの言葉
public struct PlaceKind: Sendable, Equatable {
    public var id: String
    public var label: String
    /// メモのフォルダ・タグ・使う場面・タイトルに当てる言葉
    public var words: String

    public static var all: [PlaceKind] {
        [
            PlaceKind(id: "grocery", label: L("スーパー", "Supermarket"), words: "買い物|スーパー|食材|料理|節約|shopping|grocer|cook"),
            PlaceKind(id: "station", label: L("駅", "Station"), words: "電車|駅|通勤|旅行|おでかけ|新幹線|train|station|commute|travel"),
            PlaceKind(id: "pharmacy", label: L("薬局", "Pharmacy"), words: "薬|健康|風邪|花粉|サプリ|medicine|pharmacy|health"),
            PlaceKind(id: "convenience", label: L("コンビニ", "Convenience store"), words: "コンビニ|支払|振込|宅配|convenience|parcel"),
            PlaceKind(id: "airport", label: L("空港", "Airport"), words: "空港|飛行機|旅行|パスポート|airport|flight|passport"),
            PlaceKind(id: "hospital", label: L("病院", "Hospital"), words: "病院|診察|保険証|hospital|clinic"),
        ]
    }

    /// この種類の場所で役立ちそうなメモ
    public func notes(in notes: [Note]) -> [Note] {
        notes.filter { n in
            !n.example && !n.isLocked &&
            ([n.category, n.title] + n.tags + n.situations).joined(separator: " ").range(of: words, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }
}

// MARK: メモのつながりの図

public struct NoteLink: Sendable, Hashable {
    public var a: String
    public var b: String
    public var weight: Int
}

extension Heuristics {
    /// 同じタグ・使う場面・ハッシュタグを持つメモどうしを結ぶ（Web 版と同じ）。点が多すぎないよう、つながりの多いメモから limit 件
    public static func graph(_ notes: [Note], limit: Int = 40) -> (nodes: [Note], links: [NoteLink]) {
        let pool = notes.filter { !$0.example && !$0.isLocked }
        func keys(_ n: Note) -> Set<String> { Set((n.tags + n.situations).map { $0.lowercased() }) }
        var links: [NoteLink] = []
        var degree: [String: Int] = [:]
        let ks = pool.map(keys)
        for i in pool.indices {
            for j in pool.indices where j > i {
                let w = ks[i].intersection(ks[j]).count
                guard w > 0 else { continue }
                links.append(NoteLink(a: pool[i].id, b: pool[j].id, weight: w))
                degree[pool[i].id, default: 0] += w
                degree[pool[j].id, default: 0] += w
            }
        }
        let keep = Set(pool.filter { degree[$0.id] != nil }.sorted { degree[$0.id]! > degree[$1.id]! }.prefix(limit).map(\.id))
        return (pool.filter { keep.contains($0.id) }, links.filter { keep.contains($0.a) && keep.contains($0.b) })
    }
}

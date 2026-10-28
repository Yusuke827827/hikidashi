// メモのアラーム。決めた日時・何日おき・曜日・毎月に通知する。
// 特定の言葉（keywords）を入力したときに、そのメモを出すこともできる。

import Foundation

public struct Alarm: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        /// 時刻では鳴らさない（言葉だけ）
        case none
        /// 決めた日時に 1 回
        case once
        /// 毎日
        case daily
        /// 何日おき
        case interval
        /// 決めた曜日
        case weekly
        /// 毎月（date の日にち）
        case monthly
    }

    public var kind: Kind
    /// 1 回のときはその日時。ほかは始める日と時刻
    public var date: Date
    /// 何日おき（interval のとき）
    public var intervalDays: Int
    /// 曜日（1 = 日曜 … 7 = 土曜。weekly のとき）
    public var weekdays: [Int]
    /// この言葉を入力したら、このメモを出す
    public var keywords: [String]

    public init(kind: Kind = .once, date: Date = Date(), intervalDays: Int = 3, weekdays: [Int] = [], keywords: [String] = []) {
        self.kind = kind
        self.date = date
        self.intervalDays = max(1, intervalDays)
        self.weekdays = weekdays
        self.keywords = keywords
    }

    enum CodingKeys: String, CodingKey { case kind, date, intervalDays, weekdays, keywords }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .none
        if let ms = try? c.decode(Double.self, forKey: .date) {
            date = Date(timeIntervalSince1970: ms / 1000)
        } else {
            date = Date()
        }
        intervalDays = max(1, (try? c.decode(Int.self, forKey: .intervalDays)) ?? 3)
        weekdays = (try? c.decode([Int].self, forKey: .weekdays)) ?? []
        keywords = (try? c.decode([String].self, forKey: .keywords)) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode((date.timeIntervalSince1970 * 1000).rounded(), forKey: .date)
        try c.encode(intervalDays, forKey: .intervalDays)
        try c.encode(weekdays, forKey: .weekdays)
        try c.encode(keywords, forKey: .keywords)
    }

    /// 時刻で鳴るか
    public var hasSchedule: Bool {
        switch kind {
        case .none: return false
        case .weekly: return !weekdays.isEmpty
        default: return true
        }
    }

    /// これから鳴る日時（近い順に最大 count 件）。毎日・曜日・毎月も同じように数える
    public func occurrences(after now: Date, count: Int, calendar cal: Calendar = .current) -> [Date] {
        guard hasSchedule, count > 0 else { return [] }
        let hm = cal.dateComponents([.hour, .minute], from: date)
        func at(_ day: Date) -> Date? {
            cal.date(bySettingHour: hm.hour ?? 9, minute: hm.minute ?? 0, second: 0, of: day)
        }
        var out: [Date] = []
        switch kind {
        case .none:
            return []
        case .once:
            return date > now ? [date] : []
        case .daily, .weekly, .monthly:
            var day = cal.startOfDay(for: max(now, cal.startOfDay(for: date)))
            var guardCount = 0
            while out.count < count, guardCount < 800 {
                guardCount += 1
                if let t = at(day), t > now, matches(day, cal) { out.append(t) }
                day = cal.date(byAdding: .day, value: 1, to: day)!
            }
        case .interval:
            var day = cal.startOfDay(for: date)
            var guardCount = 0
            while out.count < count, guardCount < 2000 {
                guardCount += 1
                if let t = at(day), t > now { out.append(t) }
                day = cal.date(byAdding: .day, value: intervalDays, to: day)!
            }
        }
        return out
    }

    private func matches(_ day: Date, _ cal: Calendar) -> Bool {
        switch kind {
        case .weekly: return weekdays.contains(cal.component(.weekday, from: day))
        case .monthly: return cal.component(.day, from: day) == cal.component(.day, from: date)
        default: return true
        }
    }

    /// 短い説明（「毎週 月・木 8:00」など）
    public var summary: String {
        let time = Self.timeFormatter.string(from: date)
        let words = keywords.isEmpty ? "" : " · " + keywords.map { "「\($0)」" }.joined()
        switch kind {
        case .none:
            return keywords.isEmpty ? "" : L("言葉で", "On words") + words
        case .once:
            return Self.dateTimeFormatter.string(from: date) + words
        case .daily:
            return L("毎日 ", "Daily ") + time + words
        case .interval:
            return L("\(intervalDays) 日おき ", "Every \(intervalDays) days ") + time + words
        case .weekly:
            let names = weekdays.sorted().map { Self.weekdayName($0) }.joined(separator: L("・", ", "))
            return L("毎週 ", "Weekly ") + names + " " + time + words
        case .monthly:
            let d = Calendar.current.component(.day, from: date)
            return L("毎月 \(d) 日 ", "Monthly on the \(d)th ") + time + words
        }
    }

    public static func weekdayName(_ w: Int) -> String {
        let ja = ["日", "月", "火", "水", "木", "金", "土"]
        let en = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let i = max(1, min(7, w)) - 1
        return L(ja[i], en[i])
    }

    static var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = AppLanguage.current.locale
        f.dateFormat = "H:mm"
        return f
    }

    static var dateTimeFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = AppLanguage.current.locale
        f.setLocalizedDateFormatFromTemplate("MdEHmm")
        return f
    }
}

extension Heuristics {
    /// 入力した文に、アラームの言葉が入っているメモ
    public static func keywordAlarms(_ notes: [Note], text: String) -> [Note] {
        let t = text.lowercased()
        guard !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return notes.filter { n in
            guard let words = n.alarm?.keywords, !words.isEmpty else { return false }
            return words.contains { w in
                let k = w.trimmingCharacters(in: .whitespaces).lowercased()
                return !k.isEmpty && t.contains(k)
            }
        }
    }

    /// 通知の予約（近い順に最大 limit 件）。何日おき・1 回は日時を、毎日・曜日・毎月は繰り返しで予約する
    public static func alarmSchedule(_ notes: [Note], now: Date = Date(), limit: Int = 24) -> [(note: Note, fireAt: Date)] {
        var all: [(note: Note, fireAt: Date)] = []
        for n in notes {
            guard let a = n.alarm, a.hasSchedule else { continue }
            // 何日おきは先の 3 回分を予約し、アプリを開くたびに作り直す
            let count = a.kind == .interval ? 3 : 1
            for d in a.occurrences(after: now, count: count) { all.append((note: n, fireAt: d)) }
        }
        return Array(all.sorted { $0.fireAt < $1.fireAt }.prefix(limit))
    }
}

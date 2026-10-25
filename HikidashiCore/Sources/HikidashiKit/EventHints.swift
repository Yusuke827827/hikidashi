// 予定の前に、関係するメモを知らせるための計画。予定の中身は端末の中だけで使う。
// 例: 予定「大阪出張」→ 使う場面「出張の準備」のメモを、前の日の夜 8 時に知らせる。

import Foundation

public struct EventInfo: Sendable, Equatable {
    public var id: String
    public var title: String
    public var start: Date
    public var isAllDay: Bool

    public init(id: String, title: String, start: Date, isAllDay: Bool = false) {
        self.id = id
        self.title = title
        self.start = start
        self.isAllDay = isAllDay
    }
}

public struct EventHint: Sendable, Equatable {
    public var event: EventInfo
    public var notes: [Note]
    public var fireAt: Date
}

public enum EventHints {
    /// 予定ごとに関係するメモ（最大 2 件）と知らせる日時を決める。メモが無い予定は飛ばす。
    /// 知らせるのは、予定の前の日の夜 eveningHour 時。それが過ぎていれば予定の 2 時間前（終日の予定は当日の朝 8 時）
    public static func plan(events: [EventInfo], notes: [Note], now: Date = Date(), eveningHour: Int = 20, limit: Int = 10) -> [EventHint] {
        let cal = Calendar.current
        let pool = notes.filter { !$0.example }
        var out: [EventHint] = []
        for e in events.sorted(by: { $0.start < $1.start }) where e.start > now {
            let matches = pool
                .map { ($0, Heuristics.score($0, query: e.title)) }
                .filter { $0.1 >= 1 }
                .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.helpful > $1.0.helpful }
                .prefix(2)
                .map(\.0)
            guard !matches.isEmpty else { continue }
            let dayBefore = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: e.start)).flatMap {
                cal.date(bySettingHour: eveningHour, minute: 0, second: 0, of: $0)
            }
            var fire: Date?
            if let d = dayBefore, d > now {
                fire = d
            } else if e.isAllDay {
                fire = cal.date(bySettingHour: 8, minute: 0, second: 0, of: e.start).flatMap { $0 > now ? $0 : nil }
            } else {
                let twoHours = e.start.addingTimeInterval(-2 * 3600)
                fire = twoHours > now ? twoHours : nil
            }
            guard let fireAt = fire else { continue }
            out.append(EventHint(event: e, notes: matches, fireAt: fireAt))
            if out.count >= limit { break }
        }
        return out
    }
}

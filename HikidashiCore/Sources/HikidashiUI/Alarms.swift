// メモの通知。音は鳴らさず、ロック画面と通知センターに出すだけ（アプリでは「今日の確認リスト」に並ぶ）。
// 毎日・曜日・毎月は iOS の繰り返しで、1 回と何日おきは日時で予約する（アプリを開くたびに作り直す）。

#if os(iOS)
import Foundation
import HikidashiKit
import UserNotifications

@MainActor
enum Alarms {
    static let idPrefix = "hikidashi.alarm."
    /// iOS が予約できる 64 件のうち、アラームに使う数
    static let budget = 23

    static func sync(_ notes: [Note]) async {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        await scheduleWeekly(center, hasNotes: !notes.isEmpty)

        let requests = makeRequests(notes)
        guard !requests.isEmpty else { return }
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .badge])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        for r in requests { try? await center.add(r) }
    }

    static func makeRequests(_ notes: [Note], now: Date = Date()) -> [UNNotificationRequest] {
        let cal = Calendar.current
        // 近く鳴る順に並べ、予算に収まるまで入れる
        let order = Heuristics.alarmSchedule(notes, now: now, limit: 500)
        var seen = Set<String>()
        var out: [UNNotificationRequest] = []
        for item in order {
            guard out.count < budget, let a = item.note.alarm else { break }
            let n = item.note
            let hm = cal.dateComponents([.hour, .minute], from: a.date)
            switch a.kind {
            case .none:
                continue
            case .once, .interval:
                let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireAt)
                out.append(request(n, id: "\(n.id).\(Int(item.fireAt.timeIntervalSince1970))", trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
            case .daily:
                guard seen.insert(n.id).inserted else { continue }
                out.append(request(n, id: n.id, trigger: UNCalendarNotificationTrigger(dateMatching: hm, repeats: true)))
            case .weekly:
                guard seen.insert(n.id).inserted else { continue }
                for w in a.weekdays.sorted() where out.count < budget {
                    var c = hm
                    c.weekday = w
                    out.append(request(n, id: "\(n.id).w\(w)", trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: true)))
                }
            case .monthly:
                guard seen.insert(n.id).inserted else { continue }
                var c = hm
                c.day = cal.component(.day, from: a.date)
                out.append(request(n, id: n.id, trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: true)))
            }
        }
        return out
    }

    /// 週の振り返り: 毎週日曜の夜 7 時に、音なしで知らせる
    static let weeklyID = "hikidashi.weekly"
    static func scheduleWeekly(_ center: UNUserNotificationCenter, hasNotes: Bool) async {
        center.removePendingNotificationRequests(withIdentifiers: [weeklyID])
        guard hasNotes, await center.notificationSettings().authorizationStatus == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = L("今週のふりかえり", "Your week in Mindrawer")
        content.body = L("今週しまったメモと、しまったままのメモを見てみましょう。", "See what you saved this week and the tips you haven't looked at.")
        content.sound = nil
        var c = DateComponents()
        c.weekday = 1
        c.hour = 19
        try? await center.add(UNNotificationRequest(identifier: weeklyID, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: true)))
    }

    private static func request(_ n: Note, id: String, trigger: UNNotificationTrigger) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "🔔 " + n.title
        content.body = n.summary.isEmpty ? String(n.text.prefix(140)) : n.summary
        // 音は鳴らさない（見えるだけ）
        content.sound = nil
        content.interruptionLevel = .active
        content.userInfo = ["noteID": n.id]
        return UNNotificationRequest(identifier: idPrefix + id, content: content, trigger: trigger)
    }

    /// 予約に関わる部分だけ。変わったときに作り直す（何日おきは日付が変わるたびにも）
    static func signature(_ notes: [Note]) -> String {
        let day = Heuristics.dayFormatter.string(from: Date())
        return day + "\n" + notes.compactMap { n in
            guard let a = n.alarm, a.hasSchedule else { return nil }
            return "\(n.id)|\(a.kind.rawValue)|\(a.date.timeIntervalSince1970)|\(a.intervalDays)|\(a.weekdays)|\(n.title)"
        }.sorted().joined(separator: "\n")
    }
}
#endif

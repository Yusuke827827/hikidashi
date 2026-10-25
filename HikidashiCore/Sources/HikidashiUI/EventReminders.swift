// 予定の前に関係するメモを知らせる（設定でオンにしたときだけ）。予定は端末の中で読むだけで、どこにも送らない。
// 3 日先までの予定を見て、関係するメモがあれば前の日の夜に通知する。通知を押すと、予定の名前で「ひきだす」。

#if os(iOS)
import EventKit
import Foundation
import HikidashiKit
import UserNotifications

@MainActor
enum EventReminders {
    static let idPrefix = "hikidashi.event."
    static let settingKey = "calendarHints"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: settingKey) }

    /// オンにするときに呼ぶ。予定と通知の許可を求め、許可されたら true
    static func enable() async -> Bool {
        let store = EKEventStore()
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        if granted {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
        UserDefaults.standard.set(granted, forKey: settingKey)
        return granted
    }

    static func disable() async {
        UserDefaults.standard.set(false, forKey: settingKey)
        await clear()
    }

    static func clear() async {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
    }

    /// 予約し直す（アプリを開くたび）
    static func sync(_ notes: [Note]) async {
        await clear()
        guard isOn, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        let store = EKEventStore()
        let now = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: 3, to: now) else { return }
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let events = store.events(matching: predicate).compactMap { e -> EventInfo? in
            guard let title = e.title, !title.isEmpty, let start = e.startDate else { return nil }
            return EventInfo(id: e.calendarItemIdentifier, title: title, start: start, isAllDay: e.isAllDay)
        }
        let center = UNUserNotificationCenter.current()
        for hint in EventHints.plan(events: events, notes: notes, now: now) {
            let content = UNMutableNotificationContent()
            content.title = L("「\(hint.event.title)」の前に", "Before \"\(hint.event.title)\"")
            content.body = hint.notes.map { "・" + $0.title }.joined(separator: "\n")
            content.sound = .default
            content.userInfo = ["recallQuery": hint.event.title]
            let when = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: hint.fireAt)
            let request = UNNotificationRequest(identifier: idPrefix + hint.event.id, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
            try? await center.add(request)
        }
    }
}
#endif

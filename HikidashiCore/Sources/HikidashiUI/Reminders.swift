// リマインド日の通知。メモのリマインド日の朝 9 時に、端末の中だけで通知を出す（サーバーは使わない）。
// メモが変わるたびに予約を作り直す。通知を押すと、そのメモを開く。

#if os(iOS)
import Foundation
import HikidashiKit
import Observation
import UserNotifications

@MainActor
enum Reminders {
    static let idPrefix = "hikidashi.remind."

    /// 予約し直す。リマインド日のあるメモが初めて現れたときだけ、通知の許可を求める
    static func sync(_ notes: [Note]) async {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)

        // iOS が予約できる通知は 64 件まで。予定の前の知らせ（最大 10 件）の分を空けておく
        let plan = Heuristics.reminderSchedule(notes, limit: 50)
        guard !plan.isEmpty else { return }

        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        for item in plan {
            let content = UNMutableNotificationContent()
            content.title = item.note.title
            content.body = item.note.summary.isEmpty ? String(item.note.text.prefix(120)) : item.note.summary
            content.subtitle = L("今日のリマインド", "Reminder for today")
            content.sound = .default
            content.userInfo = ["noteID": item.note.id]
            let when = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireAt)
            let request = UNNotificationRequest(identifier: idPrefix + item.note.id, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
            try? await center.add(request)
        }
    }

    /// 予約内容に関わる部分だけを並べた文字列。これが変わったときだけ予約し直す
    static func signature(_ notes: [Note]) -> String {
        notes.compactMap { n in n.remindAt.map { "\(n.id)|\($0)|\(n.title)" } }.sorted().joined(separator: "\n")
    }
}

/// 通知を押したときに開くメモを画面へ伝える
@MainActor
@Observable
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    var openNoteID: String?
    /// 予定の前の知らせを押したときの「ひきだす」の問い
    var recallQuery: String?

    // アプリを開いている間に届いた通知も表示する
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        if let q = info["recallQuery"] as? String {
            await MainActor.run { NotificationRouter.shared.recallQuery = q }
            return
        }
        guard let id = info["noteID"] as? String else { return }
        await MainActor.run { NotificationRouter.shared.openNoteID = id }
    }
}
#endif

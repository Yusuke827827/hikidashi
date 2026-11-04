// iPhone 側の Apple Watch とのやりとり。「今日の確認リスト」と「今日のひとつ」を Watch に送り、
// Watch で付けたチェックを受け取って保存する。

#if os(iOS) && canImport(WatchConnectivity)
import HikidashiKit
import WatchConnectivity
import WidgetKit

@MainActor
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()
    private weak var store: NoteStore?

    func start(store: NoteStore) {
        self.store = store
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        if WCSession.default.activationState != .activated { WCSession.default.activate() }
        send()
    }

    /// 今の内容を Watch に送る（Watch がつながっていなければ何もしない）
    func send() {
        guard let store, WCSession.isSupported() else { return }
        let s = WCSession.default
        guard s.activationState == .activated, s.isPaired, s.isWatchAppInstalled else { return }
        let now = Date()
        let day = Heuristics.dayFormatter.string(from: now)
        let items: [[String: Any]] = Heuristics.todayList(store.notes, now: now).map { i in
            var d: [String: Any] = ["id": i.note.id, "title": i.note.title, "checked": store.isChecked(i.note.id, day: day)]
            if let t = i.time { d["time"] = t.timeIntervalSince1970 }
            return d
        }
        var ctx: [String: Any] = ["day": day, "items": items, "sent": now.timeIntervalSince1970]
        if let pick = Heuristics.todaysPick(store.notes, now: now) {
            ctx["pickTitle"] = pick.title
            ctx["pickSummary"] = pick.summary
        }
        try? s.updateApplicationContext(ctx)
    }

    private func handle(_ msg: [String: Any]) {
        // Watch で話したメモは、受け取り箱に置く（アプリを開いたとき・次の更新で整理される）
        if let text = msg["save"] as? String, let store {
            _ = try? Inbox.put(text: text, url: nil, comment: "", image: nil, root: store.root)
            NotificationRouter.shared.inboxArrived += 1
            return
        }
        guard let id = msg["toggle"] as? String, let day = msg["day"] as? String, let store else { return }
        store.toggleCheck(id, day: day)
        WidgetCenter.shared.reloadAllTimelines()
        send()
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.send() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.handle(message) }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in self.handle(userInfo) }
    }
}
#endif

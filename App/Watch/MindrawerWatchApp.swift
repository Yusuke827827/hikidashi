// Apple Watch の Mindrawer。iPhone から届いた「今日の確認リスト」と「今日のひとつ」を出し、腕の上でチェックできる。
// メモは iPhone にあり、Watch は WatchConnectivity で受け取った分だけを持つ。チェックは iPhone に送り返す。

import SwiftUI
import WatchConnectivity

struct WatchItem: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var time: Double?
    var checked: Bool
}

@MainActor
final class WatchModel: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchModel()
    @Published var day = ""
    @Published var items: [WatchItem] = []
    @Published var pickTitle = ""
    @Published var pickSummary = ""

    private let key = "watchContext"

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: key), let ctx = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { apply(ctx) }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    var done: Int { items.filter(\.checked).count }

    func apply(_ ctx: [String: Any]) {
        day = ctx["day"] as? String ?? ""
        pickTitle = ctx["pickTitle"] as? String ?? ""
        pickSummary = ctx["pickSummary"] as? String ?? ""
        if let raw = ctx["items"] as? [[String: Any]],
           let data = try? JSONSerialization.data(withJSONObject: raw),
           let list = try? JSONDecoder().decode([WatchItem].self, from: data) {
            items = list
        }
        if let data = try? JSONSerialization.data(withJSONObject: ctx) { UserDefaults.standard.set(data, forKey: key) }
    }

    func toggle(_ item: WatchItem) {
        guard let i = items.firstIndex(of: item) else { return }
        items[i].checked.toggle()
        let msg: [String: Any] = ["toggle": item.id, "day": day]
        let s = WCSession.default
        guard s.activationState == .activated else { return }
        if s.isReachable {
            s.sendMessage(msg, replyHandler: nil) { _ in s.transferUserInfo(msg) }
        } else {
            s.transferUserInfo(msg)
        }
    }

    @Published var lastSaved = ""

    /// 話した（書いた）メモを iPhone に送る。iPhone が近くになくても、つながったときに届く
    func save(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let msg: [String: Any] = ["save": t, "at": Date().timeIntervalSince1970]
        let s = WCSession.default
        guard s.activationState == .activated else { return }
        s.transferUserInfo(msg)
        lastSaved = t
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let ctx = session.receivedApplicationContext
        guard !ctx.isEmpty else { return }
        Task { @MainActor in self.apply(ctx) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }
}

@main
struct MindrawerWatchApp: App {
    @StateObject private var model = WatchModel.shared

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    Section {
                        TextFieldLink(prompt: Text("しまうことを話す")) {
                            Label("話してしまう", systemImage: "mic.fill")
                        } onSubmit: { text in
                            model.save(text)
                        }
                        if !model.lastSaved.isEmpty {
                            Text("しまいました: \(model.lastSaved)").font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    Section {
                        if model.items.isEmpty {
                            Text(model.day.isEmpty ? "iPhone の Mindrawer を開いてください" : "今日確認するメモはありません")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(model.items) { item in
                            Button { model.toggle(item) } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(item.checked ? Color.orange : Color.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title).strikethrough(item.checked).foregroundStyle(item.checked ? .secondary : .primary)
                                        if let t = item.time {
                                            Text(Date(timeIntervalSince1970: t), style: .time).font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("今日の確認 \(model.done)/\(model.items.count)")
                    }
                    if !model.pickTitle.isEmpty {
                        Section("今日のひとつ") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.pickTitle).font(.headline)
                                if !model.pickSummary.isEmpty { Text(model.pickSummary).font(.footnote).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                .navigationTitle("Mindrawer")
            }
        }
    }
}

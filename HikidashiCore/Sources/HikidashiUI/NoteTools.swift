// メモの道具: 秘密のメモを開く、読み上げ、編集の履歴、つながりの図、今の時間によく見るメモ、場所の種類で知らせる。

#if os(iOS)
import AVFoundation
import CoreLocation
import HikidashiKit
import MapKit
import SwiftUI
import UserNotifications

// MARK: 秘密のメモ

/// 開いた秘密のメモ（アプリを離れたら閉じる）
@MainActor
@Observable
final class SecretNotes {
    static let shared = SecretNotes()
    private(set) var unlocked: Set<String> = []

    func isHidden(_ note: Note) -> Bool { note.isLocked && !unlocked.contains(note.id) }

    func unlock(_ id: String) async {
        if await AppLock.authenticate(reason: L("秘密のメモを開く", "Open the secret note")) { unlocked.insert(id) }
    }

    func closeAll() { unlocked.removeAll() }
}

// MARK: 読み上げ

@MainActor
final class Speaker {
    static let shared = Speaker()
    private let synth = AVSpeechSynthesizer()
    private(set) var speakingID: String?

    func toggle(_ note: Note) {
        if synth.isSpeaking {
            let same = speakingID == note.id
            synth.stopSpeaking(at: .immediate)
            speakingID = nil
            if same { return }
        }
        let u = AVSpeechUtterance(string: note.title + "。\n" + note.text)
        let ja = note.text.range(of: #"[\p{Hiragana}\p{Katakana}\p{Han}]"#, options: .regularExpression) != nil
        u.voice = AVSpeechSynthesisVoice(language: ja ? "ja-JP" : "en-US")
        speakingID = note.id
        synth.speak(u)
    }
}

// MARK: 編集の履歴

struct HistorySheet: View {
    let note: Note
    let store: NoteStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var p

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.title).font(.headline)
                        Text(note.text).font(.footnote).foregroundStyle(.secondary).lineLimit(4)
                    }
                } header: { Text(L("今の内容", "Current")) }
                Section {
                    ForEach(Array((note.history ?? []).enumerated()), id: \.offset) { _, v in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(v.at, format: .dateTime.year().month().day().hour().minute())
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Text(v.title).font(.subheadline.weight(.semibold))
                            Text(v.text).font(.footnote).foregroundStyle(.secondary).lineLimit(6)
                            Button(L("この内容に戻す", "Restore this version")) {
                                store.restoreVersion(note.id, v)
                                dismiss()
                            }
                            .font(.footnote.weight(.semibold))
                            .tint(p.accent)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text(L("前の内容（新しい順・\(Note.historyLimit) 件まで）", "Earlier versions (newest first, up to \(Note.historyLimit))"))
                }
            }
            .navigationTitle(L("編集の履歴", "Edit history"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("閉じる", "Done")) { dismiss() } } }
        }
    }
}

// MARK: つながりの図

struct GraphSheet: View {
    let store: NoteStore
    var onOpen: (Note) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var p

    var body: some View {
        NavigationStack {
            let g = Heuristics.graph(store.notes)
            Group {
                if g.nodes.count < 2 {
                    ContentUnavailableView(L("まだつながりがありません", "No connections yet"), systemImage: "point.3.connected.trianglepath.dotted",
                                           description: Text(L("同じタグや使う場面のメモが増えると、ここに線で結ばれます。", "Notes sharing tags or moments get linked here.")))
                } else {
                    GeometryReader { geo in
                        let pos = layout(g.nodes, size: geo.size)
                        ZStack {
                            Canvas { ctx, _ in
                                for l in g.links {
                                    guard let a = pos[l.a], let b = pos[l.b] else { continue }
                                    var path = Path()
                                    path.move(to: a)
                                    path.addLine(to: b)
                                    ctx.stroke(path, with: .color(p.line), lineWidth: CGFloat(min(4, l.weight)))
                                }
                            }
                            ForEach(g.nodes) { n in
                                let color = Looks.color(store.folderLook(n.category.isEmpty ? Heuristics.otherFolder : n.category).color)
                                Button {
                                    dismiss()
                                    onOpen(n)
                                } label: {
                                    VStack(spacing: 3) {
                                        Circle().fill(color).frame(width: 14, height: 14)
                                        Text(n.title).font(.caption2).foregroundStyle(p.text).lineLimit(1).frame(maxWidth: 90)
                                    }
                                }
                                .buttonStyle(.plain)
                                .position(pos[n.id] ?? .zero)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .background(p.bg.ignoresSafeArea())
            .navigationTitle(L("つながりの図", "Connections"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("閉じる", "Done")) { dismiss() } } }
        }
    }

    /// フォルダごとにまとまるよう、円の上に並べる（フォルダ順・その中は名前順）
    private func layout(_ nodes: [Note], size: CGSize) -> [String: CGPoint] {
        let sorted = nodes.sorted { ($0.category, $0.title) < ($1.category, $1.title) }
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let r = max(40, min(size.width, size.height) / 2 - 30)
        var out: [String: CGPoint] = [:]
        for (i, n) in sorted.enumerated() {
            let a = Double(i) / Double(sorted.count) * 2 * .pi - .pi / 2
            // 交互に内側へずらして文字が重なりにくくする
            let rr = i % 2 == 0 ? r : r * 0.72
            out[n.id] = CGPoint(x: c.x + rr * cos(a), y: c.y + rr * sin(a))
        }
        return out
    }
}

// MARK: 今の時間によく見るメモ

struct NowCard: View {
    let notes: [Note]
    var onOpen: (Note) -> Void
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(TimeBucket().title, systemImage: "clock").font(.subheadline.weight(.bold)).foregroundStyle(p.text)
            ForEach(notes) { n in
                Button { onOpen(n) } label: {
                    HStack {
                        Text(n.title).font(.subheadline).foregroundStyle(p.text).lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(p.muted)
                    }
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }
}

// MARK: 場所の種類で知らせる

/// 近くのスーパー・駅・薬局などに着いたら、そこで役立つメモを知らせる（iOS が見張り、アプリは位置を記録しない）
@MainActor
enum PlaceKindAlerts {
    static let settingKey = "placeKindAlerts"
    static let idPrefix = "hikidashi.kind."
    private static let manager = CLLocationManager()
    private static var lastSync: Date?

    static var isOn: Bool { UserDefaults.standard.bool(forKey: settingKey) }

    static func setOn(_ on: Bool, notes: [Note]) async {
        UserDefaults.standard.set(on, forKey: settingKey)
        if on { PlaceReminders.requestPermission() }
        lastSync = nil
        await sync(notes)
    }

    static func category(_ kind: PlaceKind) -> [MKPointOfInterestCategory] {
        switch kind.id {
        case "grocery": return [.foodMarket]
        case "station": return [.publicTransport]
        case "pharmacy": return [.pharmacy]
        case "convenience": return [.store]
        case "airport": return [.airport]
        case "hospital": return [.hospital]
        default: return []
        }
    }

    /// 今いる辺りの、その種類の場所（近い順に数か所）を通知に登録し直す。1 時間に 1 回まで
    static func sync(_ notes: [Note]) async {
        let center = UNUserNotificationCenter.current()
        guard isOn else {
            let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)
            return
        }
        if let t = lastSync, Date().timeIntervalSince(t) < 3600 { return }
        guard PlaceReminders.authorized, let here = manager.location?.coordinate else { return }
        lastSync = Date()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        var budget = 8 // 場所の通知は iOS 全体で 20 件まで。メモの場所のぶんを残す
        for kind in PlaceKind.all {
            let matched = kind.notes(in: notes)
            guard !matched.isEmpty, budget > 0 else { continue }
            let req = MKLocalPointsOfInterestRequest(center: here, radius: 3000)
            req.pointOfInterestFilter = MKPointOfInterestFilter(including: category(kind))
            let items = (try? await MKLocalSearch(request: req).start().mapItems) ?? []
            for (i, item) in items.prefix(2).enumerated() where budget > 0 {
                let c = item.placemark.coordinate
                let id = idPrefix + kind.id + ".\(i)"
                let region = CLCircularRegion(center: c, radius: 120, identifier: id)
                region.notifyOnEntry = true
                region.notifyOnExit = false
                let content = UNMutableNotificationContent()
                content.title = L("\(kind.label)に着きました", "At a \(kind.label.lowercased())")
                content.body = matched.prefix(3).map(\.title).joined(separator: "・")
                content.sound = .default
                if let first = matched.first { content.userInfo = ["noteID": first.id] }
                try? await center.add(UNNotificationRequest(identifier: id, content: content,
                                                            trigger: UNLocationNotificationTrigger(region: region, repeats: true)))
                budget -= 1
            }
        }
    }
}
#endif

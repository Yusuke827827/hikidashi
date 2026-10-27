// 場所で知らせる。メモに付けた場所に着いたら通知する（iOS が見張り、アプリは位置を記録しない）。

#if os(iOS)
import CoreLocation
import Foundation
import HikidashiKit
import MapKit
import SwiftUI
import UserNotifications

@MainActor
enum PlaceReminders {
    static let idPrefix = "hikidashi.place."
    private static let manager = CLLocationManager()

    static var authorized: Bool {
        let s = manager.authorizationStatus
        return s == .authorizedWhenInUse || s == .authorizedAlways
    }

    /// 場所を付けるときに呼ぶ（位置情報と通知の許可を求める）
    static func requestPermission() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    }

    /// 予約し直す
    static func sync(_ notes: [Note]) async {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        guard authorized else { return }
        for n in Heuristics.placeNotes(notes) {
            guard let p = n.place else { continue }
            let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude),
                                          radius: max(100, p.radius), identifier: idPrefix + n.id)
            region.notifyOnEntry = true
            region.notifyOnExit = false
            let content = UNMutableNotificationContent()
            content.title = "📍 " + p.name
            content.body = n.title
            content.sound = .default
            content.userInfo = ["noteID": n.id]
            let request = UNNotificationRequest(identifier: idPrefix + n.id, content: content,
                                                trigger: UNLocationNotificationTrigger(region: region, repeats: true))
            try? await center.add(request)
        }
    }

    static func signature(_ notes: [Note]) -> String {
        Heuristics.placeNotes(notes).compactMap { n in n.place.map { "\(n.id)|\($0.latitude)|\($0.longitude)|\(n.title)" } }.joined(separator: "\n")
    }
}

/// 場所を探して選ぶ画面
struct PlaceSearchView: View {
    var onPick: (Place) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searching = false

    var body: some View {
        List {
            Section {
                HStack {
                    TextField(L("店名・住所・駅など", "Store, address, station…"), text: $query)
                        .submitLabel(.search)
                        .onSubmit { Task { await search() } }
                    if searching { ProgressView() }
                }
            } footer: {
                Text(L("この場所に着いたら、iPhone が通知します（半径 150m ほど）。位置情報は iPhone が見張るだけで、アプリは記録しません。",
                       "When you arrive near this place (about 150 m), your iPhone notifies you. iOS watches the location; the app doesn't record it."))
            }
            ForEach(results, id: \.self) { item in
                Button {
                    let c = item.placemark.coordinate
                    onPick(Place(name: item.name ?? query, latitude: c.latitude, longitude: c.longitude))
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name ?? "").foregroundStyle(.primary)
                        Text(item.placemark.title ?? "").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(L("場所を選ぶ", "Choose a place"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { PlaceReminders.requestPermission() }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        defer { searching = false }
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = q
        results = (try? await MKLocalSearch(request: req).start().mapItems) ?? []
    }
}
#endif

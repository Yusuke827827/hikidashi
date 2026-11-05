// 少しずつ出すヒント・機能を探す（コマンドパレット）・共有フォルダのコメント・印刷・週のまとめの知らせ。

#if os(iOS)
import HikidashiKit
import SwiftUI
import UIKit
import UserNotifications

// MARK: ヒント

struct TipCard: View {
    let tip: FeatureTip
    var onDone: () -> Void
    @Environment(\.palette) private var p

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: tip.symbol).font(.title3).foregroundStyle(p.accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("ヒント: ", "Tip: ") + tip.title).font(.subheadline.weight(.bold)).foregroundStyle(p.text)
                Text(tip.body).font(.footnote).foregroundStyle(p.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button { onDone() } label: { Image(systemName: "xmark").font(.caption.weight(.bold)).frame(width: 30, height: 30) }
                .foregroundStyle(p.muted)
                .accessibilityLabel(L("わかった", "Got it"))
        }
        .card(padding: 14)
    }
}

// MARK: 機能を探す

struct PaletteAction: Identifiable {
    let id: String
    let title: String
    let symbol: String
    /// 探すときの言葉（日本語・英語）
    let keywords: String
    let run: () -> Void
}

/// 機能の名前やメモの言葉で探して、すぐ開く
struct CommandPalette: View {
    let actions: [PaletteAction]
    let store: NoteStore
    var onOpen: (Note) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var focused: Bool

    private var q: String { query.trimmingCharacters(in: .whitespaces).lowercased() }

    var body: some View {
        NavigationStack {
            List {
                let acts = q.isEmpty ? actions : actions.filter { ($0.title + " " + $0.keywords).lowercased().contains(q) }
                if !acts.isEmpty {
                    Section(L("機能", "Features")) {
                        ForEach(acts) { a in
                            Button {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { a.run() }
                            } label: {
                                Label(a.title, systemImage: a.symbol).foregroundStyle(.primary)
                            }
                        }
                    }
                }
                if !q.isEmpty {
                    let hits = store.notes.filter { $0.archived != true && store.haystack($0).contains(q) }.prefix(8)
                    if !hits.isEmpty {
                        Section(L("メモ", "Notes")) {
                            ForEach(Array(hits)) { n in
                                Button {
                                    dismiss()
                                    onOpen(n)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(n.title).foregroundStyle(.primary)
                                        Text(n.category).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    if acts.isEmpty && hits.isEmpty {
                        Text(L("見つかりませんでした。", "Nothing found.")).foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: L("機能やメモを探す（例: ボード・同期・印刷）", "Find a feature or note (board, sync, print…)"))
            .navigationTitle(L("探す", "Find"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("閉じる", "Done")) { dismiss() } } }
        }
    }
}

// MARK: 共有フォルダのコメント

struct CommentsView: View {
    let note: Note
    let store: NoteStore
    @Environment(\.palette) private var p
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("コメント", "Comments").uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(p.muted).tracking(1)
            ForEach(note.comments ?? []) { c in
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.text).font(.footnote).foregroundStyle(p.text)
                    Text(c.by + " · " + c.at.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(p.muted)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(p.surface2))
            }
            HStack {
                TextField(L("ひとこと（例: 買っておいたよ）", "Add a comment (e.g. Bought it)"), text: $text)
                    .font(.footnote)
                    .submitLabel(.send)
                    .onSubmit(send)
                Button(L("送る", "Send"), action: send).font(.footnote.weight(.semibold))
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func send() {
        store.addComment(note.id, text: text, by: Librarian.shareName)
        text = ""
    }
}

// MARK: 印刷・PDF

@MainActor
enum NotePrinter {
    /// 印刷の画面を出す（「PDF として保存」や共有もここから）
    static func print(_ notes: [Note], title: String) {
        let c = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = title
        c.printInfo = info
        c.printFormatter = UIMarkupTextPrintFormatter(markupText: NotePrint.html(notes))
        c.present(animated: true)
    }
}

// MARK: 週のまとめの知らせ（月曜の朝 8 時）

@MainActor
enum WeeklyDigestNotice {
    static let settingKey = "weeklyDigest"
    static let id = "hikidashi.weekly"
    static var isOn: Bool { UserDefaults.standard.bool(forKey: settingKey) }

    /// 今の内容で、次の月曜の知らせを予約し直す（アプリを開くたび）
    static func sync(_ notes: [Note]) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard isOn, let d = Heuristics.weeklyDigest(notes) else { return }
        let content = UNMutableNotificationContent()
        content.title = d.title
        content.body = d.body
        content.sound = .default
        var when = DateComponents()
        when.weekday = 2
        when.hour = 8
        when.minute = 3
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false)))
    }

    static func setOn(_ on: Bool, notes: [Note]) async {
        UserDefaults.standard.set(on, forKey: settingKey)
        if on { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        await sync(notes)
    }
}
#endif

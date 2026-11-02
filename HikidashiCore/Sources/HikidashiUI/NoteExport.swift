// メモを外に出す: iPhone のカレンダー・リマインダーに入れる、1 枚だけの公開リンクを作る。

#if os(iOS)
import EventKit
import HikidashiKit
import SwiftUI

enum CalendarExport {
    static let store = EKEventStore()

    /// メモの日付（通知 → リマインド日）を、カレンダーの予定にする
    static func addEvent(_ n: Note) async -> String {
        guard let (start, allDay) = when(n) else { return L("このメモには日付がありません。通知かリマインド日を決めてください。", "This note has no date. Set a notification or reminder date first.") }
        do {
            guard try await store.requestWriteOnlyAccessToEvents() else { return denied }
            let e = EKEvent(eventStore: store)
            e.title = n.title
            e.notes = [n.summary, n.text].filter { !$0.isEmpty }.joined(separator: "\n\n")
            e.url = n.url.flatMap(URL.init(string:))
            e.isAllDay = allDay
            e.startDate = start
            e.endDate = allDay ? start : start.addingTimeInterval(15 * 60)
            e.calendar = store.defaultCalendarForNewEvents
            try store.save(e, span: .thisEvent)
            return L("カレンダーに入れました。", "Added to Calendar.")
        } catch {
            return L("カレンダーに入れられませんでした。", "Couldn't add to Calendar.")
        }
    }

    /// メモをリマインダー App に入れる（日付があれば期限にする）
    static func addReminder(_ n: Note) async -> String {
        do {
            guard try await store.requestFullAccessToReminders() else { return denied }
            let r = EKReminder(eventStore: store)
            r.title = n.title
            r.notes = n.text
            r.url = n.url.flatMap(URL.init(string:))
            r.calendar = store.defaultCalendarForNewReminders()
            if let (d, allDay) = when(n) {
                let comps: Set<Calendar.Component> = allDay ? [.year, .month, .day] : [.year, .month, .day, .hour, .minute]
                r.dueDateComponents = Calendar.current.dateComponents(comps, from: d)
                if !allDay { r.addAlarm(EKAlarm(absoluteDate: d)) }
            }
            try store.save(r, commit: true)
            return L("リマインダーに入れました。", "Added to Reminders.")
        } catch {
            return L("リマインダーに入れられませんでした。", "Couldn't add to Reminders.")
        }
    }

    static let denied = L("許可されませんでした。iPhone の「設定」→「プライバシー」で許可できます。", "Access wasn't allowed. You can allow it in Settings → Privacy.")

    static func when(_ n: Note) -> (Date, Bool)? {
        if let a = n.alarm, a.hasSchedule, let next = a.occurrences(after: Date(), count: 1).first { return (next, false) }
        if let r = n.remindAt, let d = Heuristics.dayFormatter.date(from: r) { return (d, true) }
        return nil
    }
}

/// 1 枚だけの公開リンク
struct PublicLinkSheet: View {
    let note: Note
    @Environment(\.dismiss) private var dismiss
    @State private var link: PublicLink?
    @State private var error: String?
    @State private var removed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if removed {
                        Text(L("公開をやめました。リンクはもう開けません。", "Unpublished. The link no longer opens."))
                    } else if let link {
                        Text(link.url).font(.footnote.monospaced()).textSelection(.enabled)
                        if let u = URL(string: link.url) {
                            ShareLink(item: u) { Label(L("リンクを送る", "Send the link"), systemImage: "square.and.arrow.up") }
                            Link(destination: u) { Label(L("ページを見る", "Open the page"), systemImage: "safari") }
                        }
                        Button(L("公開をやめる", "Unpublish"), role: .destructive) {
                            Task { await PublicLinks.remove(noteID: note.id); removed = true }
                        }
                    } else if let error {
                        Text(error).foregroundStyle(.red)
                    } else {
                        ProgressView()
                    }
                } footer: {
                    Text(L("リンクを知っている人は、アプリが無くてもブラウザでこのメモ（タイトル・本文・出典）を見られます。検索エンジンには載りません。あとで直した内容は反映されないので、作り直してください。",
                           "Anyone with the link can read this note (title, text, source) in a browser, no app needed. It isn't indexed by search engines. Later edits aren't reflected; publish again to update."))
                }
            }
            .navigationTitle(L("公開リンク", "Public link"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("完了", "Done")) { dismiss() } } }
            .task {
                guard let server = Subscription.serverURL?.absoluteString else {
                    error = ShareError.noServer.errorDescription
                    return
                }
                do { link = try await PublicLinks.create(note, server: server) }
                catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
            }
        }
        .presentationDetents([.medium])
    }
}
#endif

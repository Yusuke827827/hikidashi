// メモの編集。すべての項目を直せる。本文を大きく変えたときは「保存して AI で再整理」を使う。

#if os(iOS)
import HikidashiKit
import SwiftUI

struct NoteEditor: View {
    let note: Note
    let librarian: Librarian

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var text: String
    @State private var summary: String
    @State private var category: String
    @State private var situations: String
    @State private var tags: String
    @State private var url: String
    @State private var hasRemind: Bool
    @State private var remindDate: Date
    @State private var place: Place?
    @State private var alarmOn: Bool
    @State private var alarm: Alarm
    @State private var alarmWords: String

    init(note: Note, librarian: Librarian) {
        self.note = note
        self.librarian = librarian
        _title = State(initialValue: note.title)
        _text = State(initialValue: note.text)
        _summary = State(initialValue: note.summary)
        _category = State(initialValue: note.category)
        _situations = State(initialValue: note.situations.joined(separator: ", "))
        _tags = State(initialValue: note.tags.joined(separator: ", "))
        _url = State(initialValue: note.url ?? "")
        _hasRemind = State(initialValue: note.remindAt != nil)
        _remindDate = State(initialValue: note.remindAt.flatMap { Heuristics.dayFormatter.date(from: $0) } ?? Date())
        _place = State(initialValue: note.place)
        _alarmOn = State(initialValue: note.alarm != nil)
        let defaultDate = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date().addingTimeInterval(86400)) ?? Date()
        _alarm = State(initialValue: note.alarm ?? Alarm(kind: .once, date: defaultDate))
        _alarmWords = State(initialValue: (note.alarm?.keywords ?? []).joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("本文", "Note")) {
                    TextField(L("タイトル", "Title"), text: $title)
                    TextEditor(text: $text).frame(minHeight: 140)
                    TextField(L("要約", "Summary"), text: $summary, axis: .vertical)
                }
                Section(L("整理", "Filing")) {
                    TextField(L("フォルダ", "Folder"), text: $category)
                    if !librarian.store.folders.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(librarian.store.folders, id: \.self) { f in
                                    Button(f) { category = f }.buttonStyle(.bordered).controlSize(.small)
                                }
                            }
                        }
                    }
                    TextField(L("使う場面（カンマ区切り）", "When it helps (comma-separated)"), text: $situations, axis: .vertical)
                    TextField(L("タグ（カンマ区切り）", "Tags (comma-separated)"), text: $tags)
                    Toggle(L("リマインド", "Reminder"), isOn: $hasRemind.animation())
                    if hasRemind {
                        DatePicker(L("日付", "Date"), selection: $remindDate, displayedComponents: .date)
                    }
                }
                alarmSection
                Section {
                    if let p = place {
                        HStack {
                            Label(p.name, systemImage: "mappin.and.ellipse")
                            Spacer()
                            Button(L("外す", "Remove"), role: .destructive) { place = nil }.buttonStyle(.borderless)
                        }
                    } else {
                        NavigationLink {
                            PlaceSearchView { place = $0 }
                        } label: {
                            Label(L("場所を選ぶ", "Choose a place"), systemImage: "mappin.and.ellipse")
                        }
                    }
                } header: {
                    Text(L("着いたら知らせる", "Remind me at a place"))
                } footer: {
                    Text(L("例: スーパーに着いたら買い物のコツ、ジムに着いたらフォームの注意。", "e.g. shopping tips at the supermarket, form cues at the gym."))
                }
                Section(L("出典", "Source")) {
                    TextField("https://", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if librarian.hasAI {
                    Section {
                        Button(L("保存して AI で再整理", "Save & re-file with AI")) { commit(refile: true) }
                    } footer: {
                        Text(L("本文を大きく書き換えたときに。フォルダ・使う場面・タグを付け直します。", "Use after a big rewrite. AI redoes the folder, moments and tags."))
                    }
                }
            }
            .navigationTitle(L("編集", "Edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("キャンセル", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("保存", "Save")) { commit(refile: false) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: アラーム

    private var alarmSection: some View {
        Section {
            Toggle(L("通知する", "Notify me"), isOn: $alarmOn.animation())
            if alarmOn {
                Picker(L("いつ", "When"), selection: $alarm.kind) {
                    Text(L("1 回", "Once")).tag(Alarm.Kind.once)
                    Text(L("毎日", "Daily")).tag(Alarm.Kind.daily)
                    Text(L("何日おき", "Every N days")).tag(Alarm.Kind.interval)
                    Text(L("曜日", "Weekdays")).tag(Alarm.Kind.weekly)
                    Text(L("毎月", "Monthly")).tag(Alarm.Kind.monthly)
                    Text(L("時刻なし（言葉だけ）", "No time (words only)")).tag(Alarm.Kind.none)
                }
                switch alarm.kind {
                case .once:
                    DatePicker(L("日時", "Date & time"), selection: $alarm.date, displayedComponents: [.date, .hourAndMinute])
                case .daily:
                    DatePicker(L("時刻", "Time"), selection: $alarm.date, displayedComponents: .hourAndMinute)
                case .interval:
                    Stepper(L("\(alarm.intervalDays) 日おき", "Every \(alarm.intervalDays) days"), value: $alarm.intervalDays, in: 1...365)
                    DatePicker(L("始める日と時刻", "Starting"), selection: $alarm.date, displayedComponents: [.date, .hourAndMinute])
                case .weekly:
                    HStack(spacing: 6) {
                        ForEach(1...7, id: \.self) { w in
                            let on = alarm.weekdays.contains(w)
                            Button(Alarm.weekdayName(w)) {
                                if on { alarm.weekdays.removeAll { $0 == w } } else { alarm.weekdays.append(w) }
                            }
                            .buttonStyle(.bordered)
                            .tint(on ? Color.accentColor : Color.secondary)
                            .controlSize(.small)
                        }
                    }
                    DatePicker(L("時刻", "Time"), selection: $alarm.date, displayedComponents: .hourAndMinute)
                case .monthly:
                    DatePicker(L("日にちと時刻", "Day & time"), selection: $alarm.date, displayedComponents: [.date, .hourAndMinute])
                case .none:
                    EmptyView()
                }
                TextField(L("この言葉を入力したら知らせる（カンマ区切り・任意）", "Remind me when I type these words (comma-separated, optional)"), text: $alarmWords, axis: .vertical)
            }
        } header: {
            Text(L("通知", "Notification"))
        } footer: {
            if alarmOn {
                Text(L("その日は「今日の確認リスト」に並び、時刻になると音なしで通知に出ます。言葉を決めておくと、入力欄や「ひきだす」でその言葉を書いたときに、このメモを出します。",
                       "On those days it appears in Today's checklist, and a silent notification shows at the time. If you set words, this note pops up when you type them in the input box or Recall."))
            }
        }
    }

    private func split(_ s: String) -> [String] {
        s.components(separatedBy: CharacterSet(charactersIn: ",、，\n"))
            .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "") }
            .filter { !$0.isEmpty }
    }

    private func commit(refile: Bool) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let id = note.id
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let link = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let remind = hasRemind ? Heuristics.dayFormatter.string(from: remindDate) : nil
        librarian.store.update(id) { n in
            n.text = body
            n.title = t.isEmpty ? Heuristics.title(for: body) : t
            n.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            n.category = folder.isEmpty ? Heuristics.otherFolder : folder
            n.situations = split(situations)
            n.tags = split(tags)
            n.url = link.isEmpty ? nil : link
            n.remindAt = remind
            n.place = place
            if alarmOn {
                var a = alarm
                a.keywords = split(alarmWords)
                n.alarm = (a.kind == .none && a.keywords.isEmpty) ? nil : a
            } else {
                n.alarm = nil
            }
        }
        if refile { Task { await librarian.file(id) } }
        dismiss()
    }
}
#endif

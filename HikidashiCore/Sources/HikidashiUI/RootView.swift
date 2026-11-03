// アプリの画面。上から 入力欄 → 取り出しの答え → 今日のひとつ → リマインド → フォルダ → メモの一覧。
// アプリを開くたびに、共有シートから届いたものを取り込み、未整理のメモを AI で整理する。

#if os(iOS)
import HikidashiKit
import SwiftUI
import CoreSpotlight
import UserNotifications

public struct HikidashiRootView: View {
    enum FolderMode: Hashable { case topic, date }
    static let allKey = "__all"
    static let pinKey = "__pin"

    @State private var librarian: Librarian
    @AppStorage("wallpaper") private var wallpaperRaw = Wallpaper.plain.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var systemScheme

    @State private var folderMode: FolderMode = .topic
    @State private var folder = HikidashiRootView.allKey
    @State private var filter = ""
    @State private var recall: RecallOutcome?
    @State private var editing: Note?
    @State private var showSettings = false
    @State private var pickSkip = 0
    @State private var toast: String?
    @State private var jumpTarget: String?
    @State private var managingFolders = false
    @AppStorage("onboarded") private var onboarded = false
    @AppStorage("reviewDismissedWeek") private var reviewDismissedWeek = ""
    @State private var composing: RecallOutcome?
    @State private var noteFilter = NoteFilter()
    @State private var smartFolders = SmartFolders.load()
    @State private var upkeepRefresh = 0
    @State private var joinCode: String?
    @State private var showFilter = false
    @State private var focusSave = 0
    @State private var chatting = false
    @AppStorage("autoBackup") private var autoBackup = true
    @State private var mergeRefresh = 0
    /// スマホの幅での画面（今日・メモ）
    enum Tab: Hashable { case today, notes, calendar }
    @State private var tab: Tab = .today
    @State private var calMonth = Date()
    @State private var calDay = Heuristics.dayFormatter.string(from: Date())
    @State private var calText = ""
    @State private var showGraph = false
    @State private var usageTick = 0
    @AppStorage("noteSort") private var sortRaw = NoteSort.new.rawValue
    private var sort: NoteSort { NoteSort(rawValue: sortRaw) ?? .new }

    @MainActor
    public init() {
        _librarian = State(initialValue: DemoMode.isOn ? DemoMode.makeLibrarian() : Librarian(store: NoteStore(), credentialProvider: Subscription.credential))
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
    }

    private var store: NoteStore { librarian.store }
    private var wallpaper: Wallpaper { Wallpaper(rawValue: wallpaperRaw) ?? .plain }
    private var palette: Palette { Palette.make(wallpaper, scheme: wallpaper.scheme ?? systemScheme) }

    public var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Group {
                    if wide {
                        // iPad・Mac: 左に入力欄やカード、右にフォルダとメモの一覧
                        HStack(alignment: .top, spacing: 0) {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 18) { mainColumn }
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 48)
                            }
                            .frame(width: 400)
                            .scrollDismissesKeyboard(.interactively)
                            Divider().opacity(0.4)
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 18) { listColumn }
                                    .padding(.horizontal, 20)
                                    .padding(.top, 16)
                                    .padding(.bottom, 48)
                                    .frame(maxWidth: 820)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 18) {
                                switch tab {
                                case .today: mainColumn
                                case .notes: header; listColumn
                                case .calendar: header; calendarPanel
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .safeAreaInset(edge: .bottom) { tabBar }
                    }
                }
                .onChange(of: jumpTarget) { _, id in
                    guard let id else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
            }
            .background { WallpaperBackground(wallpaper: wallpaper, palette: palette) }
            .toolbar(.hidden, for: .navigationBar)
        }
        .environment(\.palette, palette)
        .tint(palette.accent)
        .preferredColorScheme(wallpaper.scheme)
        .sheet(item: $editing) { n in
            NoteEditor(note: n, librarian: librarian).environment(\.palette, palette).tint(palette.accent)
        }
        .sheet(isPresented: $showFilter) {
            FilterSheet(filter: $noteFilter, notes: store.notes, onSave: saveSmartFolder).tint(palette.accent)
        }
        .sheet(item: $composing) { r in
            ComposeSheet(librarian: librarian, topic: r.query, noteIDs: r.noteIDs) { n in
                show(L("「\(n.title)」をしまいました。", "Saved “\(n.title)”."))
            }
            .tint(palette.accent)
        }
        .sheet(isPresented: $chatting) {
            ChatView(librarian: librarian) { n in jump(n) }
                .environment(\.palette, palette)
                .tint(palette.accent)
        }
        .sheet(isPresented: $managingFolders, onDismiss: { mergeRefresh += 1 }) {
            FolderManagerView(store: store, librarian: librarian).environment(\.palette, palette).tint(palette.accent)
        }
        .sheet(isPresented: $showGraph) {
            GraphSheet(store: store, onOpen: jump).environment(\.palette, palette).tint(palette.accent)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(librarian: librarian, wallpaperRaw: $wallpaperRaw).environment(\.palette, palette).tint(palette.accent)
        }
        .task { await refresh() }
        .task { if !DemoMode.isOn { await librarian.checkLinksIfNeeded() } }
        .task { if !DemoMode.isOn { await Subscription.shared.start() } }
        .task { if !DemoMode.isOn, CloudSync.isOn { CloudSync.shared.start(store: store) } }
        // 購読が始まったら、たまっている未整理のメモを整理する
        .onChange(of: Subscription.shared.isActive) { _, active in
            if active { Task { await librarian.fileAll() } }
        }
        // 「その他」を振り分けた・似たフォルダをまとめた、などを知らせる
        .onChange(of: librarian.tidyMessage) { _, m in
            if let m { show(m); librarian.tidyMessage = nil; mergeRefresh += 1 }
        }
        // リマインド日・タイトルが変わったときだけ、通知を予約し直す
        .task(id: Reminders.signature(store.notes)) {
            if !DemoMode.isOn { await Reminders.sync(store.notes) }
        }
        // アプリのアイコンに、今日まだ確認していない数を出す
        .task(id: todayItems.filter { !store.isChecked($0.note.id, day: todayKey) }.count) {
            guard !DemoMode.isOn else { return }
            let left = todayItems.filter { !store.isChecked($0.note.id, day: todayKey) }.count
            try? await UNUserNotificationCenter.current().setBadgeCount(left)
        }
        // Apple Watch と、今日の確認リストのウィジェットに、今の内容を送る
        .task(id: todayItems.map { $0.note.id + (store.isChecked($0.note.id, day: todayKey) ? "1" : "0") + $0.note.title }.joined(separator: "|") + todayKey) {
            guard !DemoMode.isOn else { return }
            #if canImport(WatchConnectivity)
            WatchBridge.shared.start(store: store)
            #endif
            AppRouter.reloadWidgets()
        }
        .task(id: Alarms.signature(store.notes)) {
            if !DemoMode.isOn { await Alarms.sync(store.notes) }
        }
        .task(id: PlaceReminders.signature(store.notes)) {
            if !DemoMode.isOn { await PlaceReminders.sync(store.notes) }
        }
        .onChange(of: NotificationRouter.shared.openNoteID) { _, id in
            guard let id, let note = store.note(id) else { return }
            NotificationRouter.shared.openNoteID = nil
            jump(note)
        }
        // 共有フォルダのリンクから開いたら参加の画面を出す
        .onChange(of: NotificationRouter.shared.joinCode) { _, c in
            guard let c else { return }
            NotificationRouter.shared.joinCode = nil
            joinCode = c
        }
        .sheet(item: Binding(get: { joinCode.map(JoinRequest.init) }, set: { joinCode = $0?.code })) { r in
            JoinShareSheet(librarian: librarian, initial: r.code) { name in show(L("共有フォルダ「\(name)」に参加しました", "Joined the shared folder \(name)")) }
                .tint(palette.accent)
        }
        // 共有フォルダは、開いたときと、その中のメモが変わったとき（少し待ってから）に同期する
        .task(id: shareSignature) {
            guard !DemoMode.isOn, !librarian.sharedFolders.isEmpty else { return }
            try? await Task.sleep(for: .seconds(2))
            await librarian.syncShares()
        }
        .onChange(of: NotificationRouter.shared.focusSave) { _, on in
            guard on else { return }
            NotificationRouter.shared.focusSave = false
            focusSave += 1
        }
        .onChange(of: NotificationRouter.shared.recallQuery) { _, q in
            guard let q else { return }
            NotificationRouter.shared.recallQuery = nil
            Task { recall = await librarian.recall(q) }
        }
        .onOpenURL { AppRouter.handle($0) }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            if let id = Spotlight.noteID(from: activity) { AppRouter.open(noteID: id) }
        }
        // メモが変わったら、ウィジェットと iPhone の検索を新しくする
        .onChange(of: store.notes) { _, notes in
            guard !DemoMode.isOn else { return }
            AppRouter.reloadWidgets()
            Spotlight.index(notes)
        }
        // 初めて開いたときの案内（見本モードでは出さない）
        .fullScreenCover(isPresented: Binding(get: { !onboarded && !DemoMode.isOn }, set: { _ in })) {
            OnboardingView { addExamples in
                if addExamples { librarian.addExamples() }
                onboarded = true
            }
            .environment(\.palette, palette)
        }
        // ロック中は中身を隠す
        .overlay {
            if AppLock.shared.locked, !DemoMode.isOn {
                LockScreen().environment(\.palette, palette)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { AppLock.shared.lockIfNeeded(); SecretNotes.shared.closeAll(); usageTick += 1 }
            if phase == .active { Task { await refresh() } }
        }
    }

    private func refresh() async {
        if DemoMode.isOn {
            if let q = DemoMode.recallQuery, recall == nil {
                var r = await librarian.recall(q)
                r.answer = DemoMode.recallAnswer
                recall = r
            }
            if DemoMode.opensSettings { showSettings = true }
            return
        }
        // アプリが閉じた状態から通知を押して起動したとき
        if let id = NotificationRouter.shared.openNoteID, let note = store.note(id) {
            NotificationRouter.shared.openNoteID = nil
            jump(note)
        }
        if let q = NotificationRouter.shared.recallQuery {
            NotificationRouter.shared.recallQuery = nil
            recall = await librarian.recall(q)
        }
        let n = librarian.ingestInbox()
        if n > 0 { show(L("共有シートから \(n) 件届きました。", "\(n) items arrived from the share sheet.")) }
        if CloudSync.isOn { await CloudSync.shared.fetch() }
        await librarian.syncShares()
        store.reloadChecks()
        let mailed = await librarian.pullInbox()
        if mailed > 0 {
            show(L("メール・LINE から \(mailed) 件届きました。", "\(mailed) notes arrived by email or LINE."))
            await librarian.fileAll()
        }
        if let c = NotificationRouter.shared.joinCode { NotificationRouter.shared.joinCode = nil; joinCode = c }
        store.purgeTrash()
        let expired = store.purgeExpired()
        if expired > 0 { show(L("期限が過ぎたメモ \(expired) 件をゴミ箱へ移しました。", "Moved \(expired) expired notes to the trash.")) }
        await PlaceKindAlerts.sync(store.notes)
        if autoBackup {
            let last = UserDefaults.standard.object(forKey: "lastBackup") as? Date
            if Backup.runIfDue(store, last: last) != nil { UserDefaults.standard.set(Date(), forKey: "lastBackup") }
        }
        await librarian.fileAll()
        await EventReminders.sync(store.notes)
    }

    private func show(_ message: String) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(5))
            if toast == message { withAnimation { toast = nil } }
        }
    }

    // MARK: 見出し

    private var aiLabel: String {
        switch librarian.aiKind {
        case .claude: return "Claude"
        case .onDevice: return L("iPhone の AI", "On-device AI")
        case .none: return L("簡易整理", "Basic")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(!wide && tab == .notes ? L("メモ", "Notes") : (!wide && tab == .calendar ? L("カレンダー", "Calendar") : "Mindrawer"))
                .font(!wide && tab != .today ? .largeTitle.weight(.bold) : Fonts.mincho(26))
                .foregroundStyle(palette.text)
            Spacer()
            Text(aiLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(palette.muted)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(palette.surface2))
            if wide {
                Button { chatting = true } label: {
                    Image(systemName: "bubble.left.and.text.bubble.right").font(.title3).frame(width: 40, height: 44)
                }
                .foregroundStyle(palette.text)
                .accessibilityLabel(L("メモに聞く", "Ask your notes"))
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape").font(.title3).frame(width: 44, height: 44)
                }
                .foregroundStyle(palette.text)
                .accessibilityLabel(L("設定", "Settings"))
            }
        }
        .padding(.top, 4)
    }

    // MARK: カレンダー

    private var calendarPanel: some View {
        let cal = Calendar.current
        let days = Heuristics.calendarDays(store.notes, month: calMonth)
        let first = cal.date(from: cal.dateComponents([.year, .month], from: calMonth)) ?? calMonth
        let lead = cal.component(.weekday, from: first) - 1
        let count = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let todayKey = Heuristics.dayFormatter.string(from: Date())
        let entries = days[calDay] ?? []
        let planned = entries.filter { $0.kind == .planned }.map(\.note)
        let saved = entries.filter { $0.kind == .saved }.map(\.note)
        let weekdays = cal.shortWeekdaySymbols
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(first.formatted(.dateTime.year().month(.wide).locale(AppLanguage.current.locale))).font(.title3.bold())
                Spacer()
                Button { calMonth = cal.date(byAdding: .month, value: -1, to: first) ?? first } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36) }
                    .accessibilityLabel(L("前の月", "Previous month"))
                Button(L("今日", "Today")) { calMonth = Date(); calDay = todayKey }.font(.subheadline)
                Button { calMonth = cal.date(byAdding: .month, value: 1, to: first) ?? first } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36) }
                    .accessibilityLabel(L("次の月", "Next month"))
            }
            .foregroundStyle(palette.text)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(weekdays, id: \.self) { Text($0).font(.caption2).foregroundStyle(palette.muted) }
                ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 50) }
                ForEach(1...count, id: \.self) { d in
                    let date = cal.date(byAdding: .day, value: d - 1, to: first) ?? first
                    let key = Heuristics.dayFormatter.string(from: date)
                    let list = days[key] ?? []
                    Button { calDay = key } label: {
                        VStack(spacing: 4) {
                            Text("\(d)").font(.subheadline.monospacedDigit().weight(key == todayKey ? .bold : .regular))
                                .foregroundStyle(key == todayKey ? palette.accentText : palette.text)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(key == todayKey ? palette.accent : Color.clear))
                            HStack(spacing: 3) {
                                ForEach(Array(list.filter { $0.kind == .saved }.prefix(3).enumerated()), id: \.offset) { _, e in
                                    Circle().fill(Looks.color(store.folderLook(e.note.category).color)).frame(width: 5, height: 5)
                                }
                                if list.contains(where: { $0.kind == .planned }) {
                                    Circle().stroke(palette.accent, lineWidth: 1.5).frame(width: 6, height: 6)
                                }
                            }
                            .frame(height: 6)
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(RoundedRectangle(cornerRadius: 10).fill(palette.surface))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(key == calDay ? palette.text : Color.clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(d)  \(list.count)")
                }
            }
            Text((Heuristics.dayFormatter.date(from: calDay) ?? Date()).formatted(.dateTime.month().day().weekday(.abbreviated).locale(AppLanguage.current.locale)))
                .font(.headline).foregroundStyle(palette.text).padding(.top, 4)
            HStack {
                TextField(L("この日のメモを書く", "Add a note for this day"), text: $calText)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit(addCalendarNote)
                Button(L("追加", "Add"), action: addCalendarNote)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(calText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !planned.isEmpty {
                sectionTitle(L("予定", "Planned"))
                ForEach(planned) { card($0) }
            }
            if !saved.isEmpty {
                sectionTitle(L("しまったメモ", "Saved"))
                ForEach(saved) { card($0) }
            }
            if entries.isEmpty {
                Text(L("この日のメモはありません。", "Nothing on this day.")).font(.subheadline).foregroundStyle(palette.muted)
            }
        }
    }

    private func addCalendarNote() {
        let t = calText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        calText = ""
        let note = librarian.save(text: t, url: nil, image: nil)
        let day = calDay
        store.update(note.id) { $0.remindAt = day }
        show(L("この日に追加しました。", "Added to this day."))
        Task { await librarian.file(note.id) }
    }

    /// 下のタブ（スマホの幅）。今日・メモは画面を切り替え、聞く・設定は開く
    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(L("今日", "Today"), "house", on: tab == .today) { withAnimation(.easeOut(duration: 0.15)) { tab = .today } }
            tabButton(L("メモ", "Notes"), "note.text", on: tab == .notes) { withAnimation(.easeOut(duration: 0.15)) { tab = .notes } }
            tabButton(L("カレンダー", "Calendar"), "calendar", on: tab == .calendar) { withAnimation(.easeOut(duration: 0.15)) { tab = .calendar } }
            tabButton(L("聞く", "Ask"), "bubble.left.and.text.bubble.right", on: false) { chatting = true }
            tabButton(L("設定", "Settings"), "gearshape", on: false) { showSettings = true }
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func tabButton(_ title: String, _ symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: on ? symbol + ".fill" : symbol).font(.system(size: 19)).frame(height: 22)
                Text(title).font(.caption2.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .foregroundStyle(on ? palette.accent : palette.muted)
        }
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func errorBanner(_ e: String) -> some View {
        HStack(alignment: .top) {
            Text(e).font(.footnote).foregroundStyle(palette.text)
            Spacer()
            Button(L("閉じる", "Close")) { librarian.clearError() }.font(.footnote)
        }
        .card(padding: 12)
    }

    // MARK: 取り出しの答え

    private func recallCard(_ r: RecallOutcome) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("ひきだし ・ 「\(r.query)」 ・ \(r.noteIDs.count) 件", "Recall · “\(r.query)” · \(r.noteIDs.count)"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.accent)
                Spacer()
                Button(L("閉じる", "Close")) { withAnimation { recall = nil } }.font(.footnote)
            }
            Text(r.answer).font(.body).foregroundStyle(palette.text).fixedSize(horizontal: false, vertical: true)
            if r.noteIDs.count >= 2 {
                Button { composing = r } label: {
                    Label(L("このメモからまとめノートを作る", "Combine these into one note"), systemImage: "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(palette.accent)
            }
            ForEach(r.noteIDs.compactMap { store.note($0) }) { n in
                NoteCard(note: n, librarian: librarian, highlighted: true, onEdit: { editing = $0 }, onJump: jump)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.accentSoft))
        .background { if palette.translucent { RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial) } }
    }

    // MARK: 週の振り返り（日曜と月曜）

    private var weekKey: String {
        let c = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return "\(c.yearForWeekOfYear ?? 0)-\(c.weekOfYear ?? 0)"
    }

    @ViewBuilder private var weeklyReviewCard: some View {
        if Heuristics.isReviewDay(), reviewDismissedWeek != weekKey {
            let review = Heuristics.weeklyReview(store.notes)
            if !review.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(L("今週のふりかえり", "This week").uppercased())
                            .font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(palette.muted)
                        Spacer()
                        Button(L("閉じる", "Close")) { withAnimation { reviewDismissedWeek = weekKey } }.font(.footnote)
                    }
                    Text(L("この 1 週間で \(review.added.count) 件しまいました。", "You saved \(review.added.count) notes this week."))
                        .font(.subheadline).foregroundStyle(palette.text)
                    if !review.forgotten.isEmpty {
                        Text(L("しまったままのメモ", "Notes you haven't looked at")).font(.caption.weight(.bold)).foregroundStyle(palette.accent)
                        ForEach(review.forgotten) { n in
                            Button { jump(n) } label: {
                                Text("→ " + n.title).font(.subheadline).foregroundStyle(palette.text).lineLimit(1)
                            }
                        }
                    }
                }
                .card()
            }
        }
    }

    // MARK: 今日の確認リスト

    private var todayItems: [TodayItem] { Heuristics.todayList(store.notes) }
    private var todayKey: String { Heuristics.dayFormatter.string(from: Date()) }

    @ViewBuilder private var todayListCard: some View {
        let items = todayItems
        if !items.isEmpty {
            let done = items.filter { store.isChecked($0.note.id, day: todayKey) }.count
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L("今日の確認リスト", "Today's checklist").uppercased())
                        .font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(palette.muted)
                    Spacer()
                    Text("\(done)/\(items.count)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(done == items.count ? palette.accent : palette.muted)
                }
                ForEach(items, id: \.note.id) { item in todayRow(item) }
                if done == items.count {
                    Text(L("今日の分は全部確認しました ✓", "All checked for today ✓"))
                        .font(.footnote).foregroundStyle(palette.accent)
                }
            }
            .card()
        }
    }

    private func todayRow(_ item: TodayItem) -> some View {
        let checked = store.isChecked(item.note.id, day: todayKey)
        return HStack(spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { store.toggleCheck(item.note.id, day: todayKey) }
            } label: {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(checked ? palette.accent : palette.muted)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel(checked ? L("確認済み", "Checked") : L("確認する", "Check"))
            Button { jump(item.note) } label: {
                HStack {
                    Text(item.note.title)
                        .font(.subheadline)
                        .strikethrough(checked, color: palette.muted)
                        .foregroundStyle(checked ? palette.muted : palette.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    if let t = item.time {
                        Text(t, format: .dateTime.hour().minute()).font(.caption.monospacedDigit()).foregroundStyle(palette.muted)
                    } else if item.reason == .remind {
                        Image(systemName: "alarm").font(.caption).foregroundStyle(palette.accent)
                    }
                }
            }
        }
    }

    // MARK: 今日のひとつ・リマインド

    private func pickCard(_ n: Note) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("今日のひとつ", "Today's pick").uppercased()).font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(palette.muted)
            Text(n.category).font(.caption.weight(.bold)).foregroundStyle(palette.accent)
            Text(n.title).font(.headline).foregroundStyle(palette.text)
            if !n.summary.isEmpty { Text(n.summary).font(.subheadline).foregroundStyle(palette.muted) }
            HStack {
                Button(L("読んだ", "Got it")) { store.update(n.id) { $0.lastSeen = Date() } }
                Button(L("別のを見る", "Another")) { pickSkip += 1 }
                Spacer()
                Button(L("開く", "Open")) { jump(n) }
            }
            .font(.footnote.weight(.semibold))
            .padding(.top, 4)
        }
        .card()
    }

    @ViewBuilder private var upcoming: some View {
        let soon = Heuristics.upcoming(store.notes)
        if !soon.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle(L("近日のリマインド", "Coming up"))
                ForEach(soon) { n in
                    Button { jump(n) } label: {
                        HStack {
                            Text(String((n.remindAt ?? "").dropFirst(5)).replacingOccurrences(of: "-", with: "/"))
                                .font(.caption.monospacedDigit()).foregroundStyle(palette.accent)
                            Text(n.title).font(.subheadline).foregroundStyle(palette.text).lineLimit(1)
                            Spacer()
                        }
                    }
                }
            }
            .card(padding: 14)
        }
    }

    // MARK: フォルダと一覧

    private func folderKey(_ n: Note) -> String {
        switch folderMode {
        case .topic: return n.category.isEmpty ? Heuristics.otherFolder : n.category
        case .date:
            let c = Calendar.current.dateComponents([.year, .month], from: n.createdAt)
            return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
        }
    }

    private func folderLabel(_ key: String) -> String {
        guard folderMode == .date, let d = Heuristics.dayFormatter.date(from: key + "-01") else { return key }
        return d.formatted(.dateTime.year().month(.wide).locale(AppLanguage.current.locale))
    }

    /// 似ているフォルダをまとめる提案（1 件だけ）
    private var mergeSuggestion: FolderMergeSuggestion? {
        _ = mergeRefresh
        guard !DemoMode.isOn, librarian.mergeMode == .suggest else { return nil }
        return Heuristics.folderMergeSuggestions(store.notes, folders: store.folders, dismissed: MergeDismissals.all, limit: 1).first
    }

    /// 「その他」から振り分けられるメモ（自動で振り分けないとき）
    private var resortMoves: [(id: String, folder: String)]? {
        _ = mergeRefresh
        guard !DemoMode.isOn, !librarian.autoResort, librarian.folderMode == .ask else { return nil }
        let moves = Heuristics.resortSuggestions(store.notes, folders: store.folders)
        return moves.isEmpty || ResortCard.isDismissed(moves) ? nil : moves
    }

    /// 共有フォルダのメモの変わり目（同期のきっかけ）
    private var shareSignature: String {
        let shared = Set(librarian.sharedFolders.map(\.folder))
        guard !shared.isEmpty else { return "" }
        let ns = store.notes.filter { shared.contains($0.category) }
        return "\(shared.count)|\(ns.count)|\(ns.map(\.modifiedAt).max()?.timeIntervalSince1970 ?? 0)"
    }

    // MARK: 画面の組み立て

    @Environment(\.horizontalSizeClass) private var sizeClass
    /// iPad・Mac の広い画面
    private var wide: Bool { sizeClass == .regular }

    @ViewBuilder private var mainColumn: some View {
        header
        CaptureCard(librarian: librarian, onRecall: { recall = $0 }, onToast: show, onOpen: jump, focusTrigger: focusSave)
        if let req = librarian.folderChoice {
            FolderChoiceCard(request: req, librarian: librarian).id(req.noteID)
        }
        if let toast {
            Text(toast).font(.footnote).foregroundStyle(palette.accent).transition(.opacity)
        }
        if let e = librarian.lastError { errorBanner(e) }
        if let recall { recallCard(recall) }
        todayListCard
        let now = usageTick >= 0 ? Heuristics.forNow(store.notes, log: UsageLog.load()) : []
        if !now.isEmpty { NowCard(notes: now, onOpen: jump) }
        let due = Heuristics.dueReviews(store.notes)
        if !due.isEmpty { ReviewCard(notes: due, store: store) }
        weeklyReviewCard
        upkeepCards
        if let pick = Heuristics.todaysPick(store.notes, skip: pickSkip) { pickCard(pick) }
        upcoming
        if let s = mergeSuggestion {
            MergeSuggestionCard(suggestion: s, store: store) { withAnimation { mergeRefresh += 1 } }
        }
        if let moves = resortMoves {
            ResortCard(moves: moves, store: store) { withAnimation { mergeRefresh += 1 } }
        }
    }

    @ViewBuilder private var listColumn: some View {
        if store.notes.isEmpty { emptyState } else { folderBar; listHeader; notesList }
    }

    // MARK: 手入れ（ダブり・見直し）

    @ViewBuilder private var upkeepCards: some View {
        let _ = upkeepRefresh
        if !DemoMode.isOn {
            let stale = Heuristics.staleNotes(store.notes)
            if !stale.isEmpty { StaleCard(items: stale, librarian: librarian) { editing = $0 } }
            if let pair = Heuristics.duplicates(store.notes, dismissed: DuplicateDismissals.all).first {
                DuplicateCard(pair: pair, librarian: librarian) { withAnimation { upkeepRefresh += 1 } }
            }
        }
    }

    // MARK: スマートフォルダ

    static let smartPrefix = "smart:"

    private func saveSmartFolder(_ name: String) {
        let realFolder = folderMode == .topic && folder != Self.allKey && folder != Self.pinKey && !folder.hasPrefix(Self.smartPrefix) ? folder : nil
        let sf = SmartFolder(name: name, query: filter, folder: realFolder, filter: noteFilter)
        smartFolders.append(sf)
        SmartFolders.save(smartFolders)
        filter = ""
        noteFilter = NoteFilter()
        folder = Self.smartPrefix + sf.id
    }

    private func deleteSmartFolder(_ id: String) {
        smartFolders.removeAll { $0.id == id }
        SmartFolders.save(smartFolders)
        if folder == Self.smartPrefix + id { folder = Self.allKey }
    }

    private var folderBar: some View {
        let counts = folderMode == .topic ? store.folderCounts : Dictionary(grouping: store.notes, by: folderKey).mapValues(\.count)
        let keys = folderMode == .topic ? store.folders : counts.keys.sorted(by: >)
        let pinned = store.notes.filter(\.pinned).count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle(L("フォルダ", "Folders"))
                Spacer()
                Picker("", selection: $folderMode) {
                    Text(L("分類", "Topic")).tag(FolderMode.topic)
                    Text(L("日付", "Date")).tag(FolderMode.date)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                .onChange(of: folderMode) { _, _ in folder = Self.allKey }
                Button { managingFolders = true } label: {
                    Image(systemName: "folder.badge.gearshape").frame(width: 36, height: 34)
                }
                .foregroundStyle(palette.muted)
                .accessibilityLabel(L("フォルダの管理", "Manage folders"))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    folderTab(Self.allKey, L("すべて", "All"), store.notes.count)
                    if pinned > 0 { folderTab(Self.pinKey, L("お気に入り", "Favorites"), pinned, favorite: true) }
                    ForEach(smartFolders) { sf in
                        folderTab(Self.smartPrefix + sf.id, sf.name, store.notes.filter { sf.matches($0) }.count)
                            .contextMenu {
                                Button(role: .destructive) { deleteSmartFolder(sf.id) } label: { Label(L("このスマートフォルダを消す", "Delete smart folder"), systemImage: "trash") }
                            }
                    }
                    ForEach(keys, id: \.self) { k in
                        folderTab(k, folderLabel(k), counts[k] ?? 0, badge: folderMode == .topic, favorite: folderMode == .topic && store.isFavoriteFolder(k))
                    }
                }
            }
        }
    }

    private func folderTab(_ key: String, _ label: String, _ count: Int, badge: Bool = false, favorite: Bool = false) -> some View {
        let on = folder == key
        return Button { folder = key } label: {
            HStack(spacing: 6) {
                if badge { FolderBadge(name: key, store: store, size: 20) }
                if favorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(on ? palette.bg : palette.accent) }
                Text(label).font(.subheadline.weight(on ? .semibold : .regular))
                Text("\(count)").font(.caption2.monospacedDigit()).opacity(0.6)
            }
            .padding(.leading, badge ? 6 : 12)
            .padding(.trailing, 12)
            .frame(minHeight: 36)
            .foregroundStyle(on ? palette.bg : palette.text)
            .background(Capsule().fill(on ? palette.text : palette.surface))
            .overlay(Capsule().stroke(palette.line, lineWidth: on ? 0 : 1))
        }
    }

    private var shownNotes: [Note] {
        let f = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let smart = folder.hasPrefix(Self.smartPrefix) ? smartFolders.first { Self.smartPrefix + $0.id == folder } : nil
        return sort.sorted(store.notes.filter { n in
            if let smart, !smart.matches(n) { return false }
            let inFolder = smart != nil || folder == Self.allKey || (folder == Self.pinKey ? n.pinned : folderKey(n) == folder)
            return inFolder && (f.isEmpty || n.haystack.contains(f)) && noteFilter.matches(n)
        })
    }

    private var listHeader: some View {
        HStack(spacing: 10) {
            sectionTitle(L("\(shownNotes.count) 件", "\(shownNotes.count) notes"))
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(palette.muted)
                TextField(L("絞り込み", "Filter"), text: $filter).textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 36)
            .background(RoundedRectangle(cornerRadius: 10).fill(palette.surface2))
            Button { showFilter = true } label: {
                Image(systemName: noteFilter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.title3)
                    .frame(width: 36, height: 36)
                    .overlay(alignment: .topTrailing) {
                        if noteFilter.count > 0 {
                            Text("\(noteFilter.count)").font(.caption2.bold()).foregroundStyle(palette.accentText)
                                .padding(3).background(Circle().fill(palette.accent)).offset(x: 4, y: -2)
                        }
                    }
            }
            .foregroundStyle(noteFilter.isActive ? palette.accent : palette.muted)
            .accessibilityLabel(L("詳しく絞り込む", "More filters"))
            Menu {
                Picker(L("並べ方", "Sort"), selection: $sortRaw) {
                    ForEach(NoteSort.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down.circle")
                    .font(.title3)
                    .frame(width: 36, height: 36)
            }
            .foregroundStyle(sort == .new ? palette.muted : palette.accent)
            .accessibilityLabel(L("並べ方: ", "Sort: ") + sort.label)
            Button { showGraph = true } label: {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.title3)
                    .frame(width: 36, height: 36)
            }
            .foregroundStyle(palette.muted)
            .accessibilityLabel(L("つながりの図", "Connections"))
        }
    }

    private var notesList: some View {
        let notes = shownNotes
        return Group {
            if notes.isEmpty {
                Text(L("該当するメモはありません。", "No notes match.")).font(.subheadline).foregroundStyle(palette.muted)
            }
            if sort == .folder {
                ForEach(Dictionary(grouping: notes, by: { $0.category.isEmpty ? Heuristics.otherFolder : $0.category }).sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }, id: \.key) { group in
                    HStack(spacing: 8) {
                        FolderBadge(name: group.key, store: store)
                        Text(group.key).font(.subheadline.weight(.semibold)).foregroundStyle(palette.text)
                        Text("\(group.value.count)").font(.caption).foregroundStyle(palette.muted)
                    }
                    .padding(.top, 8)
                    ForEach(group.value) { card($0) }
                }
            } else {
                ForEach(notes) { card($0) }
            }
        }
    }

    private func card(_ n: Note) -> some View {
        NoteCard(note: n, librarian: librarian, highlighted: jumpTarget == n.id, onEdit: { editing = $0 }, onJump: jump, onTag: { t in
            noteFilter.tags = [t]
            folder = Self.allKey
            tab = .notes
            show(L("#\(t) のメモだけを出しています。絞り込みで解除できます。", "Showing #\(t). Clear it in Filters."))
        })
        .id(n.id)
    }

    private func jump(_ n: Note) {
        UsageLog.record(n.id)
        tab = .notes
        folderMode = .topic
        folder = Self.allKey
        filter = ""
        jumpTarget = nil
        DispatchQueue.main.async { jumpTarget = n.id }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("ひきだしはまだ空です", "Your drawer is empty")).font(.headline).foregroundStyle(palette.text)
            Text(L("上の欄に Tips を貼って「しまう」を押すか、X や Safari の共有ボタンから「Mindrawer」を選んでください。AI がフォルダ分けし、「ひきだす」で必要なときに取り出せます。",
                   "Paste a tip above and tap Save, or pick Mindrawer from the share sheet in X or Safari. Claude files it, and Recall hands it back when you need it."))
                .font(.subheadline).foregroundStyle(palette.muted)
            Button(L("見本の 3 件を入れて試す", "Add 3 examples to try it")) { librarian.addExamples() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 4)
        }
        .card()
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s.uppercased()).font(.caption.weight(.semibold)).tracking(1).foregroundStyle(palette.muted)
    }
}
#endif

#if os(iOS)
private struct JoinRequest: Identifiable {
    let code: String
    var id: String { code }
}
#endif

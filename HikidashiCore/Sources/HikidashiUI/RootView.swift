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
    @State private var chatting = false
    @AppStorage("autoBackup") private var autoBackup = true
    @State private var mergeRefresh = 0

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
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        header
                        CaptureCard(librarian: librarian, onRecall: { recall = $0 }, onToast: show, onOpen: jump)
                        if let toast {
                            Text(toast).font(.footnote).foregroundStyle(palette.accent).transition(.opacity)
                        }
                        if let e = librarian.lastError { errorBanner(e) }
                        if let recall { recallCard(recall) }
                        todayListCard
                        weeklyReviewCard
                        if let pick = Heuristics.todaysPick(store.notes, skip: pickSkip) { pickCard(pick) }
                        upcoming
                        if let s = mergeSuggestion {
                            MergeSuggestionCard(suggestion: s, store: store) { withAnimation { mergeRefresh += 1 } }
                        }
                        if store.notes.isEmpty { emptyState } else { folderBar; listHeader; notesList }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 48)
                }
                .scrollDismissesKeyboard(.interactively)
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
            FolderManagerView(store: store).environment(\.palette, palette).tint(palette.accent)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(librarian: librarian, wallpaperRaw: $wallpaperRaw).environment(\.palette, palette).tint(palette.accent)
        }
        .task { await refresh() }
        .task { if !DemoMode.isOn { await Subscription.shared.start() } }
        .task { if !DemoMode.isOn, CloudSync.isOn { CloudSync.shared.start(store: store) } }
        // 購読が始まったら、たまっている未整理のメモを整理する
        .onChange(of: Subscription.shared.isActive) { _, active in
            if active { Task { await librarian.fileAll() } }
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
            if phase == .background { AppLock.shared.lockIfNeeded() }
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
        store.purgeTrash()
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
            Text("Mindrawer").font(Fonts.mincho(26)).foregroundStyle(palette.text)
            Text("引出").font(.caption.weight(.bold)).tracking(3).foregroundStyle(palette.accent)
            Spacer()
            Button { chatting = true } label: {
                Image(systemName: "bubble.left.and.text.bubble.right").font(.title3).frame(width: 40, height: 44)
            }
            .foregroundStyle(palette.text)
            .accessibilityLabel(L("メモに聞く", "Ask your notes"))
            Text(aiLabel)
                .font(.caption.monospaced())
                .foregroundStyle(palette.muted)
            Button { showSettings = true } label: {
                Image(systemName: "gearshape").font(.title3).frame(width: 44, height: 44)
            }
            .foregroundStyle(palette.text)
            .accessibilityLabel(L("設定", "Settings"))
        }
        .padding(.top, 4)
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
                        Text("⏰").font(.caption)
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
        guard !DemoMode.isOn else { return nil }
        return Heuristics.folderMergeSuggestions(store.notes, folders: store.folders, dismissed: MergeDismissals.all, limit: 1).first
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
                    if pinned > 0 { folderTab(Self.pinKey, "★ " + L("お気に入り", "Favorites"), pinned) }
                    ForEach(keys, id: \.self) { k in
                        folderTab(k, (folderMode == .topic && store.isFavoriteFolder(k) ? "★ " : "") + folderLabel(k), counts[k] ?? 0)
                    }
                }
            }
        }
    }

    private func folderTab(_ key: String, _ label: String, _ count: Int) -> some View {
        let on = folder == key
        return Button { folder = key } label: {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(label).font(.subheadline.weight(on ? .bold : .regular))
                Text("\(count)").font(.caption2.monospacedDigit()).opacity(0.7)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .foregroundStyle(on ? palette.accentText : palette.text)
            .background(RoundedRectangle(cornerRadius: 10).fill(on ? palette.accent : palette.surface2))
        }
    }

    private var shownNotes: [Note] {
        let f = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return store.notes.filter { n in
            let inFolder = folder == Self.allKey || (folder == Self.pinKey ? n.pinned : folderKey(n) == folder)
            return inFolder && (f.isEmpty || n.haystack.contains(f))
        }
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
        }
    }

    private var notesList: some View {
        let notes = shownNotes
        return Group {
            if notes.isEmpty {
                Text(L("該当するメモはありません。", "No notes match.")).font(.subheadline).foregroundStyle(palette.muted)
            }
            ForEach(notes) { n in
                NoteCard(note: n, librarian: librarian, highlighted: jumpTarget == n.id, onEdit: { editing = $0 }, onJump: jump)
                    .id(n.id)
            }
        }
    }

    private func jump(_ n: Note) {
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

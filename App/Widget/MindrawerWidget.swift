// ホーム画面とロック画面のウィジェット。「今日のひとつ」と近いリマインドを出す。
// メモはアプリと共有している保存フォルダ（App Group）の notes.json から読むだけ。

import AppIntents
import HikidashiKit
import SwiftUI
import WidgetKit

struct DrawerEntry: TimelineEntry {
    let date: Date
    let pick: Note?
    let upcoming: [Note]
}

struct DrawerProvider: TimelineProvider {
    static func loadNotes() -> [Note] {
        let url = SharedContainer.root.appendingPathComponent("notes.json")
        guard let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(ExportFile.self, from: data) else { return [] }
        return file.notes
    }

    static func entry(at date: Date = Date()) -> DrawerEntry {
        let notes = loadNotes()
        return DrawerEntry(date: date, pick: Heuristics.todaysPick(notes, now: date), upcoming: Array(Heuristics.upcoming(notes, now: date).prefix(2)))
    }

    func placeholder(in context: Context) -> DrawerEntry {
        DrawerEntry(date: Date(),
                    pick: Note(text: "", title: L("シミは叩いて落とす", "Blot stains, never rub"), summary: L("こすらず外から内へ叩く。", "Work from the outside in."), category: L("暮らし・家事", "Home")),
                    upcoming: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (DrawerEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : Self.entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DrawerEntry>) -> Void) {
        // 日付が変わったら「今日のひとつ」が替わる
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .minute, value: 5, to: cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: Date())!))!
        completion(Timeline(entries: [Self.entry()], policy: .after(tomorrow)))
    }
}

struct DrawerWidgetView: View {
    let entry: DrawerEntry
    @Environment(\.widgetFamily) private var family

    private let accent = Color(red: 0.78, green: 0.33, blue: 0.24)

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular: accessory
            case .systemMedium: medium
            default: small
            }
        }
        .containerBackground(for: .widget) { Color(red: 0.965, green: 0.96, blue: 0.95) }
        .widgetURL(entry.pick.map { URL(string: "mindrawer://note/\($0.id)")! } ?? URL(string: "mindrawer://")!)
    }

    private var empty: some View {
        Text(L("Tips をしまうと、ここに出ます", "Save a tip to see it here"))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func pickView(_ n: Note, lines: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("今日のひとつ", "TODAY'S PICK")).font(.caption2.weight(.bold)).foregroundStyle(accent)
            Text(n.title).font(.headline).foregroundStyle(.black).lineLimit(3)
            if !n.summary.isEmpty {
                Text(n.summary).font(.caption).foregroundStyle(.black.opacity(0.6)).lineLimit(lines)
            }
        }
    }

    private var small: some View {
        VStack(alignment: .leading) {
            if let n = entry.pick { pickView(n, lines: 2) } else { empty }
            Spacer(minLength: 0)
            Text("Mindrawer").font(.caption2.weight(.semibold)).foregroundStyle(.black.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading) {
                if let n = entry.pick { pickView(n, lines: 3) } else { empty }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !entry.upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("リマインド", "REMINDERS")).font(.caption2.weight(.bold)).foregroundStyle(accent)
                    ForEach(entry.upcoming, id: \.id) { n in
                        Link(destination: URL(string: "mindrawer://note/\(n.id)")!) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(n.remindAt ?? "").font(.caption2.monospacedDigit()).foregroundStyle(.black.opacity(0.5))
                                Text(n.title).font(.caption).foregroundStyle(.black).lineLimit(2)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: 130, alignment: .leading)
            }
        }
    }

    private var accessory: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(L("今日のひとつ", "Today's pick")).font(.caption2.weight(.semibold))
            Text(entry.pick?.title ?? L("Tips をしまう", "Save a tip")).font(.caption).lineLimit(2)
        }
    }
}

struct DrawerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MindrawerDrawer", provider: DrawerProvider()) { entry in
            DrawerWidgetView(entry: entry)
        }
        .configurationDisplayName(L("今日のひとつ", "Today's pick"))
        .description(L("しまったままの Tips と、近いリマインドを出します。", "Shows a stored tip and upcoming reminders."))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

/// コントロールセンター・ロック画面・アクションボタンに置ける「しまう」ボタン（iOS 18 以降）
@available(iOS 18.0, *)
struct QuickSaveControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "MindrawerQuickSave") {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "mindrawer://save")!)) {
                Label(L("しまう", "Save a tip"), systemImage: "tray.and.arrow.down")
            }
        }
        .displayName(LocalizedStringResource(stringLiteral: L("Mindrawer にしまう", "Save to Mindrawer")))
    }
}

// MARK: 今日の確認リスト（ロック画面・ホーム画面。iOS 17 以降はその場でチェックできる）

struct TodayEntry: TimelineEntry {
    let date: Date
    let items: [TodayItem]
    let checked: Set<String>
    var done: Int { items.filter { checked.contains($0.note.id) }.count }
}

struct TodayProvider: TimelineProvider {
    static func entry(at date: Date = Date()) -> TodayEntry {
        let items = Heuristics.todayList(DrawerProvider.loadNotes(), now: date)
        let day = Heuristics.dayFormatter.string(from: date)
        let checked = Set(NoteStore.loadChecks()[day] ?? [])
        return TodayEntry(date: date, items: items, checked: checked)
    }

    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), items: [
            TodayItem(note: Note(id: "p1", text: "", title: L("最初の 30 秒だけ暗記する", "Memorize just the first 30 seconds")), time: nil, reason: .planned),
            TodayItem(note: Note(id: "p2", text: "", title: L("服は 1 日ずつ袋に分ける", "Pack each day's clothes in a bag")), time: nil, reason: .planned),
        ], checked: ["p2"])
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : Self.entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        // アラームの時刻と、日付が変わったときに描き直す
        let cal = Calendar.current
        let now = Date()
        let tomorrow = cal.date(byAdding: .minute, value: 1, to: cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: now)!))!
        let times = Heuristics.todayList(DrawerProvider.loadNotes(), now: now).compactMap(\.time).filter { $0 > now }
        let dates = [now] + times
        completion(Timeline(entries: dates.map { Self.entry(at: $0) }, policy: .after(tomorrow)))
    }
}

/// ウィジェットの ○ を押したとき（アプリを開かずにチェックする）
struct ToggleCheckIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle a checklist item"
    static var isDiscoverable = false

    @Parameter(title: "Note ID") var noteID: String

    init() {}
    init(noteID: String) { self.noteID = noteID }

    func perform() async throws -> some IntentResult {
        NoteStore.toggleCheck(noteID, day: Heuristics.dayFormatter.string(from: Date()))
        return .result()
    }
}

struct TodayWidgetView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family
    private let accent = Color(red: 0.78, green: 0.33, blue: 0.24)

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryInline: inline
            case .accessoryRectangular: rectangular
            default: list(limit: family == .systemSmall ? 3 : (family == .systemLarge ? 8 : 4))
            }
        }
        .containerBackground(for: .widget) { Color(red: 0.965, green: 0.96, blue: 0.95) }
        .widgetURL(URL(string: "mindrawer://")!)
    }

    private var total: Int { entry.items.count }

    private var circular: some View {
        Gauge(value: Double(entry.done), in: 0...Double(max(total, 1))) {
            Image(systemName: "checklist")
        } currentValueLabel: {
            Text("\(entry.done)/\(total)").font(.caption2.monospacedDigit())
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private var inline: some View {
        let next = entry.items.first { !entry.checked.contains($0.note.id) }
        return Text(next.map { "☐ " + $0.note.title } ?? (total == 0 ? L("今日の確認はありません", "Nothing to check today") : L("今日の分は全部確認しました", "All checked today")))
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(L("今日の確認 \(entry.done)/\(total)", "Today \(entry.done)/\(total)")).font(.caption2.weight(.semibold))
            let open = entry.items.filter { !entry.checked.contains($0.note.id) }.prefix(2)
            if open.isEmpty {
                Text(total == 0 ? L("確認するメモはありません", "Nothing to check") : L("全部確認しました ✓", "All done ✓")).font(.caption)
            }
            ForEach(Array(open), id: \.note.id) { i in
                Text("☐ " + i.note.title).font(.caption).lineLimit(1)
            }
        }
    }

    private func list(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("今日の確認リスト", "TODAY'S CHECKLIST")).font(.caption2.weight(.bold)).foregroundStyle(accent)
                Spacer()
                Text("\(entry.done)/\(total)").font(.caption2.monospacedDigit()).foregroundStyle(.black.opacity(0.5))
            }
            if entry.items.isEmpty {
                Text(L("今日確認するメモはありません", "Nothing to check today")).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(entry.items.prefix(limit), id: \.note.id) { i in
                let on = entry.checked.contains(i.note.id)
                Button(intent: ToggleCheckIntent(noteID: i.note.id)) {
                    HStack(spacing: 6) {
                        Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? accent : .black.opacity(0.4))
                        Text(i.note.title).font(.caption).foregroundStyle(on ? .black.opacity(0.4) : .black).strikethrough(on).lineLimit(1)
                        Spacer(minLength: 0)
                        if let t = i.time { Text(t, style: .time).font(.caption2.monospacedDigit()).foregroundStyle(.black.opacity(0.5)) }
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MindrawerToday", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName(L("今日の確認リスト", "Today's checklist"))
        .description(L("今日確認するメモを並べ、その場でチェックできます。", "Lists today's notes; check them off right here."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

@main
struct MindrawerWidgets: WidgetBundle {
    var body: some Widget {
        DrawerWidget()
        TodayWidget()
        if #available(iOS 18.0, *) {
            QuickSaveControl()
        }
    }
}

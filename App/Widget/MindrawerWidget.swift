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

@main
struct MindrawerWidgets: WidgetBundle {
    var body: some Widget {
        DrawerWidget()
        if #available(iOS 18.0, *) {
            QuickSaveControl()
        }
    }
}

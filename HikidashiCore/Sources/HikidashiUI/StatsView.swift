// 使われ方のまとめ。月ごとにしまった数、フォルダごとの数、よく役立ったメモ、復習の進み具合。

#if os(iOS)
import Charts
import HikidashiKit
import SwiftUI

struct StatsView: View {
    let notes: [Note]

    var body: some View {
        let s = Heuristics.usageStats(notes)
        List {
            Section {
                HStack {
                    stat(L("しまった数", "Notes"), "\(s.total)")
                    stat(L("今月", "This month"), "\(s.addedThisMonth)")
                    stat(L("お気に入り", "Favorites"), "\(s.favorites)")
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            }
            Section(L("月ごとにしまった数", "Saved per month")) {
                Chart(s.perMonth, id: \.month) { m in
                    BarMark(x: .value(L("月", "Month"), String(m.month.suffix(2))), y: .value(L("件数", "Notes"), m.count))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(height: 180)
                .accessibilityLabel(s.perMonth.map { "\($0.month): \($0.count)" }.joined(separator: ", "))
            }
            if !s.perFolder.isEmpty {
                Section(L("フォルダごと", "By folder")) {
                    Chart(s.perFolder, id: \.folder) { f in
                        BarMark(x: .value(L("件数", "Notes"), f.count), y: .value(L("フォルダ", "Folder"), f.folder))
                            .foregroundStyle(Color.accentColor.opacity(0.8))
                            .annotation(position: .trailing) { Text("\(f.count)").font(.caption2).foregroundStyle(.secondary) }
                    }
                    .frame(height: CGFloat(max(1, s.perFolder.count)) * 30 + 10)
                }
            }
            if !s.topHelpful.isEmpty {
                Section(L("よく役立ったメモ", "Most helpful")) {
                    ForEach(s.topHelpful) { n in
                        HStack {
                            Text(n.title).lineLimit(1)
                            Spacer()
                            Label("\(n.helpful)", systemImage: "hand.thumbsup").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section(L("ほか", "More")) {
                LabeledContent(L("復習中", "Learning"), value: "\(s.reviewing)")
                LabeledContent(L("覚えた（30 日以上あけても覚えていた）", "Learned (remembered after 30+ days)"), value: "\(s.learned)")
                LabeledContent(L("通知・リマインド付き", "With a reminder"), value: "\(s.withNotification)")
            }
        }
        .navigationTitle(L("使われ方のまとめ", "Your stats"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.weight(.bold).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
#endif

// 一覧の絞り込みの設定画面。

#if os(iOS)
import HikidashiKit
import SwiftUI

struct FilterSheet: View {
    @Binding var filter: NoteFilter
    let notes: [Note]

    @Environment(\.dismiss) private var dismiss

    private func periodLabel(_ p: NoteFilter.Period) -> String {
        switch p {
        case .all: return L("すべて", "Any time")
        case .week: return L("1 週間", "Past week")
        case .month: return L("1 か月", "Past month")
        case .quarter: return L("3 か月", "Past 3 months")
        case .year: return L("1 年", "Past year")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("しまった時期", "Saved")) {
                    Picker(L("期間", "Period"), selection: $filter.period) {
                        ForEach(NoteFilter.Period.allCases, id: \.self) { Text(periodLabel($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Toggle(L("★ お気に入りだけ", "★ Favorites only"), isOn: $filter.favoritesOnly)
                    Toggle(L("写真・ファイル付き", "With a photo or file"), isOn: $filter.withAttachment)
                    Toggle(L("通知・リマインド・場所付き", "With a notification, reminder or place"), isOn: $filter.withNotification)
                    Toggle(L("整理待ちだけ", "Not filed yet"), isOn: $filter.unfiledOnly)
                }
                let tags = NoteFilter.popularTags(notes)
                if !tags.isEmpty {
                    Section(L("タグ（どれかが付いているもの）", "Tags (any of)")) {
                        FlowTags(tags: tags, selected: $filter.tags)
                    }
                }
            }
            .navigationTitle(L("絞り込み", "Filter"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("リセット", "Reset")) { filter = NoteFilter() }.disabled(!filter.isActive)
                }
                ToolbarItem(placement: .confirmationAction) { Button(L("完了", "Done")) { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// タグを折り返して並べる
private struct FlowTags: View {
    let tags: [String]
    @Binding var selected: Set<String>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: [GridItem(.fixed(34)), GridItem(.fixed(34)), GridItem(.fixed(34))], spacing: 6) {
                ForEach(tags, id: \.self) { t in
                    let on = selected.contains(t)
                    Button("#" + t) {
                        if on { selected.remove(t) } else { selected.insert(t) }
                    }
                    .buttonStyle(.bordered)
                    .tint(on ? Color.accentColor : Color.secondary)
                    .controlSize(.small)
                }
            }
        }
        .frame(height: 116)
    }
}
#endif

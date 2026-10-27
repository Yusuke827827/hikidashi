// フォルダの管理。作る・名前を変える・まとめる・消す・お気に入りにする。
// 似ているフォルダがあれば、まとめる提案も出す。

#if os(iOS)
import HikidashiKit
import SwiftUI

/// 「別のままにする」を選んだ提案（もう出さない）
enum MergeDismissals {
    static let key = "folderMergeDismissed"

    static var all: Set<String> { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }

    static func dismiss(_ s: FolderMergeSuggestion) {
        UserDefaults.standard.set(Array(all.union([s.key])), forKey: key)
    }
}

/// 似ているフォルダをまとめる提案のカード（一覧の上と、フォルダの管理に出す）
struct MergeSuggestionCard: View {
    let suggestion: FolderMergeSuggestion
    let store: NoteStore
    var onDone: () -> Void

    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("似ているフォルダがあります", "Similar folders"), systemImage: "arrow.triangle.merge")
                .font(.caption.weight(.bold))
                .foregroundStyle(p.accent)
            Text(L("「\(suggestion.from)」を「\(suggestion.into)」にまとめますか？",
                   "Merge \"\(suggestion.from)\" into \"\(suggestion.into)\"?"))
                .font(.subheadline)
                .foregroundStyle(p.text)
            HStack {
                Button(L("まとめる", "Merge")) {
                    withAnimation { store.mergeFolders([suggestion.from], into: suggestion.into) }
                    onDone()
                }
                .buttonStyle(PrimaryButtonStyle())
                Button(L("別のままにする", "Keep separate")) {
                    MergeDismissals.dismiss(suggestion)
                    onDone()
                }
                .font(.subheadline)
                .foregroundStyle(p.muted)
                Spacer()
            }
        }
        .card()
    }
}

struct FolderManagerView: View {
    let store: NoteStore

    @Environment(\.dismiss) private var dismiss
    @State private var creating = false
    @State private var newName = ""
    @State private var renaming: String?
    @State private var renameText = ""
    @State private var merging: String?
    @State private var deleting: String?
    @State private var refresh = 0

    private var suggestions: [FolderMergeSuggestion] {
        _ = refresh
        return Heuristics.folderMergeSuggestions(store.notes, folders: store.folders, dismissed: MergeDismissals.all, limit: 3)
    }

    var body: some View {
        NavigationStack {
            List {
                if !suggestions.isEmpty {
                    Section(L("まとめる提案", "Suggestions")) {
                        ForEach(suggestions, id: \.key) { s in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L("「\(s.from)」→「\(s.into)」", "\"\(s.from)\" → \"\(s.into)\""))
                                HStack {
                                    Button(L("まとめる", "Merge")) { store.mergeFolders([s.from], into: s.into); refresh += 1 }
                                        .buttonStyle(.borderedProminent)
                                    Button(L("別のままにする", "Keep separate")) { MergeDismissals.dismiss(s); refresh += 1 }
                                        .buttonStyle(.bordered)
                                }
                                .controlSize(.small)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                Section {
                    ForEach(store.folders, id: \.self) { name in
                        row(name)
                    }
                } header: {
                    Text(L("フォルダ", "Folders"))
                } footer: {
                    Text(L("★ でお気に入りにすると、一覧の先頭に出ます。左にスワイプで消す・名前を変える・まとめる。消したフォルダのメモは「その他」に移ります。",
                           "Tap ★ to favorite a folder; favorites come first. Swipe left to delete, rename or merge. Notes in a deleted folder move to Other."))
                }
            }
            .navigationTitle(L("フォルダの管理", "Manage folders"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("完了", "Done")) { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { newName = ""; creating = true } label: { Image(systemName: "folder.badge.plus") }
                        .accessibilityLabel(L("新しいフォルダ", "New folder"))
                }
            }
            .alert(L("新しいフォルダ", "New folder"), isPresented: $creating) {
                TextField(L("名前", "Name"), text: $newName)
                Button(L("作る", "Create")) { store.createFolder(newName) }
                Button(L("キャンセル", "Cancel"), role: .cancel) {}
            }
            .alert(L("名前を変える", "Rename"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField(L("名前", "Name"), text: $renameText)
                Button(L("変える", "Rename")) { if let r = renaming { store.renameFolder(r, to: renameText) }; renaming = nil }
                Button(L("キャンセル", "Cancel"), role: .cancel) { renaming = nil }
            } message: {
                Text(L("同じ名前のフォルダがあれば、そこにまとめます。", "If a folder with that name exists, they're merged."))
            }
            .confirmationDialog(L("「\(deleting ?? "")」を消しますか？", "Delete \"\(deleting ?? "")\"?"),
                                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button(L("消す（メモは「その他」へ）", "Delete (notes move to Other)"), role: .destructive) {
                    if let d = deleting { store.deleteFolder(d) }
                    deleting = nil
                }
            }
            .sheet(item: Binding(get: { merging.map(MergeSource.init) }, set: { merging = $0?.name })) { src in
                MergeTargetPicker(store: store, source: src.name) { merging = nil }
            }
        }
    }

    private func row(_ name: String) -> some View {
        let count = store.folderCounts[name] ?? 0
        let fav = store.isFavoriteFolder(name)
        return HStack {
            Button { store.setFavoriteFolder(name, !fav) } label: {
                Image(systemName: fav ? "star.fill" : "star").foregroundStyle(fav ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(L("お気に入り", "Favorite"))
            Text(name)
            Spacer()
            Text("\(count)").monospacedDigit().foregroundStyle(.secondary)
        }
        .swipeActions(edge: .trailing) {
            if name != Heuristics.otherFolder {
                Button(role: .destructive) { deleting = name } label: { Label(L("消す", "Delete"), systemImage: "trash") }
            }
            Button { renameText = name; renaming = name } label: { Label(L("名前", "Rename"), systemImage: "pencil") }
                .tint(.orange)
            Button { merging = name } label: { Label(L("まとめる", "Merge"), systemImage: "arrow.triangle.merge") }
                .tint(.blue)
        }
    }
}

private struct MergeSource: Identifiable {
    let name: String
    var id: String { name }
}

/// まとめる先を選ぶ
private struct MergeTargetPicker: View {
    let store: NoteStore
    let source: String
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            List(store.folders.filter { $0 != source }, id: \.self) { target in
                Button {
                    store.mergeFolders([source], into: target)
                    onDone()
                } label: {
                    HStack {
                        Text(target)
                        Spacer()
                        Text("\(store.folderCounts[target] ?? 0)").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(L("「\(source)」をまとめる先", "Merge \"\(source)\" into"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("キャンセル", "Cancel")) { onDone() } }
            }
        }
    }
}
#endif

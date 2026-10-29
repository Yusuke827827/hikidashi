// ゴミ箱。消したメモは 30 日ここに残り、元に戻せる。

#if os(iOS)
import HikidashiKit
import SwiftUI

struct TrashView: View {
    let store: NoteStore

    @State private var confirmEmpty = false

    var body: some View {
        List {
            if store.trash.isEmpty {
                Text(L("ゴミ箱は空です。", "The trash is empty.")).foregroundStyle(.secondary)
            }
            ForEach(store.trash) { t in
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.note.title.isEmpty ? String(t.note.text.prefix(40)) : t.note.title)
                    Text(L("あと \(daysLeft(t)) 日で消えます", "Deleted for good in \(daysLeft(t)) days"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .swipeActions(edge: .leading) {
                    Button { store.restore(t.id) } label: { Label(L("戻す", "Restore"), systemImage: "arrow.uturn.backward") }
                        .tint(.green)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { store.deleteForever([t.id]) } label: { Label(L("完全に消す", "Delete"), systemImage: "trash") }
                }
                .contextMenu {
                    Button { store.restore(t.id) } label: { Label(L("戻す", "Restore"), systemImage: "arrow.uturn.backward") }
                }
            }
        }
        .navigationTitle(L("ゴミ箱", "Trash"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !store.trash.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(L("空にする", "Empty"), role: .destructive) { confirmEmpty = true }
                }
            }
        }
        .confirmationDialog(L("ゴミ箱を空にしますか？元に戻せません。", "Empty the trash? This can't be undone."), isPresented: $confirmEmpty, titleVisibility: .visible) {
            Button(L("空にする", "Empty"), role: .destructive) { store.emptyTrash() }
        }
    }

    private func daysLeft(_ t: TrashedNote) -> Int {
        let passed = Int(Date().timeIntervalSince(t.deletedAt) / 86400)
        return max(0, NoteStore.trashDays - passed)
    }
}
#endif

// メモの手入れのカード: ダブったメモをまとめる、古くなったメモを見直す、覚えるメモを復習する。

#if os(iOS)
import HikidashiKit
import SwiftUI

/// 「別のままにする」を選んだダブりの組（もう出さない）
enum DuplicateDismissals {
    static let key = "duplicateDismissed"
    static var all: Set<String> { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
    static func dismiss(_ p: DuplicatePair) { UserDefaults.standard.set(Array(all.union([p.key])), forKey: key) }
}

struct DuplicateCard: View {
    let pair: DuplicatePair
    let librarian: Librarian
    var onDone: () -> Void

    @Environment(\.palette) private var p

    var body: some View {
        let store = librarian.store
        VStack(alignment: .leading, spacing: 10) {
            Label(L("同じようなメモがあります", "These look the same"), systemImage: "doc.on.doc")
                .font(.caption.weight(.bold))
                .foregroundStyle(p.accent)
            ForEach([pair.keep, pair.drop], id: \.self) { id in
                if let n = store.note(id) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(n.title).font(.subheadline.weight(.semibold)).foregroundStyle(p.text).lineLimit(1)
                        Text(n.text).font(.caption).foregroundStyle(p.muted).lineLimit(2)
                    }
                }
            }
            HStack {
                Button(L("1 つにまとめる", "Merge into one")) {
                    withAnimation { librarian.mergeDuplicate(pair) }
                    onDone()
                }
                .buttonStyle(PrimaryButtonStyle())
                Button(L("別のままにする", "Keep both")) {
                    DuplicateDismissals.dismiss(pair)
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

struct StaleCard: View {
    let items: [StaleItem]
    let librarian: Librarian
    var onEdit: (Note) -> Void

    @Environment(\.palette) private var p

    var body: some View {
        let store = librarian.store
        VStack(alignment: .leading, spacing: 12) {
            Label(L("見直したいメモ", "Worth a check"), systemImage: "clock.arrow.circlepath")
                .font(.caption.weight(.bold))
                .foregroundStyle(p.accent)
            ForEach(items, id: \.note.id) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.note.title).font(.subheadline.weight(.semibold)).foregroundStyle(p.text).lineLimit(2)
                    Text(item.label).font(.caption).foregroundStyle(p.muted)
                    HStack(spacing: 14) {
                        Button(L("まだ使える", "Still good")) {
                            withAnimation { store.update(item.note.id) { $0.checkedAt = Date(); $0.linkBroken = nil } }
                        }
                        Button(L("直す", "Edit")) { onEdit(item.note) }
                        Button(L("ゴミ箱へ", "Trash"), role: .destructive) { withAnimation { store.remove(item.note.id) } }
                    }
                    .font(.footnote.weight(.semibold))
                }
            }
        }
        .card()
    }
}

struct ReviewCard: View {
    let notes: [Note]
    let store: NoteStore

    @Environment(\.palette) private var p
    @State private var revealed = false

    var body: some View {
        if let n = notes.first {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(L("今日の復習", "Review"), systemImage: "brain.head.profile")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(p.accent)
                    Spacer()
                    Text(L("残り \(notes.count) 件", "\(notes.count) left")).font(.caption.monospacedDigit()).foregroundStyle(p.muted)
                }
                Text(n.title).font(.headline).foregroundStyle(p.text)
                if revealed {
                    Text(n.text).font(.callout).foregroundStyle(p.text.opacity(0.9)).textSelection(.enabled)
                    HStack {
                        Button(L("覚えてた", "Remembered")) { answer(n, true) }.buttonStyle(PrimaryButtonStyle())
                        Button(L("忘れてた", "Forgot")) { answer(n, false) }.font(.subheadline.weight(.semibold)).foregroundStyle(p.accent)
                        Spacer()
                    }
                } else {
                    Button(L("中身を見る", "Show it")) { withAnimation { revealed = true } }
                        .font(.subheadline.weight(.semibold))
                }
            }
            .card()
        }
    }

    private func answer(_ n: Note, _ remembered: Bool) {
        withAnimation {
            store.update(n.id) { $0.review = ($0.review ?? .start()).answered(remembered: remembered) }
            revealed = false
        }
    }
}
#endif

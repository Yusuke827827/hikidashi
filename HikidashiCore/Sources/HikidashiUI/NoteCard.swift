// メモ 1 件のカード。開くと原文・出典・関連メモが出る。

#if os(iOS)
import HikidashiKit
import QuickLook
import SwiftUI

struct NoteCard: View {
    let note: Note
    let librarian: Librarian
    var highlighted = false
    var onEdit: (Note) -> Void
    var onJump: (Note) -> Void

    @Environment(\.palette) private var p
    @State private var expanded = false
    @State private var confirmDelete = false
    @State private var sharedImage: SharedImage?
    @State private var previewURL: URL?
    @State private var publishing = false
    @State private var exportMessage: String?

    private var store: NoteStore { librarian.store }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(note.category.isEmpty ? Heuristics.otherFolder : note.category)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(p.accent)
                if librarian.filing.contains(note.id) {
                    ProgressView().controlSize(.mini)
                    Text(L("整理中", "Filing")).font(.caption2).foregroundStyle(p.muted)
                } else if !note.filed {
                    Text(L("整理待ち", "Not filed yet")).font(.caption2).foregroundStyle(p.muted)
                }
                Spacer()
                Text(note.createdAt, format: .dateTime.year().month().day())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(p.muted)
            }
            Text(note.title)
                .font(.headline)
                .foregroundStyle(p.text)
                .fixedSize(horizontal: false, vertical: true)
            if !note.summary.isEmpty {
                Text(note.summary).font(.subheadline).foregroundStyle(p.text.opacity(0.88))
            }
            if let name = note.imageFile, let ui = UIImage(contentsOfFile: store.imageURL(name).path) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: expanded ? 420 : 160)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if let f = note.file {
                Button { previewURL = store.imageURL(f) } label: {
                    Label(note.fileTitle ?? f, systemImage: "doc.text")
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 32)
                        .background(RoundedRectangle(cornerRadius: 8).fill(p.surface2))
                }
                .foregroundStyle(p.text)
                .quickLookPreview($previewURL)
            }
            chips
            if expanded { details }
            actions
        }
        .card()
        .overlay {
            if highlighted { RoundedRectangle(cornerRadius: 14).stroke(p.accent, lineWidth: 2) }
        }
        .confirmationDialog(L("このメモを削除しますか？", "Delete this note?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("ゴミ箱へ（30 日は戻せます）", "Move to trash (restorable for 30 days)"), role: .destructive) { store.remove(note.id) }
        }
    }

    @ViewBuilder private var chips: some View {
        let hasChips = note.remindAt != nil || note.alarm != nil || note.review != nil || note.linkBroken == true || !note.situations.isEmpty || !note.tags.isEmpty
        if hasChips {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if let r = note.remindAt { Chip(text: "⏰ " + r, kind: .remind) }
                    if let a = note.alarm, !a.summary.isEmpty { Chip(text: "🔔 " + a.summary, kind: .remind) }
                    if note.review != nil { Chip(text: L("🧠 復習中", "🧠 Learning"), kind: .remind) }
                    if note.linkBroken == true { Chip(text: L("リンク切れ", "Broken link"), kind: .remind) }
                    ForEach(note.situations, id: \.self) { Chip(text: $0, kind: .situation) }
                    ForEach(note.tags, id: \.self) { Chip(text: $0, kind: .tag) }
                }
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(note.text)
                .font(.callout)
                .foregroundStyle(p.muted)
                .textSelection(.enabled)
                .padding(.leading, 10)
                .overlay(alignment: .leading) { Rectangle().fill(p.line).frame(width: 2) }
            if let original = note.original, original != note.text {
                DisclosureGroup {
                    Text(original)
                        .font(.footnote)
                        .foregroundStyle(p.muted)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(L("元の文に戻す", "Restore the original")) { librarian.restoreOriginal(note.id) }
                        .font(.footnote)
                } label: {
                    Text(L("メモ風に整える前の文", "Text before it was condensed")).font(.footnote).foregroundStyle(p.muted)
                }
                .tint(p.accent)
            }
            if let s = note.url, let url = URL(string: s) {
                Link(s, destination: url).font(.footnote).lineLimit(2)
            }
            if let src = note.sources?.compactMap({ store.note($0) }), !src.isEmpty {
                Text(L("まとめた元のメモ", "Combined from").uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(p.muted).tracking(1)
                ForEach(src) { r in
                    Button("→ " + r.title) { onJump(r) }.font(.footnote).foregroundStyle(p.accent)
                }
            }
            let related = Heuristics.related(to: note, in: store.notes)
            if !related.isEmpty {
                Text(L("関連", "Related").uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(p.muted).tracking(1)
                ForEach(related) { r in
                    Button("→ " + r.title) { onJump(r) }.font(.footnote).foregroundStyle(p.accent)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 2) {
            Button(expanded ? L("閉じる", "Less") : L("原文と関連", "More")) {
                withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() }
            }
            Spacer()
            Button {
                store.update(note.id) { $0.pinned.toggle() }
            } label: {
                Image(systemName: note.pinned ? "star.fill" : "star").frame(width: 36, height: 32)
            }
            .foregroundStyle(note.pinned ? p.accent : p.muted)
            .accessibilityLabel(L("お気に入り", "Favorite"))
            Button {
                store.update(note.id) { $0.helpful += 1 }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "hand.thumbsup")
                    if note.helpful > 0 { Text("\(note.helpful)").monospacedDigit() }
                }
                .frame(minWidth: 36, minHeight: 32)
            }
            .accessibilityLabel(L("役立った", "Helpful"))
            Menu {
                Button { onEdit(note) } label: { Label(L("編集", "Edit"), systemImage: "pencil") }
                if librarian.hasAI {
                    Button { Task { await librarian.file(note.id) } } label: { Label(L("AI で再整理", "Re-file with AI"), systemImage: "sparkles") }
                }
                let today = Heuristics.dayFormatter.string(from: Date())
                Button {
                    store.update(note.id) { $0.plannedDay = $0.plannedDay == today ? nil : today }
                } label: {
                    Label(note.plannedDay == today ? L("今日のリストから外す", "Remove from today's list") : L("今日のリストに入れる", "Add to today's list"),
                          systemImage: "checklist")
                }
                Button {
                    store.update(note.id) { $0.review = $0.review == nil ? .start() : nil }
                } label: {
                    Label(note.review == nil ? L("覚える（復習に出す）", "Learn it (add to review)") : L("復習から外す", "Stop reviewing"),
                          systemImage: "brain.head.profile")
                }
                Button {
                    sharedImage = ShareCard.image(for: note, palette: p).map(SharedImage.init)
                } label: { Label(L("画像で共有", "Share as image"), systemImage: "photo.on.rectangle") }
                if let s = note.url, let url = URL(string: s) {
                    ShareLink(item: url) { Label(L("出典を共有", "Share source"), systemImage: "square.and.arrow.up") }
                }
                Button { publishing = true } label: {
                    Label(PublicLinks.all()[note.id] == nil ? L("公開リンクを作る", "Create a public link") : L("公開リンク", "Public link"), systemImage: "globe")
                }
                Button { Task { exportMessage = await CalendarExport.addEvent(note) } } label: {
                    Label(L("カレンダーに入れる", "Add to Calendar"), systemImage: "calendar.badge.plus")
                }
                Button { Task { exportMessage = await CalendarExport.addReminder(note) } } label: {
                    Label(L("リマインダーに入れる", "Add to Reminders"), systemImage: "checklist.checked")
                }
                Button(role: .destructive) { confirmDelete = true } label: { Label(L("削除", "Delete"), systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis").frame(width: 36, height: 32)
            }
        }
        .font(.footnote)
        .foregroundStyle(p.muted)
        .sheet(isPresented: $publishing) { PublicLinkSheet(note: note) }
        .alert(exportMessage ?? "", isPresented: Binding(get: { exportMessage != nil }, set: { if !$0 { exportMessage = nil } })) {
            Button("OK") { exportMessage = nil }
        }
        .sheet(item: $sharedImage) { item in
            ActivityView(items: [item.image]).presentationDetents([.medium, .large])
        }
    }
}
#endif

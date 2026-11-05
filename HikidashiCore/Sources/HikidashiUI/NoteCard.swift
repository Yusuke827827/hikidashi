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
    /// タグを押したとき（そのタグで絞り込む）
    var onTag: ((String) -> Void)? = nil

    @Environment(\.palette) private var p
    @State private var expanded = false
    @State private var confirmDelete = false
    @State private var sharedImage: SharedImage?
    @State private var previewURL: URL?
    @State private var publishing = false
    @State private var exportMessage: String?
    @State private var showHistory = false
    @State private var showSteps = false
    @AppStorage("simpleMode") private var simpleMode = false
    private var secrets: SecretNotes { SecretNotes.shared }
    private var hidden: Bool { secrets.isHidden(note) }

    private var store: NoteStore { librarian.store }
    private var folderName: String { note.category.isEmpty ? Heuristics.otherFolder : note.category }
    private var folderColor: Color { Looks.color(store.folderLook(folderName).color) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                FolderBadge(name: folderName, store: store)
                Text(folderName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(folderColor)
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
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if note.isLocked {
                    Image(systemName: hidden ? "lock.fill" : "lock.open").font(.footnote).foregroundStyle(p.muted)
                }
                Text(note.title)
                    .font(.headline)
                    .foregroundStyle(p.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if hidden {
                Button {
                    Task { await secrets.unlock(note.id) }
                } label: {
                    Label(L("秘密のメモ・\(AppLock.biometryName) で開く", "Secret note · unlock with \(AppLock.biometryName)"), systemImage: "faceid")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .background(RoundedRectangle(cornerRadius: 8).fill(p.surface2))
                }
                .foregroundStyle(p.text)
            } else {
                content
            }
            chips
            if expanded && !hidden { details }
            actions
        }
        .card()
        .accessibilityElement(children: .contain)
        .overlay(alignment: .leading) {
            // フォルダの色の線
            Capsule().fill(folderColor.opacity(0.85)).frame(width: 3).padding(.vertical, 14)
        }
        .overlay {
            if highlighted { RoundedRectangle(cornerRadius: 14).stroke(p.accent, lineWidth: 2) }
        }
        .confirmationDialog(L("このメモを削除しますか？", "Delete this note?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("ゴミ箱へ（30 日は戻せます）", "Move to trash (restorable for 30 days)"), role: .destructive) { store.remove(note.id) }
        }
        .sheet(isPresented: $showHistory) { HistorySheet(note: note, store: store) }
        .fullScreenCover(isPresented: $showSteps) { StepsView(note: note).environment(\.palette, p) }
    }

    @ViewBuilder private var content: some View {
        if Vault.cannotOpen(note) {
            Text(L("別の端末（Web 版など）で鍵をかけたメモです。この iPhone では開けません。", "Locked on another device (like the web version). It can't be opened on this iPhone."))
                .font(.footnote).foregroundStyle(p.muted)
        }
        if !note.summary.isEmpty {
            Text(note.summary).font(.subheadline).foregroundStyle(p.text.opacity(0.88))
        }
        let items = Heuristics.checkItems(note.text)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(items, id: \.line) { it in
                    Button {
                        store.update(note.id) { $0.text = Heuristics.toggleCheck($0.text, line: it.line) }
                        UsageLog.record(note.id)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: it.done ? "checkmark.square.fill" : "square")
                                .foregroundStyle(it.done ? p.accent : p.muted)
                            Text(it.text)
                                .font(.subheadline)
                                .strikethrough(it.done)
                                .foregroundStyle(it.done ? p.muted : p.text)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 30)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(it.text)
                    .accessibilityValue(it.done ? L("済み", "Done") : L("まだ", "Not done"))
                }
            }
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
    }

    @ViewBuilder private var chips: some View {
        let hasChips = !(note.comments ?? []).isEmpty || note.readLater == true || note.addedBy != nil || note.archived == true || note.savedPlace != nil || note.expiresAt != nil || note.remindAt != nil || note.alarm != nil || note.review != nil || note.linkBroken == true || !note.situations.isEmpty || !note.tags.isEmpty
        if hasChips {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if let cs = note.comments, !cs.isEmpty { Chip(text: "\(cs.count)", kind: .situation, symbol: "bubble.left") }
                    if note.readLater == true {
                        Chip(text: note.readAt == nil ? L("あとで読む", "Read later") : L("読んだ", "Read"), kind: .remind, symbol: note.readAt == nil ? "bookmark" : "checkmark")
                    }
                    if note.archived == true { Chip(text: L("しまい込んだ", "Archived"), kind: .situation, symbol: "archivebox") }
                    if let by = note.addedBy, !by.isEmpty { Chip(text: by, kind: .situation, symbol: "person") }
                    if let pl = note.savedPlace, !pl.name.isEmpty { Chip(text: pl.name, kind: .situation, symbol: "mappin") }
                    if let d = note.daysLeft() {
                        Chip(text: d == 0 ? L("今日まで", "Ends today") : L("あと \(d) 日", "\(d) days left"), kind: .remind, symbol: "hourglass")
                    }
                    if let r = note.remindAt { Chip(text: r, kind: .remind, symbol: "calendar") }
                    if let a = note.alarm, !a.summary.isEmpty { Chip(text: a.summary, kind: .remind, symbol: "bell") }
                    if note.review != nil { Chip(text: L("復習中", "Learning"), kind: .remind, symbol: "brain.head.profile") }
                    if note.linkBroken == true { Chip(text: L("リンク切れ", "Broken link"), kind: .remind, symbol: "link") }
                    ForEach(note.situations, id: \.self) { Chip(text: $0, kind: .situation) }
                    ForEach(note.tags, id: \.self) { t in
                        if let onTag {
                            Button { onTag(t) } label: { Chip(text: t, kind: .tag, tint: folderColor) }.buttonStyle(.plain)
                        } else {
                            Chip(text: t, kind: .tag, tint: folderColor)
                        }
                    }
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
            if let a = note.archive {
                DisclosureGroup {
                    Text(String(a.text.prefix(6000)) + (a.text.count > 6000 ? "…" : ""))
                        .font(.footnote)
                        .foregroundStyle(p.muted)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label(L("保存したページ（\(a.at.formatted(date: .abbreviated, time: .omitted))）", "Saved page (\(a.at.formatted(date: .abbreviated, time: .omitted)))"), systemImage: "doc.text.magnifyingglass")
                        .font(.footnote).foregroundStyle(p.muted)
                }
                .tint(p.accent)
            }
            if let src = note.sources?.compactMap({ store.note($0) }), !src.isEmpty {
                Text(L("まとめた元のメモ", "Combined from").uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(p.muted).tracking(1)
                ForEach(src) { r in
                    Button("→ " + r.title) { onJump(r) }.font(.footnote).foregroundStyle(p.accent)
                }
            }
            SeriesNav(note: note, notes: store.notes, onJump: onJump)
            // 共有フォルダのメモには、家族のひとことを付けられる
            if librarian.isShared(folderName) || !(note.comments ?? []).isEmpty {
                CommentsView(note: note, store: store)
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
                if expanded { UsageLog.record(note.id) }
            }
            .disabled(hidden)
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
                UsageLog.record(note.id)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "hand.thumbsup")
                    if note.helpful > 0 { Text("\(note.helpful)").monospacedDigit() }
                }
                .frame(minWidth: 36, minHeight: 32)
            }
            .accessibilityLabel(L("役立った", "Helpful"))
            Menu {
                Button {
                    if hidden { Task { await secrets.unlock(note.id); if !secrets.isHidden(note) { onEdit(note) } } } else { onEdit(note) }
                } label: { Label(L("編集", "Edit"), systemImage: "pencil") }
                if !hidden {
                    if Heuristics.steps(note.text).count >= 2 {
                        Button { showSteps = true; UsageLog.record(note.id) } label: { Label(L("手順モードで見る", "Step-by-step mode"), systemImage: "list.number") }
                    }
                    if note.url != nil {
                        Button {
                            store.update(note.id) { n in
                                if n.readLater == true && n.readAt == nil { n.readAt = Date() } else { n.readLater = true; n.readAt = nil }
                            }
                        } label: {
                            note.readLater == true && note.readAt == nil
                                ? Label(L("読んだ", "Mark as read"), systemImage: "checkmark.circle")
                                : Label(L("あとで読む", "Read later"), systemImage: "bookmark")
                        }
                    }
                    Button {
                        store.update(note.id) { $0.board = $0.board == nil ? BoardColumn.week.rawValue : nil }
                    } label: {
                        Label(note.board == nil ? L("やることボードへ", "Add to to-do board") : L("ボードから外す", "Remove from board"), systemImage: "rectangle.split.3x1")
                    }
                    Button {
                        store.update(note.id) { $0.archived = $0.archived == true ? nil : true }
                    } label: {
                        Label(note.archived == true ? L("しまい込みから戻す", "Unarchive") : L("しまい込む", "Archive"), systemImage: "archivebox")
                    }
                    Button { Speaker.shared.toggle(note) } label: { Label(L("読み上げる", "Read aloud"), systemImage: "speaker.wave.2") }
                    Button { NotePrinter.print([note], title: note.title) } label: { Label(L("印刷・PDF", "Print or PDF"), systemImage: "printer") }
                    if Heuristics.checkItems(note.text).isEmpty {
                        Button { store.update(note.id) { $0.text = Heuristics.toChecklist($0.text) } } label: {
                            Label(L("チェックリストにする", "Make it a checklist"), systemImage: "checklist")
                        }
                    } else if Heuristics.checkItems(note.text).contains(where: \.done) {
                        Button { store.update(note.id) { $0.text = Heuristics.clearChecked($0.text) } } label: {
                            Label(L("済んだ項目を消す", "Clear checked items"), systemImage: "checklist.checked")
                        }
                    }
                }
                if !(note.history ?? []).isEmpty, !hidden {
                    Button { showHistory = true } label: { Label(L("編集の履歴", "Edit history"), systemImage: "clock.arrow.circlepath") }
                }
                Button {
                    if note.isLocked {
                        Task {
                            if await AppLock.authenticate(reason: L("秘密をやめる", "Stop keeping it secret")) { store.update(note.id) { $0.locked = nil } }
                        }
                    } else {
                        store.update(note.id) { $0.locked = true }
                    }
                } label: {
                    Label(note.isLocked ? L("秘密のメモをやめる", "Stop keeping secret") : L("秘密のメモにする", "Make it secret"),
                          systemImage: note.isLocked ? "lock.open" : "lock")
                }
                if librarian.hasAI && !note.isLocked {
                    Button { Task { await librarian.file(note.id) } } label: { Label(L("AI で再整理", "Re-file with AI"), systemImage: "sparkles") }
                }
                let today = Heuristics.dayFormatter.string(from: Date())
                Button {
                    store.update(note.id) { $0.plannedDay = $0.plannedDay == today ? nil : today }
                } label: {
                    Label(note.plannedDay == today ? L("今日のリストから外す", "Remove from today's list") : L("今日のリストに入れる", "Add to today's list"),
                          systemImage: "checklist")
                }
                if !simpleMode {
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

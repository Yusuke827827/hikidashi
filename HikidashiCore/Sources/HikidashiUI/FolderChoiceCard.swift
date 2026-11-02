// しまった直後に出る「どのフォルダに入れますか？」。AI の 3 つの候補から選ぶか、自分で入力する。
// 新しく作る名前に似たフォルダが今あれば、そちらに入れるかを聞く。

#if os(iOS)
import HikidashiKit
import SwiftUI

struct FolderChoiceCard: View {
    let request: FolderChoiceRequest
    let librarian: Librarian

    @Environment(\.palette) private var p
    @State private var typing = false
    @State private var custom = ""
    @State private var confirm: (name: String, similar: String, custom: Bool)?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L("どのフォルダに入れますか？", "Which folder?"), systemImage: "folder.badge.questionmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(p.accent)
                Spacer()
                Button(L("このままでいい", "Keep")) { withAnimation { librarian.dismissFolderChoice() } }
                    .font(.caption)
                    .foregroundStyle(p.muted)
            }
            Text(request.title).font(.subheadline.weight(.semibold)).foregroundStyle(p.text).lineLimit(2)
            FlowLayout(spacing: 8) {
                ForEach(request.options, id: \.name) { o in
                    Button { pick(o.name, similar: o.similar, custom: false) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: o.exists ? "folder.fill" : "folder.badge.plus")
                            Text(o.name)
                            if !o.exists { Text(L("新規", "New")).font(.caption2).foregroundStyle(p.muted) }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(Capsule().fill(p.surface2))
                    }
                    .foregroundStyle(p.text)
                }
                Button { withAnimation { typing = true }; focused = true } label: {
                    Label(L("自分で入力", "Type a name"), systemImage: "pencil")
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(Capsule().stroke(p.line))
                }
                .foregroundStyle(p.muted)
            }
            if typing {
                HStack {
                    TextField(L("フォルダ名", "Folder name"), text: $custom)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(submitCustom)
                    Button(L("決める", "Use"), action: submitCustom)
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Text(L("選んだフォルダから、あなたの分け方を覚えます。", "Mindrawer learns how you name folders from what you pick."))
                .font(.caption2)
                .foregroundStyle(p.muted)
        }
        .card()
        .confirmationDialog(confirm.map { L("似たフォルダ「\($0.similar)」があります", "There's a similar folder: \($0.similar)") } ?? "",
                            isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), titleVisibility: .visible) {
            if let c = confirm {
                Button(L("「\(c.similar)」に入れる", "Put it in \(c.similar)")) { withAnimation { librarian.chooseFolder(c.similar, custom: false) } }
                Button(L("新しく「\(c.name)」を作る", "Create \(c.name)")) { withAnimation { librarian.chooseFolder(c.name, custom: c.custom) } }
            }
        }
    }

    private func submitCustom() {
        let n = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        let existing = librarian.store.folders
        let similar = existing.contains(n) ? nil : existing.first { Heuristics.isSimilarFolderName($0, n) }
        pick(n, similar: similar, custom: true)
    }

    private func pick(_ name: String, similar: String?, custom: Bool) {
        if let similar { confirm = (name, similar, custom); return }
        withAnimation { librarian.chooseFolder(name, custom: custom) }
    }
}

/// 横に並べ、はみ出したら次の行へ
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing
            row = max(row, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            row = max(row, s.height)
        }
    }
}
#endif

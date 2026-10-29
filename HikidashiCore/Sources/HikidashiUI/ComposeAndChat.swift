// まとめノート（いくつかのメモを AI が 1 枚にまとめる）と、メモに聞く（自分のメモと会話する）。

#if os(iOS)
import HikidashiKit
import SwiftUI

/// まとめノートの下書きを確かめて、直してから保存する
struct ComposeSheet: View {
    let librarian: Librarian
    let topic: String
    let noteIDs: [String]
    var onSaved: (Note) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @State private var folder = L("まとめ", "Guides")
    @State private var loading = true

    var body: some View {
        NavigationStack {
            Form {
                if loading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(L("\(noteIDs.count) 件のメモからまとめています…", "Combining \(noteIDs.count) notes…")).foregroundStyle(.secondary)
                    }
                } else {
                    Section(L("タイトル", "Title")) { TextField(L("タイトル", "Title"), text: $title) }
                    Section {
                        TextEditor(text: $text).frame(minHeight: 260)
                    } header: {
                        Text(L("まとめノート（直せます）", "Combined note (you can edit it)"))
                    }
                    Section(L("フォルダ", "Folder")) { TextField(L("フォルダ", "Folder"), text: $folder) }
                }
            }
            .navigationTitle(L("まとめノート", "Combined note"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("キャンセル", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("しまう", "Save")) {
                        let n = librarian.saveComposed(title: title.isEmpty ? topic : title, text: text, sources: noteIDs,
                                                       category: folder.trimmingCharacters(in: .whitespaces).isEmpty ? L("まとめ", "Guides") : folder)
                        onSaved(n)
                        dismiss()
                    }
                    .bold()
                    .disabled(loading || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                let r = await librarian.compose(topic: topic, noteIDs: noteIDs)
                title = r.title
                text = r.text
                loading = false
            }
        }
    }
}

/// メモに聞く
struct ChatView: View {
    let librarian: Librarian
    var onOpen: (Note) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var p
    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var thinking = false
    @FocusState private var focused: Bool

    private var examples: [String] {
        L("先月しまった節約の話って何だっけ？|旅行の前に見ておくメモは？|最近しまったものを 3 つ教えて", "What was that money-saving tip from last month?|What should I check before a trip?|Show me 3 things I saved recently")
            .components(separatedBy: "|")
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if messages.isEmpty {
                            Text(L("しまったメモについて、何でも聞いてください。", "Ask anything about the notes you've saved."))
                                .foregroundStyle(.secondary)
                            ForEach(examples, id: \.self) { e in
                                Button(e) { send(e) }.buttonStyle(.bordered).font(.subheadline)
                            }
                        }
                        ForEach(messages) { m in bubble(m).id(m.id) }
                        if thinking { ProgressView().padding(.leading, 6).id("thinking") }
                    }
                    .padding(16)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 8) {
                    TextField(L("メモに聞く…", "Ask your notes…"), text: $input, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($focused)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(p.surface2))
                        .onSubmit { send(input) }
                    Button { send(input) } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || thinking)
                        .accessibilityLabel(L("送る", "Send"))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .navigationTitle(L("メモに聞く", "Ask your notes"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("閉じる", "Close")) { dismiss() } }
            }
        }
    }

    private func bubble(_ m: ChatMessage) -> some View {
        VStack(alignment: m.role == .user ? .trailing : .leading, spacing: 6) {
            Text(m.text)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14).fill(m.role == .user ? p.accent : p.surface2))
                .foregroundStyle(m.role == .user ? p.accentText : p.text)
                .textSelection(.enabled)
            ForEach(m.noteIDs.compactMap { librarian.store.note($0) }) { n in
                Button {
                    dismiss()
                    onOpen(n)
                } label: {
                    Label(n.title, systemImage: "doc.text").font(.footnote).lineLimit(1)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: m.role == .user ? .trailing : .leading)
    }

    private func send(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !thinking else { return }
        messages.append(ChatMessage(role: .user, text: t))
        input = ""
        thinking = true
        Task {
            let reply = await librarian.chat(messages)
            messages.append(reply)
            thinking = false
        }
    }
}
#endif

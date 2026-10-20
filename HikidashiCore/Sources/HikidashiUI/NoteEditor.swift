// メモの編集。すべての項目を直せる。本文を大きく変えたときは「保存して AI で再整理」を使う。

#if os(iOS)
import HikidashiKit
import SwiftUI

struct NoteEditor: View {
    let note: Note
    let librarian: Librarian

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var text: String
    @State private var summary: String
    @State private var category: String
    @State private var situations: String
    @State private var tags: String
    @State private var url: String
    @State private var hasRemind: Bool
    @State private var remindDate: Date

    init(note: Note, librarian: Librarian) {
        self.note = note
        self.librarian = librarian
        _title = State(initialValue: note.title)
        _text = State(initialValue: note.text)
        _summary = State(initialValue: note.summary)
        _category = State(initialValue: note.category)
        _situations = State(initialValue: note.situations.joined(separator: ", "))
        _tags = State(initialValue: note.tags.joined(separator: ", "))
        _url = State(initialValue: note.url ?? "")
        _hasRemind = State(initialValue: note.remindAt != nil)
        _remindDate = State(initialValue: note.remindAt.flatMap { Heuristics.dayFormatter.date(from: $0) } ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("本文", "Note")) {
                    TextField(L("タイトル", "Title"), text: $title)
                    TextEditor(text: $text).frame(minHeight: 140)
                    TextField(L("要約", "Summary"), text: $summary, axis: .vertical)
                }
                Section(L("整理", "Filing")) {
                    TextField(L("フォルダ", "Folder"), text: $category)
                    if !librarian.store.folders.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(librarian.store.folders, id: \.self) { f in
                                    Button(f) { category = f }.buttonStyle(.bordered).controlSize(.small)
                                }
                            }
                        }
                    }
                    TextField(L("使う場面（カンマ区切り）", "When it helps (comma-separated)"), text: $situations, axis: .vertical)
                    TextField(L("タグ（カンマ区切り）", "Tags (comma-separated)"), text: $tags)
                    Toggle(L("リマインド", "Reminder"), isOn: $hasRemind.animation())
                    if hasRemind {
                        DatePicker(L("日付", "Date"), selection: $remindDate, displayedComponents: .date)
                    }
                }
                Section(L("出典", "Source")) {
                    TextField("https://", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if librarian.hasAI {
                    Section {
                        Button(L("保存して AI で再整理", "Save & re-file with AI")) { commit(refile: true) }
                    } footer: {
                        Text(L("本文を大きく書き換えたときに。フォルダ・使う場面・タグを付け直します。", "Use after a big rewrite. Claude redoes the folder, moments and tags."))
                    }
                }
            }
            .navigationTitle(L("編集", "Edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("キャンセル", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("保存", "Save")) { commit(refile: false) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func split(_ s: String) -> [String] {
        s.components(separatedBy: CharacterSet(charactersIn: ",、，\n"))
            .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "") }
            .filter { !$0.isEmpty }
    }

    private func commit(refile: Bool) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let id = note.id
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let link = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let remind = hasRemind ? Heuristics.dayFormatter.string(from: remindDate) : nil
        librarian.store.update(id) { n in
            n.text = body
            n.title = t.isEmpty ? Heuristics.title(for: body) : t
            n.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            n.category = folder.isEmpty ? Heuristics.otherFolder : folder
            n.situations = split(situations)
            n.tags = split(tags)
            n.url = link.isEmpty ? nil : link
            n.remindAt = remind
        }
        if refile { Task { await librarian.file(id) } }
        dismiss()
    }
}
#endif

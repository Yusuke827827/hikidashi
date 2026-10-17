// 画面上部の入力欄。「しまう」でメモを保存し、「ひきだす」で問いかけに合うメモを探す。

#if os(iOS)
import HikidashiKit
import PhotosUI
import SwiftUI

struct CaptureCard: View {
    enum Mode: Hashable { case save, recall }

    let librarian: Librarian
    var onRecall: (RecallOutcome) -> Void
    var onToast: (String) -> Void

    @Environment(\.palette) private var p
    @State private var mode: Mode = .save
    @State private var text = ""
    @State private var url = ""
    @State private var showURL = false
    @State private var photo: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var query = ""
    @State private var searching = false
    @State private var speech = SpeechInput()
    @FocusState private var focused: Bool

    private var suggestions: [String] {
        AppLanguage.current == .ja
            ? ["これから洗濯する", "旅行の荷造り中", "節約になるやつ", "プレゼン前に緊張する"]
            : ["About to do laundry", "Packing for a trip", "Ways to save money", "Before a presentation"]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $mode) {
                Text(L("しまう", "Save")).tag(Mode.save)
                Text(L("ひきだす", "Recall")).tag(Mode.recall)
            }
            .pickerStyle(.segmented)

            if mode == .save { saveForm } else { recallForm }

            if let e = speech.error {
                Text(e).font(.footnote).foregroundStyle(p.accent)
            }
        }
        .card()
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    imageData = ImageTools.jpeg(data: data)
                }
            }
        }
    }

    // MARK: しまう

    private var saveForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(L("Tips、スレッド、備忘録をそのまま貼り付け…", "Paste a tip, a thread, or a note to self…"))
                        .foregroundStyle(p.muted.opacity(0.7))
                        .padding(.top, 8)
                        .padding(.leading, 5)
                }
                TextEditor(text: $text)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 96)
                    .foregroundStyle(p.text)
            }
            if showURL {
                TextField(L("出典 URL（任意）", "Source URL (optional)"), text: $url)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(p.surface2))
            }
            if let imageData, let ui = UIImage(data: imageData) {
                HStack(spacing: 10) {
                    Image(uiImage: ui).resizable().scaledToFill().frame(width: 54, height: 54).clipShape(RoundedRectangle(cornerRadius: 8))
                    Text(L("スクショから文字を読み取って保存します", "Text will be read from the screenshot"))
                        .font(.footnote).foregroundStyle(p.muted)
                    Spacer()
                    Button(L("外す", "Remove")) { self.imageData = nil; photo = nil }.font(.footnote)
                }
            }
            HStack(spacing: 4) {
                micButton { text = $0 }
                PhotosPicker(selection: $photo, matching: .images) {
                    Image(systemName: "photo").frame(width: 40, height: 40)
                }
                .accessibilityLabel(L("スクショを添付", "Attach screenshot"))
                Button { showURL.toggle() } label: {
                    Image(systemName: "link").frame(width: 40, height: 40)
                }
                .accessibilityLabel(L("出典 URL", "Source URL"))
                Spacer()
                Button(L("しまう", "Save"), action: save).buttonStyle(PrimaryButtonStyle())
            }
            .foregroundStyle(p.muted)
        }
    }

    private func save() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty || imageData != nil else {
            onToast(L("テキストを書くか、スクショを付けてください。", "Write something or attach a screenshot first."))
            return
        }
        if speech.isRecording { speech.stop() }
        let note = librarian.save(text: t, url: url, image: imageData)
        text = ""
        url = ""
        showURL = false
        imageData = nil
        photo = nil
        focused = false
        onToast(librarian.hasKey
            ? L("しまいました。AI が整理しています…", "Saved. Claude is filing it…")
            : L("「\(note.category)」にしまいました。", "Saved to \(note.category)."))
        Task { await librarian.file(note.id) }
    }

    // MARK: ひきだす

    private var recallForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                TextField(L("これから何をする？何が知りたい？", "What are you about to do?"), text: $query)
                    .submitLabel(.search)
                    .onSubmit { recall(query) }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(p.surface2))
                micButton { query = $0 }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(suggestions, id: \.self) { s in
                        Button(s) { recall(s) }
                            .font(.footnote)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundStyle(p.text)
                            .background(Capsule().stroke(p.line, lineWidth: 1))
                    }
                }
            }
            HStack {
                Spacer()
                Button {
                    recall(query)
                } label: {
                    if searching { ProgressView().tint(p.accentText) } else { Text(L("ひきだす", "Recall")) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(searching)
            }
        }
    }

    private func recall(_ q: String) {
        let q = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !searching else { return }
        if speech.isRecording { speech.stop() }
        query = q
        searching = true
        Task {
            let r = await librarian.recall(q)
            searching = false
            onRecall(r)
        }
    }

    private func micButton(update: @escaping (String) -> Void) -> some View {
        Button {
            speech.toggle(base: mode == .save ? text : "", update: update)
        } label: {
            Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic")
                .foregroundStyle(speech.isRecording ? p.accent : p.muted)
                .frame(width: 40, height: 40)
        }
        .accessibilityLabel(speech.isRecording ? L("録音を止める", "Stop dictation") : L("声で入力", "Dictate"))
    }
}
#endif

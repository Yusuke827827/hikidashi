// 画面上部の入力欄。「しまう」でメモを保存し、「ひきだす」で問いかけに合うメモを探す。

#if os(iOS)
import HikidashiKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

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
    /// 添付したファイル（PDF・テキストなど）
    @State private var attachment: (data: Data, name: String)?
    @State private var importingFile = false
    @State private var scanning = false
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
        .fileImporter(isPresented: $importingFile, allowedContentTypes: [.pdf, .plainText, .text, .image, .commaSeparatedText, .json]) { result in
            guard case let .success(url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return }
            guard data.count <= 20_000_000 else {
                onToast(L("ファイルが大きすぎます（20MB まで）。", "That file is too large (20 MB max)."))
                return
            }
            if TextExtractor.kind(ofExtension: url.pathExtension) == .image {
                imageData = ImageTools.jpeg(data: data)
            } else {
                attachment = (data: data, name: url.lastPathComponent)
            }
        }
        .fullScreenCover(isPresented: $scanning) {
            DocumentScanner { pdf in
                scanning = false
                if let pdf {
                    attachment = (data: pdf, name: L("スキャン", "Scan") + " " + Heuristics.dayFormatter.string(from: Date()) + ".pdf")
                }
            }
            .ignoresSafeArea()
        }
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
                    Text(L("画像の文字を読み取って整理します", "Text in the image will be read and filed"))
                        .font(.footnote).foregroundStyle(p.muted)
                    Spacer()
                    Button(L("外す", "Remove")) { self.imageData = nil; photo = nil }.font(.footnote)
                }
            }
            if let a = attachment {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text").font(.title2).frame(width: 54, height: 54)
                        .background(RoundedRectangle(cornerRadius: 8).fill(p.surface2))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.name).font(.footnote.weight(.semibold)).foregroundStyle(p.text).lineLimit(1)
                        Text(L("ファイルの文字を読み取って整理します", "Text in the file will be read and filed"))
                            .font(.caption).foregroundStyle(p.muted)
                    }
                    Spacer()
                    Button(L("外す", "Remove")) { attachment = nil }.font(.footnote)
                }
            }
            HStack(spacing: 4) {
                micButton { text = $0 }
                PhotosPicker(selection: $photo, matching: .images) {
                    Image(systemName: "photo").frame(width: 40, height: 40)
                }
                .accessibilityLabel(L("写真・スクショを添付", "Attach a photo or screenshot"))
                Button { importingFile = true } label: {
                    Image(systemName: "paperclip").frame(width: 40, height: 40)
                }
                .accessibilityLabel(L("ファイルを添付", "Attach a file"))
                if DocumentScanner.isAvailable {
                    Button { scanning = true } label: {
                        Image(systemName: "doc.viewfinder").frame(width: 40, height: 40)
                    }
                    .accessibilityLabel(L("書類をスキャン", "Scan a document"))
                }
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
        guard !t.isEmpty || imageData != nil || attachment != nil else {
            onToast(L("テキストを書くか、写真やファイルを付けてください。", "Write something or attach a photo or file first."))
            return
        }
        if speech.isRecording { speech.stop() }
        let note = librarian.save(text: t, url: url, image: imageData, file: attachment)
        text = ""
        url = ""
        showURL = false
        imageData = nil
        attachment = nil
        photo = nil
        focused = false
        onToast(librarian.hasAI
            ? L("しまいました。AI が整理しています…", "Saved. AI is filing it…")
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

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
    /// アラームの言葉に合うメモを開く
    var onOpen: (Note) -> Void = { _ in }
    /// 変わったら「しまう」の欄にカーソルを置く（コントロールセンターから開いたとき）
    var focusTrigger = 0

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
    /// メモ風にまとめた結果を、しまう前に確かめる
    @AppStorage("memoPreview") private var memoPreview = true
    @State private var memoDraft: MemoDraft?
    @State private var condensing = false
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
            keywordAlarmBanner

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
        .sheet(item: $memoDraft) { draft in
            MemoPreviewSheet(draft: draft) { text, original in
                memoDraft = nil
                commit(text: text, original: original)
            } onCancel: {
                memoDraft = nil
            }
            .environment(\.palette, p)
            .tint(p.accent)
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
        .onChange(of: focusTrigger) { _, _ in
            mode = .save
            focused = true
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

    // MARK: 言葉のアラーム

    /// 入力中の文に、アラームの言葉が入っていたら知らせる
    @ViewBuilder private var keywordAlarmBanner: some View {
        let hits = Heuristics.keywordAlarms(librarian.store.notes, text: mode == .save ? text : query).prefix(3)
        if !hits.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label(L("この言葉で知らせるメモ", "Notes for this word"), systemImage: "bell.badge")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(p.accent)
                ForEach(Array(hits)) { n in
                    Button { onOpen(n) } label: {
                        HStack {
                            Text(n.title).font(.subheadline).foregroundStyle(p.text).lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(p.muted)
                        }
                    }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(p.accentSoft))
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
            if librarian.hasAI {
                Toggle(isOn: Binding(get: { librarian.memoMode }, set: { librarian.memoMode = $0 })) {
                    Label(L("長い文はメモ風にまとめる", "Condense long text into a memo"), systemImage: "list.bullet.rectangle")
                        .font(.footnote)
                        .foregroundStyle(p.muted)
                }
                .tint(p.accent)
                .controlSize(.mini)
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
                Button(action: save) {
                    if condensing { ProgressView().tint(p.accentText) } else { Text(L("しまう", "Save")) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(condensing)
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
        // メモ風モードで、しまう前に確かめる設定なら、先にまとめて見せる
        if librarian.memoMode, memoPreview, librarian.hasAI, Librarian.worthMemo(t), imageData == nil, attachment == nil {
            condensing = true
            focused = false
            Task {
                let c = await librarian.condense(t)
                condensing = false
                if let c {
                    memoDraft = MemoDraft(original: t, text: c)
                } else {
                    onToast(L("まとめられなかったので、そのまましまいました。", "Couldn't condense it, so it was saved as is."))
                    commit(text: t, original: nil)
                }
            }
            return
        }
        commit(text: t, original: nil)
    }

    /// 保存する。original があれば、メモ風に整えた後の文として保存する
    private func commit(text t: String, original: String?) {
        let note = librarian.save(text: t, url: url, image: imageData, file: attachment, original: original)
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
struct MemoDraft: Identifiable {
    let id = UUID()
    let original: String
    var text: String
}

/// AI がまとめたメモを確かめて、直してからしまう
struct MemoPreviewSheet: View {
    @State var draft: MemoDraft
    var onSave: (_ text: String, _ original: String) -> Void
    var onCancel: () -> Void

    @Environment(\.palette) private var p
    @State private var showOriginal = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $draft.text)
                        .frame(minHeight: 220)
                } header: {
                    Text(L("AI がまとめたメモ（直せます）", "AI's memo (you can edit it)"))
                }
                Section {
                    DisclosureGroup(isExpanded: $showOriginal) {
                        Text(draft.original).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                    } label: {
                        Text(L("元の文", "Original text"))
                    }
                    Button(L("元の文のまましまう", "Save the original as is")) {
                        // 同じ文を original に入れて、整理のときにまとめ直さないようにする
                        onSave(draft.original, draft.original)
                    }
                }
            }
            .navigationTitle(L("しまう前に確認", "Check before saving"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("キャンセル", "Cancel"), action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("これでしまう", "Save")) { onSave(draft.text.trimmingCharacters(in: .whitespacesAndNewlines), draft.original) }
                        .bold()
                        .disabled(draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
#endif

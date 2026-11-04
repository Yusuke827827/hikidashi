// 手順モード・やることボード・片づけ・QR コードの読み取り・次にやることの提案・シリーズ。

#if os(iOS)
import HikidashiKit
import SwiftUI
import VisionKit

// MARK: 手順モード

/// レシピや手順を 1 つずつ大きく出す。「次」「戻る」と言えば進む（料理中でも手がふさがらない）
struct StepsView: View {
    let note: Note
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var p
    @State private var index = 0
    @State private var listening = false
    @State private var speech = SpeechInput()
    @State private var heard = 0
    @AppStorage("stepsSpeak") private var speak = true

    private var steps: [String] { Heuristics.steps(note.text) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ProgressView(value: Double(index + 1), total: Double(max(steps.count, 1))).tint(p.accent)
                Text(L("手順 \(index + 1) / \(steps.count)", "Step \(index + 1) of \(steps.count)"))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(p.muted)
                ScrollView {
                    Text(steps.indices.contains(index) ? steps[index] : "")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(p.text)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .accessibilityAddTraits(.isHeader)
                }
                HStack(spacing: 16) {
                    Button { go(-1) } label: {
                        Label(L("戻る", "Back"), systemImage: "chevron.left").frame(maxWidth: .infinity, minHeight: 60)
                    }
                    .buttonStyle(.bordered)
                    .disabled(index == 0)
                    Button { go(1) } label: {
                        Label(index + 1 >= steps.count ? L("おわり", "Done") : L("次へ", "Next"), systemImage: "chevron.right")
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .font(.title3.weight(.semibold))
                Button {
                    listening.toggle()
                    if listening { startListening() } else { speech.stop() }
                } label: {
                    Label(listening ? L("声で操作中（「次」「戻る」）", "Listening (say “next” or “back”)") : L("声で進める", "Control by voice"),
                          systemImage: listening ? "waveform" : "mic")
                }
                .foregroundStyle(listening ? p.accent : p.muted)
            }
            .padding(20)
            .background(p.bg.ignoresSafeArea())
            .navigationTitle(note.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { speak.toggle(); if !speak { Speaker.shared.stop() } } label: {
                        Image(systemName: speak ? "speaker.wave.2.fill" : "speaker.slash")
                    }
                    .accessibilityLabel(speak ? L("読み上げ: オン", "Read aloud: on") : L("読み上げ: オフ", "Read aloud: off"))
                }
                ToolbarItem(placement: .confirmationAction) { Button(L("閉じる", "Done")) { close() } }
            }
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true
                read()
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
                speech.stop()
                Speaker.shared.stop()
            }
        }
    }

    private func go(_ d: Int) {
        if d > 0, index + 1 >= steps.count { close(); return }
        index = min(max(0, index + d), max(steps.count - 1, 0))
        read()
    }

    private func read() {
        guard speak, steps.indices.contains(index) else { return }
        Speaker.shared.speak(steps[index])
    }

    private func close() {
        speech.stop()
        Speaker.shared.stop()
        dismiss()
    }

    /// 話した言葉の中の「次」「戻る」の回数が増えたら進める
    private func startListening() {
        heard = 0
        speech.toggle(base: "") { said in
            let parts = said.components(separatedBy: CharacterSet(charactersIn: " 、。,."))
            let commands = parts.map(Heuristics.stepCommand).filter { $0 != 0 }
            if commands.count > heard {
                for c in commands[heard...] { go(c) }
                heard = commands.count
            }
        }
    }
}

// MARK: やることボード

struct BoardSheet: View {
    let store: NoteStore
    var onOpen: (Note) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var p
    @State private var column: BoardColumn = .today

    var body: some View {
        let board = Heuristics.board(store.notes)
        NavigationStack {
            VStack(spacing: 12) {
                Picker("", selection: $column) {
                    ForEach(BoardColumn.allCases, id: \.self) { c in Text("\(c.title) \(board[c]?.count ?? 0)").tag(c) }
                }
                .pickerStyle(.segmented)
                ScrollView {
                    LazyVStack(spacing: 10) {
                        let list = board[column] ?? []
                        if list.isEmpty {
                            Text(L("ここには何もありません。メモの「…」から「やることボードへ」で入れられます。", "Nothing here. Add notes from … → To-do board."))
                                .font(.subheadline).foregroundStyle(p.muted).padding(.top, 30)
                        }
                        ForEach(list) { n in row(n) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(p.bg.ignoresSafeArea())
            .navigationTitle(L("やることボード", "To-do board"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("閉じる", "Done")) { dismiss() } } }
        }
    }

    private func row(_ n: Note) -> some View {
        let items = Heuristics.checkItems(n.text)
        return HStack(alignment: .top, spacing: 10) {
            Button { if column != .done { move(n, .done) } else { move(n, .today) } } label: {
                Image(systemName: column == .done ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(column == .done ? p.accent : p.muted)
            }
            .accessibilityLabel(column == .done ? L("済みを戻す", "Mark not done") : L("済みにする", "Mark done"))
            VStack(alignment: .leading, spacing: 4) {
                Button { dismiss(); onOpen(n) } label: {
                    Text(n.title).font(.headline).foregroundStyle(p.text).multilineTextAlignment(.leading)
                }
                if !items.isEmpty {
                    Text(L("チェック \(items.filter(\.done).count)/\(items.count)", "Checked \(items.filter(\.done).count)/\(items.count)"))
                        .font(.caption).foregroundStyle(p.muted)
                }
                if let r = n.remindAt { Label(r, systemImage: "calendar").font(.caption).foregroundStyle(p.muted) }
            }
            Spacer()
            Menu {
                ForEach(BoardColumn.allCases.filter { $0 != column }, id: \.self) { c in
                    Button(L("「\(c.title)」へ", "Move to \(c.title)")) { move(n, c) }
                }
                Button(L("ボードから外す", "Remove from board"), role: .destructive) {
                    store.update(n.id) { $0.board = nil; $0.plannedDay = nil }
                }
            } label: {
                Image(systemName: "arrow.left.arrow.right").frame(width: 36, height: 36)
            }
            .foregroundStyle(p.muted)
            .accessibilityLabel(L("列を動かす", "Move"))
        }
        .card(padding: 12)
    }

    private func move(_ n: Note, _ c: BoardColumn) {
        withAnimation {
            store.update(n.id) { x in
                x.board = c.rawValue
                if c == .today { x.plannedDay = Heuristics.dayFormatter.string(from: Date()) }
            }
        }
    }
}

// MARK: 使っていないメモの片づけ

struct TidySheet: View {
    let store: NoteStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var p
    @State private var notes: [Note] = []

    var body: some View {
        NavigationStack {
            List {
                if notes.isEmpty {
                    Text(L("片づけるメモはありません。", "Nothing to tidy.")).foregroundStyle(.secondary)
                }
                ForEach(notes) { n in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(n.title).font(.headline)
                        Text((n.lastSeen ?? n.modifiedAt).formatted(date: .abbreviated, time: .omitted) + L(" から見ていません", " since last seen"))
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button(L("残す", "Keep")) { act(n) { $0.checkedAt = Date() } }
                            Button(L("しまい込む", "Archive")) { act(n) { $0.archived = true } }
                            Button(L("消す", "Delete"), role: .destructive) { store.remove(n.id); notes.removeAll { $0.id == n.id } }
                        }
                        .buttonStyle(.bordered)
                        .font(.footnote)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(L("使っていないメモの片づけ", "Tidy unused notes"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("閉じる", "Done")) { dismiss() } }
                if notes.count > 1 {
                    ToolbarItem(placement: .bottomBar) {
                        Button(L("全部しまい込む", "Archive all")) {
                            for n in notes { store.update(n.id) { $0.archived = true } }
                            notes = []
                        }
                    }
                }
            }
            .onAppear {
                notes = Heuristics.unused(store.notes)
                UserDefaults.standard.set(Date(), forKey: "tidyShown")
            }
        }
    }

    private func act(_ n: Note, _ f: (inout Note) -> Void) {
        store.update(n.id, f)
        withAnimation { notes.removeAll { $0.id == n.id } }
    }
}

// MARK: QR コード・バーコード

/// カメラで QR コード・バーコードを読む（対応していない端末では写真から読む）
struct CodeScannerSheet: View {
    var onFound: (ScannedCode) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    ScannerRepresentable { raw in
                        dismiss()
                        onFound(Heuristics.describeCode(raw))
                    }
                    .ignoresSafeArea()
                } else {
                    ContentUnavailableView(L("この端末ではカメラで読めません", "Scanning isn't available here"), systemImage: "qrcode.viewfinder",
                                           description: Text(L("カメラの使用を許可しているか確かめてください。写真に写ったコードは、写真を選ぶと読み取ります。",
                                                               "Check camera access. Codes in photos are read when you pick the photo.")))
                }
            }
            .navigationTitle(L("QR・バーコードを読む", "Scan a code"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("やめる", "Cancel")) { dismiss() } } }
        }
    }
}

struct ScannerRepresentable: UIViewControllerRepresentable {
    var onFound: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode()], qualityLevel: .balanced, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (String) -> Void
        var done = false
        init(onFound: @escaping (String) -> Void) { self.onFound = onFound }

        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in addedItems {
                if case let .barcode(b) = item, let s = b.payloadStringValue, !s.isEmpty {
                    done = true
                    scanner.stopScanning()
                    onFound(s)
                    return
                }
            }
        }
    }
}

// MARK: 次にやることの提案

struct NextCard: View {
    let librarian: Librarian
    var onOpen: (Note) -> Void
    @Environment(\.palette) private var p
    @State private var outcome: RecallOutcome?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(L("次にやること", "Up next"), systemImage: "lightbulb").font(.subheadline.weight(.bold)).foregroundStyle(p.text)
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                else {
                    Button(outcome == nil ? L("提案を見る", "Suggest") : L("もう一度", "Again")) {
                        Task {
                            busy = true
                            outcome = await librarian.suggestNext()
                            busy = false
                        }
                    }
                    .font(.footnote.weight(.semibold))
                }
            }
            if let o = outcome {
                Text(o.answer).font(.subheadline).foregroundStyle(p.text).fixedSize(horizontal: false, vertical: true)
                ForEach(o.noteIDs.prefix(5).compactMap { librarian.store.note($0) }) { n in
                    Button { onOpen(n) } label: {
                        HStack {
                            Text(n.title).font(.footnote).foregroundStyle(p.accent).lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(p.muted)
                        }
                        .frame(minHeight: 30)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text(L("期限が近いもの・やり残し・季節に合うものから、今週やっておくと良さそうなことを選びます。", "Picks what's worth doing this week from due dates, unfinished items and the season."))
                    .font(.footnote).foregroundStyle(p.muted)
            }
        }
        .card()
    }
}

// MARK: シリーズ

/// 続きもののメモを前後に移る
struct SeriesNav: View {
    let note: Note
    let notes: [Note]
    var onJump: (Note) -> Void
    @Environment(\.palette) private var p

    var body: some View {
        let s = Heuristics.series(of: note, in: notes)
        if let i = s.firstIndex(where: { $0.id == note.id }) {
            HStack(spacing: 8) {
                Image(systemName: "books.vertical").foregroundStyle(p.muted)
                Text(L("シリーズ \(i + 1) / \(s.count)", "Series \(i + 1) of \(s.count)")).font(.footnote).foregroundStyle(p.muted)
                Spacer()
                if i > 0 { Button(L("← 前", "← Prev")) { onJump(s[i - 1]) }.font(.footnote) }
                if i + 1 < s.count { Button(L("次 →", "Next →")) { onJump(s[i + 1]) }.font(.footnote) }
            }
            .tint(p.accent)
        }
    }
}
#endif

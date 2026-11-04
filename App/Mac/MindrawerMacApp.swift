// Mac のメニューバーから、すぐしまう・探す。仕事中にコピーした文を、その場でしまえる。
// メモの整理と保存は iPhone 版と同じ HikidashiKit。ほかの端末とは「同期コード」でそろえる。

import AppKit
import HikidashiKit
import SwiftUI

@main
struct MindrawerMacApp: App {
    @State private var librarian = Librarian(store: NoteStore())

    var body: some Scene {
        MenuBarExtra("Mindrawer", systemImage: "tray.and.arrow.down") {
            MenuPanel(librarian: librarian)
                .frame(width: 380)
        }
        .menuBarExtraStyle(.window)

        Settings {
            MacSettings(librarian: librarian).frame(width: 420)
        }
    }
}

/// 中継サーバーの URL（Info.plist の MindrawerServerURL）
enum MacServer {
    static var url: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "MindrawerServerURL") as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
    }
}

struct MenuPanel: View {
    let librarian: Librarian
    @State private var text = ""
    @State private var query = ""
    @State private var message: String?
    @State private var opened: String?
    @FocusState private var focused: Bool

    private var store: NoteStore { librarian.store }

    private var shown: [Note] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let pool = store.notes.filter { !$0.example }
        return Array((q.isEmpty ? pool : pool.filter { store.haystack($0).contains(q) }).prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Mindrawer").font(.headline)
                Spacer()
                if let m = message { Text(m).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            TextEditor(text: $text)
                .font(.body)
                .frame(height: 76)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
                .focused($focused)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Tips やメモを貼り付け…").foregroundStyle(.tertiary).padding(.horizontal, 11).padding(.vertical, 6).allowsHitTesting(false)
                    }
                }
            HStack {
                Button("クリップボードからしまう") { saveClipboard() }
                    .help("コピーした文やリンクを、そのまましまいます")
                Spacer()
                Button("しまう") { save(text) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Divider()
            TextField("探す", text: $query)
                .textFieldStyle(.roundedBorder)
            ForEach(shown) { n in row(n) }
            if shown.isEmpty {
                Text(query.isEmpty ? "まだメモがありません。" : "見つかりませんでした。").font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                if SyncSettings.code != nil {
                    Button("同期") { Task { await sync(manual: true) } }
                }
                SettingsLink { Text("設定…") }
                Spacer()
                Button("終了") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .padding(14)
        .onAppear { focused = true }
        .task { await sync(manual: false) }
    }

    private func row(_ n: Note) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                opened = opened == n.id ? nil : n.id
            } label: {
                HStack {
                    Text(n.title).lineLimit(1)
                    Spacer()
                    Text(n.category).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if opened == n.id {
                Text(n.isLocked ? "秘密のメモは iPhone で開いてください。" : n.text)
                    .font(.callout).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(12)
                HStack {
                    Button("本文をコピー") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(n.text, forType: .string)
                        message = "コピーしました"
                    }
                    .disabled(n.isLocked)
                    if let u = n.url.flatMap(URL.init(string:)) { Link("出典を開く", destination: u) }
                }
                .font(.caption)
            }
        }
    }

    private func saveClipboard() {
        let s = NSPasteboard.general.string(forType: .string) ?? ""
        guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { message = "クリップボードに文がありません"; return }
        save(s)
    }

    private func save(_ raw: String) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let url = t.range(of: #"https?://[^\s)\]>"']+"#, options: .regularExpression).map { String(t[$0]) }
        let n = librarian.save(text: url == t ? "" : t, url: url, image: nil)
        text = ""
        message = "「\(n.title)」をしまいました"
        Task {
            await librarian.file(n.id)
            await sync(manual: false)
        }
    }

    private func sync(manual: Bool) async {
        guard SyncSettings.code != nil else { return }
        do {
            let c = try await librarian.sync(serverURL: MacServer.url)
            if manual || c > 0 { message = c > 0 ? "\(c) 件そろえました" : "同期しました" }
        } catch {
            if manual { message = MacServer.url == nil ? "中継サーバーが未設定です" : "同期できませんでした" }
        }
    }
}

struct MacSettings: View {
    let librarian: Librarian
    @State private var code = SyncSettings.code ?? ""
    @State private var key = ""
    @State private var hasKey = APIKeyStore.load() != nil
    @State private var note = ""

    var body: some View {
        Form {
            Section("ほかの端末と同期") {
                TextField("同期コード", text: $code)
                HStack {
                    Button("新しく作る") { code = SyncCode.make() }
                    Button("保存して同期") {
                        SyncSettings.code = SyncCode.isValid(code) ? code.uppercased() : nil
                        Task {
                            do { note = "同期しました（\(try await librarian.sync(serverURL: MacServer.url)) 件）" }
                            catch { note = "同期できませんでした" }
                        }
                    }
                    .disabled(!SyncCode.isValid(code))
                }
                Text("iPhone・Web 版の設定に出る同期コードを入れると、メモがそろいます。中身は暗号にしてから送ります。").font(.caption).foregroundStyle(.secondary)
            }
            Section("Claude（任意）") {
                if hasKey {
                    Button("API キーを削除") { APIKeyStore.delete(); hasKey = false }
                } else {
                    SecureField("sk-ant-…", text: $key)
                    Button("保存") { hasKey = APIKeyStore.save(key); key = "" }.disabled(key.isEmpty)
                }
                Text("キーが無くても、キーワードで整理と検索ができます。").font(.caption).foregroundStyle(.secondary)
            }
            if !note.isEmpty { Text(note).font(.caption) }
        }
        .formStyle(.grouped)
        .padding()
    }
}

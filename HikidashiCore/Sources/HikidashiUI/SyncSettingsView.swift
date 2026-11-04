// 端末どうしの同期の設定（iPhone・iPad・Mac・Web 版で、同じ同期コードを入れるとメモがそろう）。

#if os(iOS)
import HikidashiKit
import SwiftUI

struct SyncSection: View {
    let librarian: Librarian
    @Binding var message: String?
    @State private var code = SyncSettings.code
    @State private var input = ""
    @State private var busy = false

    var body: some View {
        Section {
            if let c = code {
                HStack {
                    Text(c).font(.body.monospaced()).textSelection(.enabled)
                    Spacer()
                    Button { UIPasteboard.general.string = c; message = L("同期コードをコピーしました。", "Copied the sync code.") } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .accessibilityLabel(L("コピー", "Copy"))
                }
                Button {
                    Task { await run() }
                } label: {
                    HStack {
                        Label(L("今すぐ同期", "Sync now"), systemImage: "arrow.triangle.2.circlepath")
                        if busy { Spacer(); ProgressView() }
                    }
                }
                .disabled(busy)
                if let last = SyncSettings.lastSynced {
                    Text(L("最後に同期: ", "Last synced: ") + last.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                }
                Button(L("この端末の同期をやめる", "Stop syncing on this device"), role: .destructive) {
                    SyncSettings.code = nil
                    code = nil
                }
            } else {
                Button {
                    SyncSettings.code = SyncCode.make()
                    code = SyncSettings.code
                    Task { await run() }
                } label: { Label(L("同期を始める（新しいコードを作る）", "Start syncing (new code)"), systemImage: "plus.circle") }
                HStack {
                    TextField(L("ほかの端末の同期コード", "Sync code from another device"), text: $input)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button(L("つなぐ", "Join")) {
                        SyncSettings.code = input.trimmingCharacters(in: .whitespaces).uppercased()
                        code = SyncSettings.code
                        input = ""
                        Task { await run() }
                    }
                    .disabled(!SyncCode.isValid(input))
                }
            }
        } header: {
            Text(L("ほかの端末と同期", "Sync with your other devices"))
        } footer: {
            Text(L("iPhone・iPad・Mac・Web 版で同じ同期コードを入れると、メモがそろいます。中身はこの端末で同期コードから作った鍵で暗号にしてから送るので、中継サーバーでも読めません。コードは人に教えないでください。写真やファイルの中身は送りません。",
                   "Enter the same sync code on your iPhone, iPad, Mac and the web version to keep notes in step. Notes are encrypted on this device with a key made from the code, so even the relay server can't read them. Keep the code private. Photos and files stay on each device."))
        }
    }

    private func run() async {
        busy = true
        defer { busy = false }
        do {
            let n = try await librarian.sync(serverURL: Subscription.serverURL)
            message = n > 0 ? L("同期しました（\(n) 件）。", "Synced (\(n) changes).") : L("同期しました。", "Synced.")
        } catch SyncError.noServer {
            message = L("同期には中継サーバーが必要です（まだ設定されていません）。", "Syncing needs the relay server, which isn't set up yet.")
        } catch SyncError.badCode {
            message = L("同期コードが正しくありません。", "That sync code isn't valid.")
        } catch {
            message = L("同期できませんでした。電波のよいところでもう一度試してください。", "Couldn't sync. Try again with a better connection.")
        }
    }
}
#endif

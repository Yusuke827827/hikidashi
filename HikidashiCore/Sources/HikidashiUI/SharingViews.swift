// 共有フォルダの画面: 共有コードを送る、共有コードで参加する。

#if os(iOS)
import HikidashiKit
import SwiftUI

enum ShareLinks {
    /// Web 版の場所（GitHub Pages）
    static let web = "https://yusuke827827.github.io/hikidashi/"

    static func invitation(folder: String, code: String) -> String {
        L("Mindrawer の共有フォルダ「\(folder)」に参加してください。\n\niPhone: mindrawer://join?c=\(code)\nWeb: \(web)#join=\(code)\n\n共有コード: \(code)",
          "Join my Mindrawer shared folder \"\(folder)\".\n\niPhone: mindrawer://join?c=\(code)\nWeb: \(web)#join=\(code)\n\nShare code: \(code)")
    }
}

/// フォルダを共有して、共有コードを送る
struct ShareFolderSheet: View {
    let folder: String
    let librarian: Librarian

    @Environment(\.dismiss) private var dismiss
    @State private var code: String?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let code {
                        Text(code).font(.footnote.monospaced()).textSelection(.enabled)
                        ShareLink(item: ShareLinks.invitation(folder: folder, code: code)) {
                            Label(L("共有コードを送る", "Send the share code"), systemImage: "square.and.arrow.up")
                        }
                        Button { UIPasteboard.general.string = code } label: { Label(L("コピー", "Copy"), systemImage: "doc.on.doc") }
                    } else if let error {
                        Text(error).foregroundStyle(.red)
                    } else {
                        ProgressView()
                    }
                } footer: {
                    Text(L("共有コードを知っている人は、このフォルダのメモを見たり、足したり、直したりできます。写真・ファイル・場所・復習はこの端末だけに残ります。共有をやめたいときは、フォルダの管理で左にスワイプしてください。",
                           "Anyone with the share code can read, add and edit notes in this folder. Photos, files, places and reviews stay on this device. To stop sharing, swipe left in Manage folders."))
                }
            }
            .navigationTitle(L("「\(folder)」を共有", "Share \"\(folder)\""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("完了", "Done")) { dismiss() } } }
            .task {
                do { code = try await librarian.shareFolder(folder, server: Subscription.serverURL?.absoluteString) }
                catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
            }
        }
        .presentationDetents([.medium])
    }
}

/// 共有コードで、ほかの人のフォルダに参加する
struct JoinShareSheet: View {
    let librarian: Librarian
    var initial = ""
    var onJoined: (String) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("共有コード（MD1-…）またはリンク", "Share code (MD1-…) or link"), text: $code, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        busy = true
                        Task {
                            do {
                                let name = try await librarian.joinShare(code)
                                onJoined(name)
                                dismiss()
                            } catch {
                                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                            }
                            busy = false
                        }
                    } label: {
                        if busy { ProgressView() } else { Text(L("参加する", "Join")) }
                    }
                    .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                } footer: {
                    Text(L("送られてきた共有コードを貼り付けると、そのフォルダがこの端末にもでき、メモが一緒に使えるようになります。",
                           "Paste the share code you received. The folder appears on this device and stays in sync."))
                }
            }
            .navigationTitle(L("共有フォルダに参加", "Join a shared folder"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("キャンセル", "Cancel")) { dismiss() } } }
            .onAppear { if code.isEmpty { code = initial } }
        }
        .presentationDetents([.medium])
    }
}
#endif

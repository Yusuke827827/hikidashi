// 設定。Claude の API キー、壁紙、書き出し・読み込み、共有シートの使い方。

#if os(iOS)
import HikidashiKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let librarian: Librarian
    @Binding var wallpaperRaw: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var p
    @Environment(\.colorScheme) private var scheme
    @State private var key = ""
    @State private var hasKey = APIKeyStore.load() != nil
    @State private var message: String?
    @State private var importing = false
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if hasKey {
                        Label(L("API キーを設定済み", "API key saved"), systemImage: "checkmark.seal")
                        Button(L("API キーを削除", "Remove API key"), role: .destructive) {
                            APIKeyStore.delete()
                            hasKey = false
                        }
                    } else {
                        SecureField("sk-ant-…", text: $key)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button(L("保存", "Save")) {
                            hasKey = APIKeyStore.save(key) && APIKeyStore.load() != nil
                            key = ""
                            if hasKey { Task { await librarian.fileAll() } }
                        }
                        .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Link(L("API キーを取得する（Anthropic Console）", "Get an API key (Anthropic Console)"),
                         destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                } header: {
                    Text("Claude")
                } footer: {
                    Text(L("キーはこの端末のキーチェーンにだけ保存されます。整理と取り出しのたびに、あなたの Anthropic アカウントに少額の利用料がかかります。キーが無くても、簡易の整理とキーワード検索で使えます。",
                           "The key stays in this device's keychain. Each filing or recall is billed to your Anthropic account. Without a key, Mindrawer uses basic filing and keyword search."))
                }

                if Subscription.isAvailable { plusSection }

                Section(L("壁紙", "Wallpaper")) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 12)], spacing: 14) {
                        ForEach(Wallpaper.allCases) { w in
                            Button {
                                wallpaperRaw = w.rawValue
                            } label: {
                                VStack(spacing: 6) {
                                    WallpaperBackground(wallpaper: w, palette: Palette.make(w, scheme: w.scheme ?? scheme))
                                        .frame(height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(wallpaperRaw == w.rawValue ? p.accent : Color.secondary.opacity(0.3),
                                                                                         lineWidth: wallpaperRaw == w.rawValue ? 3 : 1))
                                    Text(w.label).font(.caption).foregroundStyle(.primary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    if let exportURL {
                        ShareLink(item: exportURL) { Label(L("書き出す（JSON）", "Export (JSON)"), systemImage: "square.and.arrow.up") }
                    }
                    Button { importing = true } label: { Label(L("読み込む（JSON）", "Import (JSON)"), systemImage: "square.and.arrow.down") }
                    Button { librarian.addExamples(); message = L("見本を 3 件入れました。", "Added 3 examples.") } label: {
                        Label(L("見本を入れる", "Add examples"), systemImage: "text.badge.plus")
                    }
                    if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                } header: {
                    Text(L("データ", "Data"))
                } footer: {
                    Text(L("Web 版（claude.ai）の Mindrawer で書き出したファイルも読み込めます。書き出したファイルは Web 版にも読み込めます。",
                           "Files exported from the web version can be imported here, and vice versa."))
                }

                Section(L("共有シートから保存する", "Save from the share sheet")) {
                    Text(L("X・Safari・写真などで共有ボタンを押し、「Mindrawer」を選ぶと保存できます。出てこないときは、共有シートの一番右の「その他」から追加してください。保存したものは、次にアプリを開いたときに整理されます。",
                           "Tap Share in X, Safari, Photos and more, then pick Mindrawer. If it isn't listed, add it from More at the end of the app row. Shared items are filed the next time you open the app."))
                        .font(.footnote)
                }
            }
            .navigationTitle(L("設定", "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("完了", "Done")) { dismiss() } }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                guard case let .success(url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let n = try librarian.store.importData(Data(contentsOf: url))
                    message = L("\(n) 件を読み込みました。", "Imported \(n) notes.")
                } catch {
                    message = L("Mindrawer の書き出しファイルではないようです。", "That file isn't a Mindrawer export.")
                }
            }
            .task { exportURL = writeExport() }
        }
    }

    // MARK: Mindrawer Plus

    private var plusSection: some View {
        let sub = Subscription.shared
        return Section {
            if sub.isActive {
                Label(L("購読中", "Subscribed"), systemImage: "checkmark.seal.fill")
                if let e = sub.expires {
                    Text(L("次の更新日: ", "Renews: ") + e.formatted(date: .abbreviated, time: .omitted))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Link(L("購読を管理する", "Manage subscription"), destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
            } else {
                Button {
                    Task { await sub.purchase() }
                } label: {
                    HStack {
                        Text(L("購読する", "Subscribe"))
                        Spacer()
                        if sub.purchasing { ProgressView() } else if let p = sub.product { Text(p.displayPrice + L(" / 月", " / month")).foregroundStyle(.secondary) }
                    }
                }
                .disabled(sub.purchasing)
            }
            Button(L("購入を復元", "Restore purchases")) { Task { await sub.restore() } }
            if let m = sub.message { Text(m).font(.footnote).foregroundStyle(.secondary) }
        } header: {
            Text("Mindrawer Plus")
        } footer: {
            Text(L("API キーを用意しなくても、AI での整理と取り出しが使えます。メモは整理のために Mindrawer のサーバーを経由して Claude に送られますが、サーバーには保存されません。自分の API キーを設定している場合は、そちらが優先されます。",
                   "Use AI filing and recall without your own API key. Notes pass through Mindrawer's server to Claude for filing and are not stored there. If you set your own API key, it's used instead."))
        }
    }

    private func writeExport() -> URL? {
        guard let data = try? librarian.store.exportData() else { return nil }
        let name = "hikidashi-\(Heuristics.dayFormatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        return (try? data.write(to: url, options: .atomic)) != nil ? url : nil
    }
}
#endif

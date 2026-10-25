// 設定。使い方、Mindrawer Plus、Claude の API キー、壁紙、書き出し・読み込み、共有シートの使い方。

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
    @State private var calendarOn = EventReminders.isOn

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        HowToView()
                    } label: {
                        Label(L("使い方", "How to use"), systemImage: "questionmark.circle")
                    }
                }

                if Subscription.isAvailable { plusSection }

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
                    Text(Subscription.isAvailable ? L("自分の API キーを使う", "Use your own API key") : "Claude")
                } footer: {
                    Text(L("キーはこの端末のキーチェーンにだけ保存されます。整理と取り出しのたびに、あなたの Anthropic アカウントに少額の利用料がかかります。キーが無くても、iPhone の中の AI（Apple Intelligence 対応機種）か、簡易の整理とキーワード検索で使えます。",
                           "The key stays in this device's keychain. Each filing or recall is billed to your Anthropic account. Without a key, Mindrawer uses on-device AI (Apple Intelligence devices) or basic filing and keyword search."))
                }


                Section {
                    Toggle(isOn: Binding(get: { calendarOn }, set: { on in
                        Task {
                            if on {
                                calendarOn = await EventReminders.enable()
                                if !calendarOn { message = L("予定へのアクセスが許可されませんでした。iPhone の「設定」→「プライバシー」→「カレンダー」で許可できます。", "Calendar access wasn't allowed. You can allow it in Settings → Privacy → Calendars.") }
                                await EventReminders.sync(librarian.store.notes)
                            } else {
                                await EventReminders.disable()
                                calendarOn = false
                            }
                        }
                    })) {
                        Label(L("予定の前にメモを知らせる", "Hints before events"), systemImage: "calendar.badge.clock")
                    }
                } header: {
                    Text(L("通知", "Notifications"))
                } footer: {
                    Text(L("カレンダーの 3 日先までの予定を見て、関係するメモがあれば前の日の夜 8 時に知らせます（例: 予定「出張」→ 荷造りのメモ）。予定はこの iPhone の中で読むだけで、どこにも送りません。",
                           "Looks at your calendar for the next 3 days and, when a note fits an event, reminds you at 8 PM the day before (e.g. a trip → packing tips). Events are read on this iPhone only and never sent anywhere."))
                }

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
                if librarian.aiKind == .onDevice {
                    Label(L("今は iPhone の中の AI で整理しています（無料）", "Filing with on-device AI now (free)"), systemImage: "iphone")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Label(L("高性能な AI（Claude）が整理", "Claude, a top AI model, files your notes"), systemImage: "folder.badge.gearshape")
                    Label(L("問いかけに合うメモを賢く取り出す", "Smarter recall for what you're doing"), systemImage: "sparkles")
                    Label(L("スクショの文字も読み取る", "Reads text in screenshots"), systemImage: "text.viewfinder")
                }
                .font(.subheadline)
                .padding(.vertical, 4)
                Button {
                    Task { await sub.purchase() }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sub.trialText ?? L("購読する", "Subscribe")).fontWeight(.semibold)
                            if sub.trialText != nil, let price = sub.priceText {
                                Text(L("その後 \(price)", "then \(price)")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if sub.purchasing { ProgressView() } else if sub.trialText == nil, let price = sub.priceText { Text(price).foregroundStyle(.secondary) }
                    }
                }
                .disabled(sub.purchasing)
            }
            Button(L("購入を復元", "Restore purchases")) { Task { await sub.restore() } }
            if let m = sub.message { Text(m).font(.footnote).foregroundStyle(.secondary) }
        } header: {
            Text("Mindrawer Plus")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("API キーを用意しなくても、AI での整理と取り出しが使えます。メモは整理のために Mindrawer のサーバーを経由して Claude に送られますが、サーバーには保存されません。自分の API キーを設定している場合は、そちらが優先されます。",
                       "Use AI filing and recall without your own API key. Notes pass through Mindrawer's server to Claude for filing and are not stored there. If you set your own API key, it's used instead."))
                Text(L("Mindrawer Plus は 1 か月ごとに自動で更新される購読です。料金は Apple ID に請求され、期間が終わる 24 時間前までに解約しない限り自動で更新されます。解約は App Store の「サブスクリプション」からいつでもできます。無料のお試しの残りは、購読すると無くなります。",
                       "Mindrawer Plus is an auto-renewing monthly subscription. Payment is charged to your Apple ID and renews automatically unless canceled at least 24 hours before the end of the period. Cancel anytime in App Store subscriptions. Any unused part of a free trial ends when you subscribe."))
                HStack(spacing: 16) {
                    Link(L("利用規約", "Terms of Use"), destination: Subscription.termsURL)
                    Link(L("プライバシーポリシー", "Privacy Policy"), destination: Subscription.privacyURL)
                }
            }
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

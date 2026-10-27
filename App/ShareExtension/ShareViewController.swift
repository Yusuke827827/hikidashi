// 共有シートの拡張機能。X・Safari・写真などで「共有 → Mindrawer」を選ぶと開く。
// 共有された文・URL・画像を受け取り、ひとこと書き足して「しまう」と、App Group の Inbox/ に置く。
// AI での整理は、次にアプリ本体を開いたときに行う（拡張機能はメモリと時間の制限が厳しいため）。

import HikidashiKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let model = SharedPayload()
        let view = ShareView(model: model, onSave: { [weak self] comment in self?.save(model, comment: comment) },
                             onCancel: { [weak self] in self?.cancel() })
        let host = UIHostingController(rootView: view)
        addChild(host)
        host.view.frame = self.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(host.view)
        host.didMove(toParent: self)
        Task { await model.load(from: extensionContext?.inputItems as? [NSExtensionItem] ?? []) }
    }

    private func save(_ model: SharedPayload, comment: String) {
        do {
            try Inbox.put(text: model.text, url: model.url, comment: comment, image: model.image,
                          file: model.file.map { (data: $0.data, name: $0.name) })
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            model.error = L("保存できませんでした。", "Couldn't save.")
        }
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: "app.hikidashi.share", code: NSUserCancelledError))
    }
}

/// 共有されたものの中身
@MainActor
final class SharedPayload: ObservableObject {
    @Published var text = ""
    @Published var url: String?
    @Published var image: Data?
    /// PDF などのファイル（文字は次にアプリを開いたときに取り出す）
    @Published var file: (data: Data, name: String)?
    @Published var loading = true
    @Published var error: String?

    func load(from items: [NSExtensionItem]) async {
        var texts: [String] = []
        for item in items {
            if let s = item.attributedContentText?.string, !s.isEmpty { texts.append(s) }
            for provider in item.attachments ?? [] {
                if file == nil, image == nil, let type = Self.fileType(provider) {
                    file = await Self.loadFile(provider, type: type)
                    if file != nil { continue }
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier), url == nil {
                    if let u = await Self.loadURL(provider), !u.isFileURL { url = u.absoluteString }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier), image == nil {
                    image = await Self.loadImage(provider)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let s = await Self.loadText(provider), !s.isEmpty { texts.append(s) }
                }
            }
        }
        // 同じ文が 2 回入ることがあるので重ねない。URL だけの文は URL 欄に回す
        var seen = Set<String>()
        text = texts.filter { t in
            let k = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if k.isEmpty || seen.contains(k) { return false }
            seen.insert(k)
            if url == nil, let u = URL(string: k), u.scheme?.hasPrefix("http") == true, !k.contains(" ") { url = k; return false }
            return k != url
        }.joined(separator: "\n\n")
        loading = false
    }

    /// 画像・URL・文以外のファイル（PDF、テキストファイルなど）の種類
    nonisolated static func fileType(_ p: NSItemProvider) -> UTType? {
        if p.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) { return .pdf }
        if p.hasItemConformingToTypeIdentifier(UTType.image.identifier) { return nil }
        for id in p.registeredTypeIdentifiers {
            guard let t = UTType(id), t.conforms(to: .data) else { continue }
            if t.conforms(to: .plainText) && !t.conforms(to: .fileURL) { continue }
            if t.conforms(to: .text) || t.conforms(to: .commaSeparatedText) || t.conforms(to: .json) { return t }
        }
        return nil
    }

    nonisolated static func loadFile(_ p: NSItemProvider, type: UTType) async -> (data: Data, name: String)? {
        await withCheckedContinuation { c in
            _ = p.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                guard let url, let data = try? Data(contentsOf: url), data.count <= 20_000_000 else {
                    c.resume(returning: nil)
                    return
                }
                let base = p.suggestedName ?? url.deletingPathExtension().lastPathComponent
                let ext = url.pathExtension.isEmpty ? (type.preferredFilenameExtension ?? "") : url.pathExtension
                let name = (base as NSString).pathExtension.isEmpty && !ext.isEmpty ? base + "." + ext : base
                c.resume(returning: (data: data, name: name))
            }
        }
    }

    nonisolated static func loadURL(_ p: NSItemProvider) async -> URL? {
        await withCheckedContinuation { c in
            p.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                c.resume(returning: item as? URL ?? (item as? String).flatMap(URL.init(string:)))
            }
        }
    }

    nonisolated static func loadText(_ p: NSItemProvider) async -> String? {
        await withCheckedContinuation { c in
            p.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                c.resume(returning: item as? String ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) })
            }
        }
    }

    nonisolated static func loadImage(_ p: NSItemProvider) async -> Data? {
        let raw: Data? = await withCheckedContinuation { c in
            p.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    c.resume(returning: try? Data(contentsOf: url))
                } else if let data = item as? Data {
                    c.resume(returning: data)
                } else if let img = item as? UIImage {
                    c.resume(returning: img.jpegData(compressionQuality: 0.9))
                } else {
                    c.resume(returning: nil)
                }
            }
        }
        return raw.flatMap { ImageTools.jpeg(data: $0) }
    }
}

struct ShareView: View {
    @ObservedObject var model: SharedPayload
    var onSave: (String) -> Void
    var onCancel: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var comment = ""
    @FocusState private var focused: Bool

    // Flowa と同じ紙色と朱色
    private var accent: Color { scheme == .dark ? Color(red: 0.878, green: 0.455, blue: 0.353) : Color(red: 0.784, green: 0.333, blue: 0.239) }
    private var bg: Color { scheme == .dark ? Color(red: 0.09, green: 0.094, blue: 0.106) : Color(red: 0.965, green: 0.961, blue: 0.949) }
    private var surface: Color { scheme == .dark ? Color(red: 0.129, green: 0.133, blue: 0.149) : .white }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if model.loading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        if let data = model.image, let ui = UIImage(data: data) {
                            Image(uiImage: ui).resizable().scaledToFit().frame(maxHeight: 220).clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        if let f = model.file {
                            Label(f.name, systemImage: "doc.text").font(.callout)
                        }
                        if !model.text.isEmpty {
                            Text(model.text).font(.callout).lineLimit(8)
                        }
                        if let url = model.url {
                            Text(url).font(.footnote).foregroundStyle(accent).lineLimit(2)
                        }
                        if model.text.isEmpty && model.url == nil && model.image == nil && model.file == nil {
                            Text(L("共有された内容を読み取れませんでした。下にメモを書いて保存できます。", "Couldn't read what was shared. You can still write a note below."))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    TextField(L("ひとこと（任意）：なぜ残すか、いつ使いたいか", "Add a note (optional): why, or when you'll need it"), text: $comment, axis: .vertical)
                        .focused($focused)
                        .lineLimit(2...5)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(bg))
                    Text(L("X の投稿は、本文が共有されないことがあります。そのときはスクショを共有すると、AI が文字を読み取ります。", "Posts on X sometimes share only a link. Share a screenshot instead and the text will be read from it."))
                        .font(.caption).foregroundStyle(.secondary)
                    if let e = model.error { Text(e).font(.footnote).foregroundStyle(accent) }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 14).fill(surface))
                .padding(16)
            }
            .background(bg)
            .navigationTitle(L("Mindrawer にしまう", "Save to Mindrawer"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("キャンセル", "Cancel"), action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("しまう", "Save")) { onSave(comment) }
                        .bold()
                        .disabled(model.loading || (model.text.isEmpty && model.url == nil && model.image == nil && model.file == nil && comment.isEmpty))
                }
            }
        }
        .tint(accent)
    }
}

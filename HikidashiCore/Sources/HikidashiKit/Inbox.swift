// 共有シートの受け口。拡張機能は共有されたものを Inbox/ に 1 件 1 ファイルで置くだけにし、
// 整理（AI 呼び出し）はアプリ本体が開いたときに行う。拡張機能はメモリと時間の制限が厳しいため。

import Foundation

public struct InboxItem: Codable, Sendable, Equatable {
    public var id: String
    /// 共有された文（X の投稿文、選択したテキストなど）
    public var text: String
    public var url: String?
    /// 共有シートで自分が書き足したひとこと
    public var comment: String
    /// 一緒に置いた画像（Inbox/ 内のファイル名）
    public var imageFile: String?
    public var createdAt: Date

    public init(id: String = UUID().uuidString, text: String, url: String? = nil, comment: String = "", imageFile: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.url = url
        self.comment = comment
        self.imageFile = imageFile
        self.createdAt = createdAt
    }

    /// メモの本文にする文（ひとことを先頭に置く）
    public var noteText: String {
        [comment, text].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

public enum Inbox {
    public static func directory(in root: URL) -> URL {
        let url = root.appendingPathComponent("Inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 共有されたものを置く（拡張機能から呼ぶ）
    @discardableResult
    public static func put(text: String, url: String?, comment: String, image: Data?, root: URL = SharedContainer.root) throws -> InboxItem {
        let dir = directory(in: root)
        var item = InboxItem(text: text, url: url, comment: comment)
        if let image {
            let name = item.id + ".jpg"
            try image.write(to: dir.appendingPathComponent(name), options: .atomic)
            item.imageFile = name
        }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .millisecondsSince1970
        // 書き終わってから .json の名前にする（途中の読みかけを拾わないため）
        let tmp = dir.appendingPathComponent(item.id + ".tmp")
        try enc.encode(item).write(to: tmp, options: .atomic)
        try FileManager.default.moveItem(at: tmp, to: dir.appendingPathComponent(item.id + ".json"))
        return item
    }

    /// 置かれたものを古い順に取り出して消す。画像は Images/ に移す（アプリ本体から呼ぶ）
    public static func drain(root: URL = SharedContainer.root) -> [InboxItem] {
        let dir = directory(in: root)
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .millisecondsSince1970
        var items: [InboxItem] = []
        for name in names where name.hasSuffix(".json") {
            let file = dir.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: file), var item = try? dec.decode(InboxItem.self, from: data) else {
                try? fm.removeItem(at: file)
                continue
            }
            if let img = item.imageFile {
                let from = dir.appendingPathComponent(img)
                let to = SharedContainer.images(in: root).appendingPathComponent(img)
                try? fm.removeItem(at: to)
                if (try? fm.moveItem(at: from, to: to)) == nil { item.imageFile = nil }
            }
            try? fm.removeItem(at: file)
            items.append(item)
        }
        return items.sorted { $0.createdAt < $1.createdAt }
    }
}

// 共有フォルダ（家族や友だちと 1 つのフォルダを一緒に使う）。中継サーバーの /share を使う。
// 共有コード（サーバー・id・鍵をまとめた文字列）を送れば、受け取った人も同じフォルダを使える。
// 開いたときと変えたときに、そのフォルダのメモを送り、ほかの人の変更を受け取る（メモごとに新しい方を残す）。
// 写真・ファイル・場所・復習などその端末だけのものは送らない。規則は Web 版と同じ。

import Foundation

public struct SharedFolder: Codable, Sendable, Equatable {
    /// この端末でのフォルダ名
    public var folder: String
    public var server: String
    public var id: String
    public var key: String
    /// 前に同期したときにあったメモの id（ここから消えたものは、この端末で消したもの）
    public var lastIDs: [String]
    public var syncedAt: Date?

    public var code: String { ShareCode.encode(server: server, id: id, key: key) }
}

public enum ShareCode {
    static let prefix = "MD1-"

    public static func encode(server: String, id: String, key: String) -> String {
        let raw = Data("\(server)|\(id)|\(key)".utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return prefix + raw
    }

    /// 共有コードか、それを含むリンク（…#join=… や mindrawer://join?c=…）から取り出す
    public static func decode(_ s: String) -> (server: String, id: String, key: String)? {
        guard let r = s.range(of: prefix + "[A-Za-z0-9_-]+", options: .regularExpression) else { return nil }
        var b = String(s[r].dropFirst(prefix.count)).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        guard let d = Data(base64Encoded: b), let t = String(data: d, encoding: .utf8) else { return nil }
        let p = t.components(separatedBy: "|")
        guard p.count == 3, p[0].hasPrefix("https://") || p[0].hasPrefix("http://localhost"), !p[1].isEmpty, !p[2].isEmpty else { return nil }
        return (p[0], p[1], p[2])
    }
}

public enum ShareError: LocalizedError {
    case noServer, badCode, notFound, forbidden, server(Int)
    public var errorDescription: String? {
        switch self {
        case .noServer: return L("共有には中継サーバーが必要です（まだ設定されていません）。", "Sharing needs the relay server, which isn't set up yet.")
        case .badCode: return L("共有コードが読み取れませんでした。", "That share code couldn't be read.")
        case .notFound: return L("共有フォルダが見つかりませんでした。", "That shared folder wasn't found.")
        case .forbidden: return L("共有コードが正しくありません。", "The share code isn't valid.")
        case .server(let c): return L("共有のサーバーでエラーが起きました（\(c)）。", "The sharing server returned an error (\(c)).")
        }
    }
}

/// サーバーから届いた共有フォルダの中身
public struct ShareRemote: Sendable {
    public var name: String
    public var notes: [Note]
    public var deleted: [String]
}

public struct ShareClient: Sendable {
    public var session: URLSession = .shared
    public init() {}

    static func encodeNotes(_ notes: [Note]) throws -> Any {
        let data = try JSONEncoder().encode(notes)
        return try JSONSerialization.jsonObject(with: data)
    }

    func send(_ method: String, _ url: URL, key: String?, body: [String: Any]?) async throws -> ShareRemote {
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        if let key { req.setValue(key, forHTTPHeaderField: "x-share-key") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, res) = try await session.data(for: req)
        let code = (res as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200: break
        case 403: throw ShareError.forbidden
        case 404: throw ShareError.notFound
        default: throw ShareError.server(code)
        }
        return try Self.decodeRemote(data)
    }

    static func decodeRemote(_ data: Data) throws -> ShareRemote {
        struct Raw: Decodable { var name: String; var notes: [Note]; var deleted: [String]?; var id: String?; var key: String? }
        let r = try JSONDecoder().decode(Raw.self, from: data)
        return ShareRemote(name: r.name, notes: r.notes, deleted: r.deleted ?? [])
    }

    /// 新しく共有する。返すのは id と鍵
    public func create(server: String, name: String, notes: [Note]) async throws -> (id: String, key: String, remote: ShareRemote) {
        guard let url = URL(string: server + "/share") else { throw ShareError.noServer }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["name": name, "notes": try Self.encodeNotes(notes)])
        let (data, res) = try await session.data(for: req)
        let code = (res as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ShareError.server(code) }
        let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let id = j?["id"] as? String, let key = j?["key"] as? String else { throw ShareError.server(code) }
        return (id, key, try Self.decodeRemote(data))
    }

    public func pull(_ sf: SharedFolder) async throws -> ShareRemote {
        guard let url = URL(string: sf.server + "/share/" + sf.id) else { throw ShareError.badCode }
        return try await send("GET", url, key: sf.key, body: nil)
    }

    public func push(_ sf: SharedFolder, notes: [Note], deleted: [String]) async throws -> ShareRemote {
        guard let url = URL(string: sf.server + "/share/" + sf.id) else { throw ShareError.badCode }
        return try await send("PUT", url, key: sf.key, body: ["notes": try Self.encodeNotes(notes), "deleted": deleted])
    }
}

public enum SharedFolders {
    static let key = "sharedFolders"

    public static func load(_ d: UserDefaults = .standard) -> [SharedFolder] {
        d.data(forKey: key).flatMap { try? JSONDecoder().decode([SharedFolder].self, from: $0) } ?? []
    }

    public static func save(_ all: [SharedFolder], _ d: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(all) { d.set(data, forKey: key) }
    }

    /// 送る前に、その端末だけのものを外す
    static func outgoing(_ n: Note) -> Note {
        var x = n
        x.imageFile = nil
        x.file = nil
        x.place = nil
        x.review = nil
        x.plannedDay = nil
        x.folderChosen = nil
        x.checkedAt = nil
        x.linkBroken = nil
        if x.updatedAt == nil { x.updatedAt = x.createdAt }
        return x
    }

    /// 届いたメモに、この端末だけのもの（写真・場所・復習など）を残して、フォルダ名をそろえる
    static func incoming(_ r: Note, local: Note?, folder: String) -> Note {
        var n = r
        n.category = folder
        n.filed = true
        n.enriched = true
        if let l = local {
            n.imageFile = l.imageFile
            n.file = l.file
            n.place = l.place
            n.review = l.review
            n.plannedDay = l.plannedDay
            n.lastSeen = l.lastSeen
            n.checkedAt = l.checkedAt
        }
        return n
    }
}

extension Librarian {
    /// 共有しているフォルダ
    public var sharedFolders: [SharedFolder] { SharedFolders.load() }

    public func isShared(_ folder: String) -> Bool { SharedFolders.load().contains { $0.folder == folder } }

    /// フォルダを共有して、共有コードを返す
    public func shareFolder(_ folder: String, server: String?) async throws -> String {
        if let sf = SharedFolders.load().first(where: { $0.folder == folder }) { return sf.code }
        guard let server, !server.isEmpty else { throw ShareError.noServer }
        let notes = store.notes.filter { $0.category == folder }.map(SharedFolders.outgoing)
        let r = try await ShareClient().create(server: server, name: folder, notes: notes)
        let sf = SharedFolder(folder: folder, server: server, id: r.id, key: r.key, lastIDs: notes.map(\.id), syncedAt: Date())
        SharedFolders.save(SharedFolders.load() + [sf])
        return sf.code
    }

    /// 共有コードで、ほかの人のフォルダに入る。フォルダ名を返す
    @discardableResult
    public func joinShare(_ code: String) async throws -> String {
        guard let c = ShareCode.decode(code) else { throw ShareError.badCode }
        if let have = SharedFolders.load().first(where: { $0.id == c.id }) { return have.folder }
        let probe = SharedFolder(folder: "", server: c.server, id: c.id, key: c.key, lastIDs: [], syncedAt: nil)
        let remote = try await ShareClient().pull(probe)
        // 同じ名前の自分のフォルダがあれば、混ざらないように名前を変える
        var name = remote.name
        if store.folders.contains(name), !store.notes.filter({ $0.category == name }).isEmpty { name += L("（共有）", " (shared)") }
        var sf = probe
        sf.folder = name
        apply(remote, to: &sf)
        SharedFolders.save(SharedFolders.load() + [sf])
        return name
    }

    /// 共有をやめる（この端末のメモはそのまま残す）
    public func leaveShare(_ folder: String) {
        SharedFolders.save(SharedFolders.load().filter { $0.folder != folder })
    }

    /// 共有しているフォルダを、すべて送って受け取る
    public func syncShares() async {
        var all = SharedFolders.load()
        guard !all.isEmpty else { return }
        for i in all.indices {
            var sf = all[i]
            let mine = store.notes.filter { $0.category == sf.folder }
            let ids = Set(mine.map(\.id))
            let deleted = sf.lastIDs.filter { !ids.contains($0) }
            do {
                let remote = try await ShareClient().push(sf, notes: mine.map(SharedFolders.outgoing), deleted: deleted)
                apply(remote, to: &sf)
                all[i] = sf
            } catch {
                continue
            }
        }
        // 同期のあいだに増えた・やめた共有を消さないように、読み直してから書く
        var latest = SharedFolders.load()
        for sf in all { if let j = latest.firstIndex(where: { $0.id == sf.id }) { latest[j] = sf } }
        SharedFolders.save(latest)
    }

    private func apply(_ remote: ShareRemote, to sf: inout SharedFolder) {
        let incoming = remote.notes.map { SharedFolders.incoming($0, local: store.note($0.id), folder: sf.folder) }
        store.applyRemote(saved: incoming, deleted: remote.deleted.filter { id in store.note(id)?.category == sf.folder })
        if !store.folders.contains(sf.folder) { _ = store.createFolder(sf.folder) }
        sf.lastIDs = store.notes.filter { $0.category == sf.folder }.map(\.id)
        sf.syncedAt = Date()
    }
}

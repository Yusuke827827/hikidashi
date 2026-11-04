// 自分の端末どうしの同期（iPhone・iPad・Mac・Web 版）。中継サーバーの /sync を使う。
// 同期コード（例: K7QF-2M9X-…）を同じにした端末どうしでメモがそろう。
// 中身は端末の中で同期コードから作った鍵（AES-GCM）で暗号にしてから送るので、サーバーは暗号文しか持たない。
// 規則は Web 版と同じ:
//   ・id = SHA-256("mindrawer-sync:" + コード) の 16 進
//   ・鍵 = SHA-256("mindrawer-sync-key:" + コード)
//   ・中身 = base64(nonce 12 バイト + 暗号文 + タグ 16 バイト) の JSON { v: 1, notes: [...], deleted: { id: ミリ秒 } }
//   ・同じメモは、最後に変えた日時が新しい方を残す。消したメモは「消した日時」を残して、ほかの端末からも消す
// 写真・ファイルの中身は送らない（その端末にだけ残る）。

import CryptoKit
import Foundation

public enum SyncCode {
    static let alphabet = Array("ABCDEFGHJKMNPQRSTVWXYZ23456789")

    /// 新しい同期コード（25 文字、5 文字ずつ区切る）
    public static func make() -> String {
        var g = SystemRandomNumberGenerator()
        let chars = (0..<25).map { _ in alphabet[Int(g.next(upperBound: UInt32(alphabet.count)))] }
        return stride(from: 0, to: 25, by: 5).map { String(chars[$0..<$0 + 5]) }.joined(separator: "-")
    }

    /// 打ち間違いを許す形に（大文字・記号なし）
    public static func normalize(_ s: String) -> String {
        s.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    public static func isValid(_ s: String) -> Bool { normalize(s).count >= 20 }

    public static func id(_ code: String) -> String {
        SHA256.hash(data: Data(("mindrawer-sync:" + normalize(code)).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func key(_ code: String) -> SymmetricKey {
        SymmetricKey(data: Data(SHA256.hash(data: Data(("mindrawer-sync-key:" + normalize(code)).utf8))))
    }
}

/// 同期で送る中身
public struct SyncPayload: Codable, Sendable, Equatable {
    public var v = 1
    public var notes: [Note]
    /// 消したメモ（id → 消した日時のミリ秒）
    public var deleted: [String: Double]

    public init(notes: [Note], deleted: [String: Double]) {
        self.notes = notes
        self.deleted = deleted
    }

    public func seal(code: String) throws -> String {
        let json = try JSONEncoder().encode(self)
        guard let box = try AES.GCM.seal(json, using: SyncCode.key(code)).combined else { throw CocoaError(.coderInvalidValue) }
        return box.base64EncodedString()
    }

    public static func open(_ s: String, code: String) throws -> SyncPayload {
        guard let data = Data(base64Encoded: s) else { throw CocoaError(.coderReadCorrupt) }
        let json = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: SyncCode.key(code))
        return try JSONDecoder().decode(SyncPayload.self, from: json)
    }

    /// 両方をまとめる。同じメモは新しい方、消したものは消す（消したあとに直したものは残す）。60 日より前の「消した」記録は捨てる
    public static func merge(local: SyncPayload, remote: SyncPayload, now: Date = Date()) -> SyncPayload {
        var deleted = local.deleted
        for (k, v) in remote.deleted { deleted[k] = max(v, deleted[k] ?? 0) }
        let cutoff = (now.timeIntervalSince1970 - 60 * 86400) * 1000
        deleted = deleted.filter { $0.value >= cutoff }
        var byID: [String: Note] = [:]
        for n in remote.notes { byID[n.id] = n }
        for n in local.notes {
            if let r = byID[n.id], r.modifiedAt > n.modifiedAt { continue }
            byID[n.id] = n
        }
        let notes = byID.values.filter { n in
            guard let d = deleted[n.id] else { return true }
            return n.modifiedAt.timeIntervalSince1970 * 1000 > d
        }
        return SyncPayload(notes: notes.sorted { $0.createdAt > $1.createdAt }, deleted: deleted)
    }

    /// 送る形のメモ（見本は送らない。写真・ファイルの中身はこの端末だけ。秘密のメモは鍵をかけた形）
    public static func outgoing(_ notes: [Note]) -> [Note] {
        notes.filter { !$0.example }.map { n in
            var x = Vault.seal(n)
            x.imageFile = nil
            x.file = nil
            return x
        }
    }

    /// 同じ内容か（並び順・写真の有無は見ない）
    func sameNotes(as other: SyncPayload) -> Bool {
        Dictionary(notes.map { ($0.id, $0.modifiedAt) }, uniquingKeysWith: max) == Dictionary(other.notes.map { ($0.id, $0.modifiedAt) }, uniquingKeysWith: max)
            && deleted == other.deleted
    }
}

/// 同期の設定と、消したメモの記録（この端末）
public enum SyncSettings {
    static let codeKey = "syncCode", verKey = "syncVer", deletedKey = "syncDeleted", lastKey = "syncLast"

    public static var code: String? {
        get { UserDefaults.standard.string(forKey: codeKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: codeKey)
            UserDefaults.standard.set(0, forKey: verKey)
        }
    }

    public static var lastSynced: Date? { UserDefaults.standard.object(forKey: lastKey) as? Date }

    static var deleted: [String: Double] {
        get { (UserDefaults.standard.dictionary(forKey: deletedKey) as? [String: Double]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: deletedKey) }
    }

    /// 消したメモを覚えておく（同期がオンのときだけ）
    public static func noteDeleted(_ ids: [String], at: Date = Date()) {
        guard code != nil, !ids.isEmpty else { return }
        var d = deleted
        for id in ids { d[id] = (at.timeIntervalSince1970 * 1000).rounded() }
        deleted = d
    }
}

public enum SyncError: Error, Equatable { case noServer, badCode, network, server(Int) }

extension NoteStore {
    /// 同期で届いた内容を当てる（写真・ファイルはこの端末のものを残す）
    func applySynced(_ merged: [Note]) {
        let mine = Dictionary(notes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [Note] = []
        for var n in merged {
            n = Vault.open(n)
            if let m = mine[n.id] {
                n.imageFile = m.imageFile
                n.file = m.file
                if m.modifiedAt >= n.modifiedAt { out.append(m); continue }
            }
            out.append(n)
        }
        // 見本のメモは同期しないので、この端末のものを残す
        out += notes.filter(\.example)
        replaceAll(out)
    }
}

extension Librarian {
    /// 同期する。届いた件数（新しく入った・変わった・消えた）を返す
    @discardableResult
    public func sync(serverURL: URL?, fetch: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }) async throws -> Int {
        guard let code = SyncSettings.code, SyncCode.isValid(code) else { throw SyncError.badCode }
        guard let server = serverURL else { throw SyncError.noServer }
        let url = server.appendingPathComponent("sync").appendingPathComponent(SyncCode.id(code))
        for _ in 0..<3 {
            let (data, res) = try await fetch(URLRequest(url: url))
            guard (res as? HTTPURLResponse)?.statusCode == 200 else { throw SyncError.server((res as? HTTPURLResponse)?.statusCode ?? 0) }
            struct Box: Decodable { var ver: Int; var data: String? }
            let box = try JSONDecoder().decode(Box.self, from: data)
            let remote = try box.data.map { try SyncPayload.open($0, code: code) } ?? SyncPayload(notes: [], deleted: [:])
            let before = store.notes.filter { !$0.example }
            let local = SyncPayload(notes: SyncPayload.outgoing(before), deleted: SyncSettings.deleted)
            let merged = SyncPayload.merge(local: local, remote: remote)
            SyncSettings.deleted = merged.deleted
            // この端末に当てる
            let changed = Self.countChanges(before: before, after: merged.notes)
            if changed > 0 { store.applySynced(merged.notes) }
            // サーバーに置く（変わったときだけ）
            if box.data != nil, merged.sameNotes(as: remote) {
                UserDefaults.standard.set(Date(), forKey: SyncSettings.lastKey)
                return changed
            }
            var put = URLRequest(url: url)
            put.httpMethod = "PUT"
            put.setValue("application/json", forHTTPHeaderField: "content-type")
            put.httpBody = try JSONSerialization.data(withJSONObject: ["ver": box.ver, "data": try merged.seal(code: code)])
            let (_, pres) = try await fetch(put)
            let status = (pres as? HTTPURLResponse)?.statusCode ?? 0
            if status == 409 { continue } // ほかの端末が先に置いた。読み直してもう一度
            guard status == 200 else { throw SyncError.server(status) }
            UserDefaults.standard.set(Date(), forKey: SyncSettings.lastKey)
            return changed
        }
        throw SyncError.network
    }

    static func countChanges(before: [Note], after: [Note]) -> Int {
        let a = Dictionary(before.map { ($0.id, $0.modifiedAt) }, uniquingKeysWith: max)
        let b = Dictionary(after.map { ($0.id, $0.modifiedAt) }, uniquingKeysWith: max)
        return b.filter { a[$0.key] == nil || a[$0.key]! < $0.value }.count + a.keys.filter { b[$0] == nil }.count
    }
}

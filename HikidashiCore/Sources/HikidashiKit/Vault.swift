// 秘密のメモの暗号化。保存するファイル（notes.json）には、本文・要約・元の文・履歴を暗号文で書く。
// 鍵はこの端末のキーチェーンに置く（端末の外には出ない）。アプリの中では開いた形で持つ。
// Web 版で鍵をかけたメモ（"p1:"）はその暗証番号でしか開けないので、そのまま残す。

import CryptoKit
import Foundation
import Security

public enum Vault {
    static let prefix = "k1:"

    /// 暗号にする中身
    struct Secret: Codable {
        var text: String
        var summary: String
        var original: String?
        var history: [NoteVersion]?
    }

    /// テストで差し替える鍵
    static var keyOverride: SymmetricKey?
    /// テストの中では、キーチェーンに触らない
    static let testKey: SymmetricKey? = NSClassFromString("XCTestCase") != nil ? SymmetricKey(size: .bits256) : nil

    static let service = "app.mindrawer.vault"

    /// キーチェーンの鍵（無ければ作る）。キーチェーンが使えなければ nil（そのときは暗号にしない）
    static var cached: SymmetricKey?

    static func key() -> SymmetricKey? {
        if let k = keyOverride ?? testKey ?? cached { return k }
        cached = loadOrCreate()
        return cached
    }

    static func loadOrCreate() -> SymmetricKey? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: "notes", kSecReturnData as String: true]
        var out: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let d = out as? Data, d.count == 32 {
            return SymmetricKey(data: d)
        }
        let k = SymmetricKey(size: .bits256)
        let data = k.withUnsafeBytes { Data($0) }
        let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                  kSecAttrAccount as String: "notes", kSecValueData as String: data,
                                  kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess ? k : nil
    }

    /// 保存する形に（秘密のメモだけ、中身を暗号文にする）
    public static func seal(_ n: Note) -> Note {
        guard n.isLocked, let key = key() else { return n }
        // 開けなかった暗号文（Web 版の鍵など）は、そのまま
        if n.text.isEmpty, n.summary.isEmpty, n.sealed != nil { return n }
        let secret = Secret(text: n.text, summary: n.summary, original: n.original, history: n.history)
        guard let json = try? JSONEncoder().encode(secret), let box = try? AES.GCM.seal(json, using: key).combined else { return n }
        var out = n
        out.sealed = prefix + box.base64EncodedString()
        out.text = ""
        out.summary = ""
        out.original = nil
        out.history = nil
        return out
    }

    /// 読み込んだ形を開く（開けなければそのまま）
    public static func open(_ n: Note) -> Note {
        guard let s = n.sealed, s.hasPrefix(prefix), let key = key(),
              let data = Data(base64Encoded: String(s.dropFirst(prefix.count))),
              let box = try? AES.GCM.SealedBox(combined: data),
              let json = try? AES.GCM.open(box, using: key),
              let secret = try? JSONDecoder().decode(Secret.self, from: json) else { return n }
        var out = n
        out.text = secret.text
        out.summary = secret.summary
        out.original = secret.original
        out.history = secret.history
        out.sealed = nil
        return out
    }

    /// この端末では開けない秘密のメモか
    public static func cannotOpen(_ n: Note) -> Bool { n.sealed != nil }
}

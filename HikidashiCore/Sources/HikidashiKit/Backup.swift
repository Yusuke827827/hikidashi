// 自動バックアップ。週に 1 回、メモを書き出しと同じ形の JSON にして、アプリの「書類」フォルダに残す。
// 「ファイル」アプリの「このiPhone内 → Mindrawer → Backups」から見られ、iPhone の iCloud バックアップにも含まれる。画像は含まない。

import Foundation

public enum Backup {
    public static let interval: TimeInterval = 7 * 86400
    /// 残す数
    public static let keep = 8

    public static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Backups", isDirectory: true)
    }

    /// 前回から interval たっていれば書き出す。書き出したファイルを返す
    @MainActor
    @discardableResult
    public static func runIfDue(_ store: NoteStore, last: Date?, now: Date = Date(), dir: URL = directory) -> URL? {
        if let last, now.timeIntervalSince(last) < interval { return nil }
        guard !store.notes.isEmpty else { return nil }
        return try? write(store, now: now, dir: dir)
    }

    @MainActor
    public static func write(_ store: NoteStore, now: Date = Date(), dir: URL = directory) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmm"
        let url = dir.appendingPathComponent("mindrawer-\(f.string(from: now)).json")
        try store.exportData().write(to: url, options: .atomic)
        prune(dir)
        return url
    }

    /// 古いものから消して keep 個にする
    static func prune(_ dir: URL) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        let files = names.filter { $0.hasPrefix("mindrawer-") && $0.hasSuffix(".json") }.sorted()
        for name in files.dropLast(keep) { try? fm.removeItem(at: dir.appendingPathComponent(name)) }
    }

    public static func list(_ dir: URL = directory) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.hasPrefix("mindrawer-") && $0.hasSuffix(".json") }.sorted(by: >).map { dir.appendingPathComponent($0) }
    }
}

// MARK: 外の保存先（iCloud Drive・Google Drive などのフォルダ）

extension Backup {
    static let bookmarkKey = "backupFolderBookmark"

    /// 選んだフォルダを覚える（ファイル App で選んだ場所。端末を変えても、そこにバックアップが残る）
    public static func setExternalFolder(_ url: URL?) {
        guard let url else { UserDefaults.standard.removeObject(forKey: bookmarkKey); return }
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        if let data = try? url.bookmarkData() { UserDefaults.standard.set(data, forKey: bookmarkKey) }
    }

    public static var externalFolder: URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
    }

    /// 外の保存先にも書き出す（選んでいなければ nil）
    @MainActor
    @discardableResult
    public static func writeExternal(_ store: NoteStore, now: Date = Date()) throws -> URL? {
        guard let dir = externalFolder else { return nil }
        let ok = dir.startAccessingSecurityScopedResource()
        defer { if ok { dir.stopAccessingSecurityScopedResource() } }
        let url = try write(store, now: now, dir: dir)
        UserDefaults.standard.set(now, forKey: "lastExternalBackup")
        return url
    }

    public static var lastExternal: Date? { UserDefaults.standard.object(forKey: "lastExternalBackup") as? Date }
}

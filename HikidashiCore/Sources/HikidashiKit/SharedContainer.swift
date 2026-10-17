// アプリ本体と共有シートの拡張機能が一緒に使う保存場所（App Group）。
// App Group の ID は Info.plist の HikidashiAppGroup に書く（project.yml の APP_GROUP から入る）。
// App Group が使えないとき（署名なしのビルド、テスト）はアプリ自身の Application Support を使う。

import Foundation

public enum SharedContainer {
    public static let defaultAppGroup = "group.app.hikidashi"

    public static var appGroup: String {
        (Bundle.main.object(forInfoDictionaryKey: "HikidashiAppGroup") as? String).flatMap { $0.isEmpty ? nil : $0 } ?? defaultAppGroup
    }

    /// 保存フォルダ（notes.json、Inbox/、Images/ を置く）
    public static var root: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Hikidashi", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static func images(in root: URL) -> URL {
        let url = root.appendingPathComponent("Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

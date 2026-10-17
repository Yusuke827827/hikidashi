// 画面の言語。端末の言語が日本語なら日本語、それ以外は英語。
// 文言は L("日本語", "English") の形でその場に書く（翻訳ファイルを分けない）。

import Foundation

public enum AppLanguage: String, Sendable {
    case ja, en

    public static var current: AppLanguage {
        let first = Locale.preferredLanguages.first ?? "en"
        return first.hasPrefix("ja") ? .ja : .en
    }

    /// Claude への指示に書く言語名
    public var promptName: String { self == .ja ? "Japanese" : "English" }

    public var locale: Locale { Locale(identifier: self == .ja ? "ja_JP" : "en_US") }
}

public func L(_ ja: String, _ en: String) -> String {
    AppLanguage.current == .ja ? ja : en
}

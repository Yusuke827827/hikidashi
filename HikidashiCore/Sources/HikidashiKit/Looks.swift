// 見分けやすくするための決まり: フォルダの色と印、本文のハッシュタグ、メモの並べ方。規則は Web 版と同じ。

import Foundation

/// フォルダの色（Heuristics.folderColors の番号）と印（Heuristics.folderIcons の名前）
public struct FolderLook: Sendable, Equatable {
    public var color: Int
    public var icon: String
}

extension Heuristics {
    /// 色（16 進）。Web 版と同じ順
    public static let folderColors = ["c8553d", "d0832b", "b39a24", "5a9a54", "2d8f84", "3c7cc0", "6b62c9", "a058b5", "c4567f", "7d7a73"]
    /// 印の名前（画面側で SF Symbols などに置き換える）
    public static let folderIcons = ["folder", "home", "food", "money", "heart", "laptop", "work", "plane", "cart", "users", "paw", "music", "sparkle", "doc", "target", "bulb", "star"]

    static let topicLooks: [(pattern: String, icon: String, color: Int)] = [
        ("料理|食|food|cook", "food", 1), ("お金|節約|money", "money", 2), ("健康|体|health", "heart", 3), ("PC|ガジェット|tech", "laptop", 5),
        ("仕事|勉強|work|study", "work", 6), ("暮らし|家事|home", "home", 4), ("旅行|おでかけ|travel", "plane", 5), ("買い物|shop", "cart", 0),
        ("家族|子育て|family", "users", 8), ("ペット|pet", "paw", 1), ("趣味|エンタメ|hobb", "music", 7), ("美容|ファッション|beauty", "sparkle", 8),
        ("手続き|書類|paper", "doc", 9), ("習慣|考え方|habit", "target", 4), ("人づきあい|people", "users", 3),
    ]

    /// フォルダの色と印。決めていなければ、話題から（無ければ名前から）決める
    public static func folderLook(_ name: String, info: FolderInfo? = nil) -> FolderLook {
        let hit = topicLooks.first { name.range(of: $0.pattern, options: [.regularExpression, .caseInsensitive]) != nil }
        var h: UInt32 = 0
        for u in name.unicodeScalars { h = h &* 31 &+ u.value }
        let color = info?.color ?? hit?.color ?? Int(h % UInt32(folderColors.count))
        let icon = info?.icon ?? hit?.icon ?? "folder"
        return FolderLook(color: min(max(color, 0), folderColors.count - 1), icon: folderIcons.contains(icon) ? icon : "folder")
    }

    /// 本文の #言葉（全角の ＃ も）
    public static func hashtags(_ text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: "(?:^|[\\s、。（(「])[#＃]([\\p{L}\\p{N}_ー・]{1,30})") else { return [] }
        let ns = text as NSString
        var out: [String] = []
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: m.range(at: 1))
            if !out.contains(tag) { out.append(tag) }
        }
        return out
    }

    /// タグに本文のハッシュタグを足す（重ならないように、12 個まで）
    public static func withHashtags(_ tags: [String], text: String) -> [String] {
        var seen = Set<String>()
        return Array((tags + hashtags(text)).filter { seen.insert($0).inserted }.prefix(12))
    }
}

/// メモの並べ方
public enum NoteSort: String, CaseIterable, Sendable {
    case new, old, updated, long, short, title, helpful, folder

    public var label: String {
        switch self {
        case .new: return L("新しい順", "Newest")
        case .old: return L("古い順", "Oldest")
        case .updated: return L("直した順", "Recently edited")
        case .long: return L("文字が多い順", "Longest")
        case .short: return L("文字が少ない順", "Shortest")
        case .title: return L("タイトル順", "Title")
        case .helpful: return L("役立った順", "Most helpful")
        case .folder: return L("フォルダ別", "By folder")
        }
    }

    public func sorted(_ notes: [Note]) -> [Note] {
        func by(_ a: Note, _ b: Note) -> Bool {
            switch self {
            case .new: return a.createdAt > b.createdAt
            case .old: return a.createdAt < b.createdAt
            case .updated: return a.modifiedAt > b.modifiedAt
            case .long: return a.text.count != b.text.count ? a.text.count > b.text.count : a.createdAt > b.createdAt
            case .short: return a.text.count != b.text.count ? a.text.count < b.text.count : a.createdAt > b.createdAt
            case .title: return a.title.localizedStandardCompare(b.title) == .orderedAscending
            case .helpful: return a.helpful != b.helpful ? a.helpful > b.helpful : a.createdAt > b.createdAt
            case .folder:
                let c = a.category.localizedStandardCompare(b.category)
                return c != .orderedSame ? c == .orderedAscending : a.createdAt > b.createdAt
            }
        }
        let pinFirst = self == .new || self == .updated
        return notes.sorted { a, b in
            if pinFirst, a.pinned != b.pinned { return a.pinned }
            return by(a, b)
        }
    }
}

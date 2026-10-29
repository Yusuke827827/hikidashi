// 一覧の絞り込み（タグ・期間・添付・通知・お気に入り・整理待ち）。

import Foundation

public struct NoteFilter: Equatable, Sendable {
    public enum Period: String, CaseIterable, Sendable {
        case all, week, month, quarter, year
        /// 今からさかのぼる日数（all は制限なし）
        var days: Int? {
            switch self {
            case .all: return nil
            case .week: return 7
            case .month: return 31
            case .quarter: return 92
            case .year: return 366
            }
        }
    }

    public var tags: Set<String> = []
    public var period: Period = .all
    public var withAttachment = false
    public var withNotification = false
    public var favoritesOnly = false
    public var unfiledOnly = false

    public init() {}

    public var isActive: Bool { self != NoteFilter() }

    /// 付いている条件の数（ボタンのバッジ用）
    public var count: Int {
        var n = tags.count
        if period != .all { n += 1 }
        for on in [withAttachment, withNotification, favoritesOnly, unfiledOnly] where on { n += 1 }
        return n
    }

    public func matches(_ n: Note, now: Date = Date()) -> Bool {
        if !tags.isEmpty, tags.isDisjoint(with: n.tags) { return false }
        if let d = period.days, n.createdAt < now.addingTimeInterval(-Double(d) * 86400) { return false }
        if withAttachment, n.imageFile == nil, n.file == nil { return false }
        if withNotification, n.alarm == nil, n.remindAt == nil, n.place == nil { return false }
        if favoritesOnly, !n.pinned { return false }
        if unfiledOnly, n.filed { return false }
        return true
    }

    /// よく使われているタグ（多い順）
    public static func popularTags(_ notes: [Note], limit: Int = 30) -> [String] {
        var count: [String: Int] = [:]
        for n in notes { for t in n.tags { count[t, default: 0] += 1 } }
        return count.keys.sorted { (count[$0]!, $1) > (count[$1]!, $0) }.prefix(limit).map { $0 }
    }
}

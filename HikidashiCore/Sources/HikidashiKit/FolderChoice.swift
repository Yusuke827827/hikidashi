// フォルダの決め方。しまうたびに AI が 3 つの名前を出し、使う人が選ぶ（どれも違えば自分で入力）。
// 選んだ結果は覚えておき、名付けの好み（短い名前・今あるフォルダを選びがち・いつも言い換える名前）を次の提案に生かす。
// おまかせにすると、1 番目の名前で自動で入れ、「その他」の振り分けや似たフォルダのまとめも自動でする。

import Foundation

/// しまうときのフォルダの決め方
public enum FolderMode: String, CaseIterable, Sendable {
    /// 3 つの候補から選ぶ（どれも違えば自分で入力）
    case ask
    /// おまかせ（1 番目の候補で自動で入れる）
    case auto
}

/// 似たフォルダのまとめ方
public enum MergeMode: String, CaseIterable, Sendable {
    /// 「まとめますか？」と聞く
    case suggest
    /// 自動でまとめる
    case auto
    /// 何もしない
    case off
}

/// フォルダの候補
public struct FolderOption: Sendable, Equatable, Hashable {
    public var name: String
    /// 今あるフォルダか（無ければ新しく作る）
    public var exists: Bool
    /// 新しく作る名前のとき、似ている今のフォルダ（「洗濯用品」に対する「洗濯」など）
    public var similar: String?

    public init(name: String, exists: Bool, similar: String? = nil) {
        self.name = name
        self.exists = exists
        self.similar = similar
    }
}

/// 「どのフォルダに入れますか？」の問い（しまった直後に出す）
public struct FolderChoiceRequest: Sendable, Equatable, Identifiable {
    public var id: String { noteID }
    public var noteID: String
    public var title: String
    public var options: [FolderOption]
}

/// 選んだ結果の記録（名付けの好みを覚える）
public struct FolderChoiceRecord: Codable, Sendable, Equatable {
    public var title: String
    public var offered: [String]
    public var chosen: String
    /// 自分で入力した名前か
    public var custom: Bool
    /// 今あるフォルダを選んだか
    public var existing: Bool
    public var at: Date

    public init(title: String, offered: [String], chosen: String, custom: Bool, existing: Bool, at: Date = Date()) {
        self.title = title
        self.offered = offered
        self.chosen = chosen
        self.custom = custom
        self.existing = existing
        self.at = at
    }
}

/// 名付けの好み
public enum NamingHabits {
    static let key = "folderChoices"
    static let limit = 60

    public static func load(_ defaults: UserDefaults = .standard) -> [FolderChoiceRecord] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([FolderChoiceRecord].self, from: data)) ?? []
    }

    public static func record(_ r: FolderChoiceRecord, defaults: UserDefaults = .standard) {
        let all = Array((load(defaults) + [r]).suffix(limit))
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: key) }
    }

    public static func reset(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    /// いつも言い換える名前（1 番目の候補 → 実際に選んだ名前）。2 回以上同じ言い換えをしたものだけ
    public static func renames(_ log: [FolderChoiceRecord]) -> [String: String] {
        var count: [String: [String: Int]] = [:]
        for r in log {
            guard let first = r.offered.first, first != r.chosen else { continue }
            count[first, default: [:]][r.chosen, default: 0] += 1
        }
        var out: [String: String] = [:]
        for (from, tos) in count {
            if let best = tos.max(by: { $0.value < $1.value }), best.value >= 2 { out[from] = best.key }
        }
        return out
    }

    /// 今あるフォルダを選びがちか（記録が少ないうちは nil）
    public static func prefersExisting(_ log: [FolderChoiceRecord]) -> Bool? {
        guard log.count >= 4 else { return nil }
        return Double(log.filter(\.existing).count) / Double(log.count) >= 0.6
    }

    /// AI に渡す、名付けの好みの説明（記録が無ければ空）
    public static func promptHint(_ log: [FolderChoiceRecord]) -> String {
        guard !log.isEmpty else { return "" }
        let recent = log.suffix(12).map { r in
            "- \"\(r.title.prefix(40))\" → chose \"\(r.chosen)\"" + (r.custom ? " (typed it themselves)" : "") + " (offered: \(r.offered.joined(separator: " / ")))"
        }
        var lines = ["The user's recent folder choices (learn their naming style and how specific or broad they like folders):"] + recent
        let custom = log.filter(\.custom).map(\.chosen)
        if !custom.isEmpty {
            let avg = Double(custom.map(\.count).reduce(0, +)) / Double(custom.count)
            lines.append("Names they typed themselves: \(Array(Set(custom)).prefix(10).joined(separator: ", ")) (about \(Int(avg.rounded())) characters long).")
        }
        if let p = prefersExisting(log) {
            lines.append(p ? "They usually put notes into an existing folder." : "They often prefer a new, more specific folder.")
        }
        for (from, to) in renames(log) { lines.append("When \"\(from)\" fits, they call it \"\(to)\".") }
        return lines.joined(separator: "\n")
    }
}

extension Heuristics {
    /// フォルダの候補を 3 つまで作る。AI の候補があれば先に使い、足りない分を言葉の辞書と今までのメモから補う
    public static func folderOptions(text: String, title: String = "", notes: [Note], folders: [String], ai: [String] = [],
                                     log: [FolderChoiceRecord] = [], preferExisting: Bool = true, language: AppLanguage = .current) -> [FolderOption] {
        let other = otherFolder
        let existing = Array(Set(folders + notes.map(\.category))).filter { !$0.isEmpty && !isCatchAll($0) && $0 != other }
        let all = [title, text].joined(separator: "\n")
        var names: [String] = ai
        // 1) 言葉の辞書と今までのフォルダから
        let r = classify(all, notes: notes, folders: folders, language: language)
        names.append(r.folder)
        // 2) 今までのメモと言葉が近いフォルダ
        if let l = learnedFolder(all, profile: profiles(notes)), l.score >= 1 { names.append(l.name) }
        // 3) 辞書で当たった別の分類と、具体的な言葉（「洗剤」など）
        let hits = topicHits(all, language: language)
        names += hits.map(\.name)
        if let word = hits.flatMap(\.words).first(where: { $0.count >= 2 }) { names.insert(word, at: min(names.count, max(1, ai.count))) }
        if let run = keyPhrase(title.isEmpty ? text : title) { names.append(run) }
        // いつも言い換える名前は、言い換えた方にする
        let renames = NamingHabits.renames(log)
        names = names.map { renames[$0] ?? $0 }
        var seen = Set<String>()
        var out: [FolderOption] = []
        var fromAI = 0
        for (i, raw) in names.enumerated() {
            let n = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
            guard !n.isEmpty, !isCatchAll(n), n != other, seen.insert(n.lowercased()).inserted else { continue }
            let exists = existing.contains(n)
            let similar = exists ? nil : existing.filter { nameSimilarity($0, n) >= 0.5 }.max { nameSimilarity($0, n) < nameSimilarity($1, n) }
            out.append(FolderOption(name: n, exists: exists, similar: similar))
            if i < ai.count { fromAI = out.count }
        }
        // 今あるフォルダを選びがちなら、AI の候補のうち今あるものを先頭に（辞書の分け方はもともと今あるフォルダを優先している）
        let likesExisting = NamingHabits.prefersExisting(log) ?? preferExisting
        if likesExisting, let i = out.prefix(fromAI).firstIndex(where: \.exists), i > 0 {
            out.insert(out.remove(at: i), at: 0)
        }
        return Array(out.prefix(3))
    }

    /// 名前が似たフォルダか（「洗濯」と「洗濯用品」など）
    public static func isSimilarFolderName(_ a: String, _ b: String) -> Bool { nameSimilarity(a, b) >= 0.5 }

    /// タイトルから、フォルダ名にできそうな言葉（漢字・カタカナの続き 2〜6 文字）
    static func keyPhrase(_ s: String) -> String? {
        var run = ""
        for ch in s {
            if isKanjiOrKatakana(ch) {
                run.append(ch)
            } else {
                if (2...6).contains(run.count) { return run }
                run = ""
            }
        }
        return (2...6).contains(run.count) ? run : nil
    }
}

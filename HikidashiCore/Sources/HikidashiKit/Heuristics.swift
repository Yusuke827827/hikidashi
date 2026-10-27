// AI を使わないときの整理と検索。API キーが無いときや、通信できないときに使う。
// 規則は Web 版と同じ。

import Foundation

public enum Heuristics {
    static let rulesJa: [(String, String)] = [
        ("料理・食", "料理|レシピ|食|味|調味|野菜|肉|魚|弁当|醤油|炊"),
        ("健康・体", "健康|睡眠|運動|筋トレ|ストレッチ|病院|薬|肩こり|姿勢"),
        ("お金・節約", "お金|節約|ポイント|税|ふるさと|保険|投資|NISA|値下げ|安く|見積"),
        ("PC・ガジェット", "PC|Mac|Windows|iPhone|Android|ショートカット|アプリ|Excel|スクショ|⌘|Ctrl"),
        ("仕事・勉強", "仕事|会議|メール|資料|プレゼン|勉強|英語|面接"),
        ("暮らし・家事", "掃除|洗濯|シミ|収納|片付|家事|ゴミ|引っ越"),
        ("おでかけ・旅行", "旅行|ホテル|新幹線|飛行機|観光|荷造り|空港"),
    ]
    static let rulesEn: [(String, String)] = [
        ("Food & Cooking", "cook|recipe|food|kitchen|meal"),
        ("Health", "sleep|health|exercise|stretch|posture"),
        ("Money", "money|save|budget|tax|price|deal|quote"),
        ("Tech", "mac|windows|iphone|android|shortcut|app|excel|chrome"),
        ("Work & Study", "work|meeting|email|slides|present|study|interview"),
        ("Home", "clean|laundry|stain|storage|move|moving"),
        ("Travel", "travel|trip|hotel|flight|pack"),
    ]

    public static var otherFolder: String { L("その他", "Other") }

    /// フォルダ名だけを推測する
    public static func folder(for text: String, language: AppLanguage = .current) -> String {
        let rules = language == .ja ? rulesJa : rulesEn
        for (name, pattern) in rules where text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return name
        }
        return otherFolder
    }

    /// 本文の 1 文目をタイトルにする
    public static func title(for text: String) -> String {
        let first = text.split(whereSeparator: { "\n。.!?！？".contains($0) }).first.map(String.init) ?? text
        let t = first.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? L("メモ", "Note") : String(t.prefix(48))
    }

    /// 簡易の整理（AI なし）
    public static func file(_ note: inout Note) {
        if note.title.isEmpty { note.title = title(for: note.text.isEmpty ? (note.url ?? "") : note.text) }
        if note.category.isEmpty { note.category = folder(for: note.text) }
    }

    static func words(_ q: String) -> [String] {
        q.lowercased()
            .components(separatedBy: CharacterSet(charactersIn: " \t\n、。,.!?？！「」“”\"'"))
            .filter { $0.count >= 2 }
    }

    /// 問いかけとメモの近さ。完全一致は 3 点、日本語は 2 文字ずつの部分一致を 1 点として数える
    public static func score(_ note: Note, query: String) -> Double {
        let hay = note.haystack
        var s = 0.0
        for w in words(query) {
            if hay.contains(w) {
                s += 3
            } else if w.unicodeScalars.contains(where: { !$0.isASCII }) {
                let chars = Array(w)
                if chars.count >= 2 {
                    for i in 0..<(chars.count - 1) where hay.contains(String(chars[i...i + 1])) { s += 1 }
                }
            }
        }
        return s + Double(note.helpful) * 0.2 + (note.pinned ? 0.5 : 0)
    }

    public static func search(_ notes: [Note], query: String, limit: Int = 8) -> [Note] {
        notes.map { ($0, score($0, query: query)) }
            .filter { $0.1 >= 1 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    /// タグ・使う場面が重なるメモ（関連メモ）
    public static func related(to note: Note, in notes: [Note], limit: Int = 3) -> [Note] {
        let mine = Set((note.tags + note.situations).map { $0.lowercased() })
        return notes.filter { $0.id != note.id }
            .map { other -> (Note, Double) in
                var s = other.category == note.category ? 0.5 : 0
                for x in other.tags + other.situations where mine.contains(x.lowercased()) { s += 1 }
                return (other, s)
            }
            .filter { $0.1 >= 1 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    /// 今日のひとつ。2 日以上前のメモのうち、長く見ていない 7 件から日替わりで選ぶ
    public static func todaysPick(_ notes: [Note], now: Date = Date(), skip: Int = 0) -> Note? {
        let old = notes.filter { now.timeIntervalSince($0.createdAt) > 2 * 86400 }
            .sorted { ($0.lastSeen ?? $0.createdAt) < ($1.lastSeen ?? $1.createdAt) }
        let pool = Array(old.prefix(7))
        guard !pool.isEmpty else { return nil }
        let day = Int(now.timeIntervalSince1970 / 86400)
        return pool[(day + skip) % pool.count]
    }

    /// 3 日前から 14 日後までのリマインド（近い順）
    public static func upcoming(_ notes: [Note], now: Date = Date()) -> [Note] {
        let today = Calendar.current.startOfDay(for: now)
        return notes.compactMap { n -> (Note, Date)? in
            guard let r = n.remindAt, let d = dayFormatter.date(from: r) else { return nil }
            let diff = d.timeIntervalSince(today) / 86400
            return diff >= -3 && diff <= 14 ? (n, d) : nil
        }
        .sorted { $0.1 < $1.1 }
        .map(\.0)
    }

    /// 通知を出すメモと日時（リマインド日の朝 hour 時。過ぎたものは除き、近い順に最大 limit 件）。
    /// iOS が一度に予約できる通知は 64 件までなので、多すぎるときは近いものだけにする
    public static func reminderSchedule(_ notes: [Note], now: Date = Date(), hour: Int = 9, limit: Int = 60) -> [(note: Note, fireAt: Date)] {
        notes.compactMap { n -> (note: Note, fireAt: Date)? in
            guard let r = n.remindAt, let day = dayFormatter.date(from: r),
                  let fire = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day),
                  fire > now
            else { return nil }
            return (n, fire)
        }
        .sorted { $0.fireAt < $1.fireAt }
        .prefix(limit)
        .map { $0 }
    }

    public static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

extension Heuristics {
    /// 場所で知らせるメモ。iOS が見張れる場所は 1 つのアプリで 20 か所までなので、ピン留め・新しいものから limit 件
    public static func placeNotes(_ notes: [Note], limit: Int = 15) -> [Note] {
        notes.filter { $0.place != nil }
            .sorted { a, b in a.pinned != b.pinned ? a.pinned : a.modifiedAt > b.modifiedAt }
            .prefix(limit)
            .map { $0 }
    }
}

/// 「似たフォルダをまとめますか？」の提案
public struct FolderMergeSuggestion: Sendable, Equatable {
    /// まとめられる側（消える）
    public var from: String
    /// まとめる先（メモの多い方）
    public var into: String
    /// 提案を「別のままにする」で消したときの鍵（順序によらない）
    public var key: String { [from, into].sorted().joined(separator: "|") }
}

extension Heuristics {
    /// 名前が似ている（片方がもう片方を含む、または 2 文字ずつの重なりが多い）か、
    /// 中のメモのタグ・使う場面が多く重なるフォルダの組を、似ている順に返す
    public static func folderMergeSuggestions(_ notes: [Note], folders: [String], dismissed: Set<String> = [], limit: Int = 2) -> [FolderMergeSuggestion] {
        let other = otherFolder
        let names = folders.filter { $0 != other && !$0.isEmpty }
        guard names.count >= 2 else { return [] }
        var count: [String: Int] = [:]
        var words: [String: Set<String>] = [:]
        for n in notes {
            count[n.category, default: 0] += 1
            words[n.category, default: []].formUnion((n.tags + n.situations).map { $0.lowercased() })
        }
        var found: [(s: FolderMergeSuggestion, score: Double)] = []
        for i in 0..<names.count {
            for j in (i + 1)..<names.count {
                let a = names[i], b = names[j]
                let score = max(nameSimilarity(a, b), jaccard(words[a] ?? [], words[b] ?? []))
                guard score >= 0.5 else { continue }
                let ca = count[a] ?? 0, cb = count[b] ?? 0
                let s = ca >= cb ? FolderMergeSuggestion(from: b, into: a) : FolderMergeSuggestion(from: a, into: b)
                guard !dismissed.contains(s.key) else { continue }
                found.append((s: s, score: score))
            }
        }
        found.sort { $0.score > $1.score }
        return found.prefix(limit).map { $0.s }
    }

    /// 名前の近さ（0〜1）
    static func nameSimilarity(_ a: String, _ b: String) -> Double {
        let x = a.lowercased(), y = b.lowercased()
        if x == y { return 1 }
        let short = x.count <= y.count ? x : y, long = x.count <= y.count ? y : x
        if short.count >= 2, long.contains(short) { return 0.9 }
        // 「・」や「&」で区切った言葉が共通なら似ている（「お金」と「お金・節約」は上で拾う）
        let sep = CharacterSet(charactersIn: "・&/、, ")
        let wa = Set(x.components(separatedBy: sep).filter { $0.count >= 2 })
        let wb = Set(y.components(separatedBy: sep).filter { $0.count >= 2 })
        if !wa.isDisjoint(with: wb) { return 0.8 }
        return jaccard(bigrams(x), bigrams(y))
    }

    static func bigrams(_ s: String) -> Set<String> {
        let c = Array(s.filter { !$0.isWhitespace })
        guard c.count >= 2 else { return [s] }
        return Set((0..<(c.count - 1)).map { String(c[$0...$0 + 1]) })
    }

    static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(a.union(b).count)
    }
}

// メモの手入れ: ダブったメモ、古くなったメモ（期限切れ・長く見ていない・リンク切れ）、覚えるメモの復習、
// 絞り込みを保存したスマートフォルダ。規則は Web 版と同じ。

import Foundation

// MARK: ダブったメモ

/// 同じ内容に見える 2 件（keep に drop をまとめる）
public struct DuplicatePair: Sendable, Equatable {
    public var keep: String
    public var drop: String
    /// 「別のままにする」で消したときの鍵（順序によらない）
    public var key: String { [keep, drop].sorted().joined(separator: "|") }
}

extension Heuristics {
    /// 2 件の近さ（0〜1）。出典が同じなら 1
    public static func duplicateScore(_ a: Note, _ b: Note) -> Double {
        if let u = a.url, !u.isEmpty, u == b.url { return 1 }
        let ga = grams(a.title + "\n" + a.text), gb = grams(b.title + "\n" + b.text)
        guard ga.count >= 4, gb.count >= 4 else { return a.text == b.text && !a.text.isEmpty ? 1 : 0 }
        return jaccard(ga, gb)
    }

    /// ダブっていそうな組（近い順）。新しい 300 件の中で探す
    public static func duplicates(_ notes: [Note], dismissed: Set<String> = [], limit: Int = 1) -> [DuplicatePair] {
        let pool = Array(notes.filter { !$0.example }.sorted { $0.createdAt > $1.createdAt }.prefix(300))
        var found: [(DuplicatePair, Double)] = []
        for i in 0..<pool.count {
            for j in (i + 1)..<pool.count {
                let a = pool[i], b = pool[j]
                let s = duplicateScore(a, b)
                guard s >= 0.6 else { continue }
                // 長い方・役立った方を残す
                let keepA = (a.helpful, a.text.count) >= (b.helpful, b.text.count)
                let pair = keepA ? DuplicatePair(keep: a.id, drop: b.id) : DuplicatePair(keep: b.id, drop: a.id)
                if !dismissed.contains(pair.key) { found.append((pair, s)) }
            }
        }
        return found.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    /// しまう前に、同じようなメモがもうあるか
    public static func similarNote(text: String, url: String?, in notes: [Note]) -> Note? {
        let probe = Note(text: text, url: url)
        return notes.filter { !$0.example }.map { ($0, duplicateScore(probe, $0)) }.filter { $0.1 >= 0.6 }.max { $0.1 < $1.1 }?.0
    }

    /// 2 件を 1 件にまとめる（本文が違えばつなげる。タグなどは合わせる）
    public static func merged(_ keep: Note, with drop: Note) -> Note {
        var n = keep
        let a = keep.text.trimmingCharacters(in: .whitespacesAndNewlines), b = drop.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !b.isEmpty, !a.contains(b) { n.text = b.contains(a) ? b : a + "\n\n" + b }
        func union(_ x: [String], _ y: [String]) -> [String] { var seen = Set<String>(); return (x + y).filter { seen.insert($0.lowercased()).inserted } }
        n.tags = union(keep.tags, drop.tags)
        n.situations = union(keep.situations, drop.situations)
        n.helpful = keep.helpful + drop.helpful
        n.pinned = keep.pinned || drop.pinned
        if n.url == nil { n.url = drop.url }
        if n.summary.isEmpty { n.summary = drop.summary }
        n.createdAt = min(keep.createdAt, drop.createdAt)
        return n
    }
}

// MARK: 古くなったメモ

public struct StaleItem: Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        /// 期限・キャンペーンが過ぎた（その日）
        case expired(String)
        /// 長く見ていない（日数）
        case old(Int)
        /// 出典のリンクが切れている
        case brokenLink
    }
    public var note: Note
    public var reason: Reason

    public var label: String {
        switch reason {
        case .expired(let d): return L("期限（\(d)）が過ぎています", "Its date (\(d)) has passed")
        case .old(let days): return L("\(days / 365) 年以上前のメモです。今も正しい？", "Saved over \(days / 365) year(s) ago. Still right?")
        case .brokenLink: return L("出典のリンクが開けなくなっています", "The source link no longer opens")
        }
    }
}

extension Heuristics {
    static let deadlineWords = ["まで", "期限", "締切", "締め切り", "キャンペーン", "セール", "限定", "終了", "until", "deadline", "expire", "sale", "campaign", "ends"]

    /// 見直したいメモ（リンク切れ → 期限切れ → 古い順）。「まだ使える」を押したものは 1 年出さない
    public static func staleNotes(_ notes: [Note], now: Date = Date(), limit: Int = 3) -> [StaleItem] {
        let today = dayFormatter.string(from: now)
        var out: [StaleItem] = []
        for n in notes where !n.example {
            if let c = n.checkedAt, now.timeIntervalSince(c) < 365 * 86400 { continue }
            if n.linkBroken == true {
                out.append(StaleItem(note: n, reason: .brokenLink))
            } else if let r = n.remindAt, r < today, let d = dayFormatter.date(from: r), now.timeIntervalSince(d) > 3 * 86400,
                      deadlineWords.contains(where: { n.text.lowercased().contains($0) || n.title.lowercased().contains($0) }) {
                out.append(StaleItem(note: n, reason: .expired(r)))
            } else {
                let last = max(n.createdAt, n.lastSeen ?? .distantPast)
                let days = Int(now.timeIntervalSince(last) / 86400)
                if days >= 365 { out.append(StaleItem(note: n, reason: .old(days))) }
            }
        }
        func rank(_ r: StaleItem.Reason) -> Int {
            switch r { case .brokenLink: return 0; case .expired: return 1; case .old: return 2 }
        }
        return Array(out.sorted { rank($0.reason) != rank($1.reason) ? rank($0.reason) < rank($1.reason) : $0.note.createdAt < $1.note.createdAt }.prefix(limit))
    }
}

// MARK: 覚えるメモの復習

/// 間隔をあけて出す（1・3・7・14・30・90・180 日）
public struct Review: Codable, Sendable, Equatable {
    public static let intervals = [1, 3, 7, 14, 30, 90, 180]
    /// 何回続けて覚えていたか
    public var step: Int
    /// 次に出す日時
    public var due: Date

    public init(step: Int = 0, due: Date) {
        self.step = step
        self.due = due
    }

    /// 覚え始める（明日から出す）
    public static func start(now: Date = Date()) -> Review {
        Review(step: 0, due: Calendar.current.startOfDay(for: now).addingTimeInterval(86400))
    }

    /// 答えたあと。覚えていれば間隔を広げ、忘れていれば明日もう一度
    public func answered(remembered: Bool, now: Date = Date()) -> Review {
        let next = remembered ? min(step + 1, Self.intervals.count - 1) : 0
        let days = remembered ? Self.intervals[next] : 1
        return Review(step: next, due: Calendar.current.startOfDay(for: now).addingTimeInterval(Double(days) * 86400))
    }

    enum CodingKeys: String, CodingKey { case step, due }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        step = (try? c.decode(Int.self, forKey: .step)) ?? 0
        due = Date(timeIntervalSince1970: ((try? c.decode(Double.self, forKey: .due)) ?? 0) / 1000)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(step, forKey: .step)
        try c.encode((due.timeIntervalSince1970 * 1000).rounded(), forKey: .due)
    }
}

extension Heuristics {
    /// 今日復習するメモ（期日の早い順）
    public static func dueReviews(_ notes: [Note], now: Date = Date()) -> [Note] {
        notes.filter { ($0.review?.due ?? .distantFuture) <= now }.sorted { $0.review!.due < $1.review!.due }
    }
}

// MARK: スマートフォルダ（絞り込みを保存）

public struct SmartFolder: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    /// 文字での絞り込み
    public var query: String
    /// フォルダ（nil ならすべて）
    public var folder: String?
    public var filter: NoteFilter

    public init(id: String = UUID().uuidString, name: String, query: String = "", folder: String? = nil, filter: NoteFilter) {
        self.id = id
        self.name = name
        self.query = query
        self.folder = folder
        self.filter = filter
    }

    public func matches(_ n: Note, now: Date = Date()) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return (folder == nil || n.category == folder) && (q.isEmpty || n.haystack.contains(q)) && filter.matches(n, now: now)
    }
}

public enum SmartFolders {
    static let key = "smartFolders"

    public static func load(_ d: UserDefaults = .standard) -> [SmartFolder] {
        d.data(forKey: key).flatMap { try? JSONDecoder().decode([SmartFolder].self, from: $0) } ?? []
    }

    public static func save(_ all: [SmartFolder], _ d: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(all) { d.set(data, forKey: key) }
    }
}

// MARK: リンク切れの確認

public enum LinkChecker {
    /// true: 開ける、false: 切れている（404・410・ホストが無い）、nil: わからない（通信できない・ほかのエラー）
    public static func check(_ s: String) async -> Bool? {
        guard let url = URL(string: s), let scheme = url.scheme, scheme.hasPrefix("http") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.httpMethod = "HEAD"
        do {
            let (_, res) = try await URLSession.shared.data(for: req)
            guard let code = (res as? HTTPURLResponse)?.statusCode else { return nil }
            if code == 404 || code == 410 { return false }
            // HEAD を受け付けないサイトもあるので、それ以外のエラーは「わからない」
            return code < 400 ? true : nil
        } catch let e as URLError where e.code == .cannotFindHost || e.code == .dnsLookupFailed {
            return false
        } catch {
            return nil
        }
    }
}

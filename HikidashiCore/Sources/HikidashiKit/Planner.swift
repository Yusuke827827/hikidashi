// 手順モード・やることボード・シリーズ・使っていないメモ・次にやること・QR コードの中身。規則は Web 版と同じ。

import Foundation

// MARK: 手順モード

extension Heuristics {
    static let bulletPattern = #"^\s*(?:[・•\-*●◆■□☐☑]|\d+[.)、．]|[①-⑳]|STEP\s*\d+[:：.]?|手順\s*\d+[:：.]?)\s*"#

    /// 手順に分ける。番号・箇条書き・チェックの行があればそれを、無ければ行ごと、1 行だけなら「。」で区切る
    public static func steps(_ text: String) -> [String] {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix(LinkFetcher.marker) && !$0.hasPrefix(TextExtractor.imageMarker) && !$0.hasPrefix(TextExtractor.fileMarker) }
        let marked = lines.filter { $0.range(of: bulletPattern, options: [.regularExpression, .caseInsensitive]) != nil }
        let picked: [String]
        if marked.count >= 2 { picked = marked }
        else if lines.count >= 2 { picked = lines }
        else { picked = (lines.first ?? "").components(separatedBy: "。").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.map { $0 + "。" } }
        return picked.map { $0.replacingOccurrences(of: bulletPattern, with: "", options: [.regularExpression, .caseInsensitive]) }.filter { !$0.isEmpty }
    }

    /// 話した言葉が「次へ」「戻る」か（手順モードを声で進める）
    public static func stepCommand(_ said: String) -> Int {
        let s = said.lowercased()
        if s.range(of: "(次|つぎ|ネクスト|進んで|すすんで|next|okay next)", options: .regularExpression) != nil { return 1 }
        if s.range(of: "(戻|もど|前へ|まえ|back|previous)", options: .regularExpression) != nil { return -1 }
        return 0
    }
}

// MARK: やることボード

public enum BoardColumn: String, CaseIterable, Sendable {
    case today, week, someday, done

    public var title: String {
        switch self {
        case .today: return L("今日", "Today")
        case .week: return L("今週", "This week")
        case .someday: return L("いつか", "Someday")
        case .done: return L("済み", "Done")
        }
    }
}

extension Heuristics {
    /// やることボード。自分で列を決めたメモはその列、決めていなければ日付やチェックリストから並べる
    public static func board(_ notes: [Note], now: Date = Date(), calendar cal: Calendar = .current) -> [BoardColumn: [Note]] {
        let today = dayFormatter.string(from: now)
        let week = dayFormatter.string(from: cal.date(byAdding: .day, value: 7, to: now) ?? now)
        var out: [BoardColumn: [Note]] = [:]
        for n in notes where !n.example && n.archived != true {
            var col: BoardColumn?
            if let b = n.board.flatMap(BoardColumn.init(rawValue:)) {
                // 済みは 2 週間で消す
                if b == .done, now.timeIntervalSince(n.modifiedAt) > 14 * 86400 { continue }
                col = b
            } else if n.plannedDay == today || (n.remindAt.map { $0 <= today } ?? false) {
                col = .today
            } else if let r = n.remindAt, r <= week {
                col = .week
            } else if let a = n.alarm, a.hasSchedule, let next = a.occurrences(after: now, count: 1).first, next.timeIntervalSince(now) < 7 * 86400 {
                col = dayFormatter.string(from: next) == today ? .today : .week
            } else if checkItems(n.text).contains(where: { !$0.done }) {
                col = .someday
            }
            if let col { out[col, default: []].append(n) }
        }
        return out
    }
}

// MARK: シリーズ

extension Heuristics {
    static let circled = Array("①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳")

    /// タイトルの最後の番号（「旅行の準備 2」「その3」「（4）」「Part 5」「⑥」）。無ければ nil
    public static func seriesKey(_ title: String) -> (stem: String, index: Int)? {
        let t = title.trimmingCharacters(in: .whitespaces)
        if let last = t.last, let i = circled.firstIndex(of: last) {
            let stem = String(t.dropLast()).trimmingCharacters(in: .whitespaces)
            return stem.count >= 2 ? (stem, i + 1) : nil
        }
        let pattern = #"^(.*?)[\s　:：\-ー]*[（(]?(?:その|第|part\s*|#|no\.?\s*|vol\.?\s*)?(\d{1,3})[)）]?(?:回|話|部|章|日目)?$"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
              let sr = Range(m.range(at: 1), in: t), let nr = Range(m.range(at: 2), in: t), let n = Int(t[nr]) else { return nil }
        let stem = String(t[sr]).trimmingCharacters(in: .whitespaces)
        return stem.count >= 2 ? (stem, n) : nil
    }

    /// 同じシリーズのメモ（番号順。2 つ以上あるときだけ）
    public static func series(of note: Note, in notes: [Note]) -> [Note] {
        guard let k = seriesKey(note.title) else { return [] }
        let same = notes.compactMap { n -> (Note, Int)? in
            guard !n.example, let x = seriesKey(n.title), x.stem.lowercased() == k.stem.lowercased() else { return nil }
            return (n, x.index)
        }
        return same.count >= 2 ? same.sorted { $0.1 < $1.1 }.map(\.0) : []
    }
}

// MARK: 使っていないメモ・次にやること

extension Heuristics {
    /// 半年見ていないメモ（お気に入り・秘密・しまい込んだもの・見本を除く。古い順に limit 件）
    public static func unused(_ notes: [Note], now: Date = Date(), days: Double = 180, limit: Int = 20) -> [Note] {
        let cut = now.addingTimeInterval(-days * 86400)
        return notes.filter { n in
            !n.example && !n.pinned && !n.isLocked && n.archived != true && n.helpful < 3
                && (n.lastSeen ?? n.modifiedAt) < cut && (n.checkedAt ?? .distantPast) < cut
        }
        .sorted { ($0.lastSeen ?? $0.modifiedAt) < ($1.lastSeen ?? $1.modifiedAt) }
        .prefix(limit).map { $0 }
    }

    /// 片づけを出す日か（月に 1 回、1 日〜7 日のあいだ）
    public static func tidyDue(now: Date = Date(), lastShown: Date?, calendar cal: Calendar = .current) -> Bool {
        guard cal.component(.day, from: now) <= 7 else { return false }
        guard let last = lastShown else { return true }
        return !cal.isDate(last, equalTo: now, toGranularity: .month)
    }

    /// AI が無いときの「次にやること」: 今日・今週のボード、やり残したチェック、読んでいない「あとで読む」
    public static func nextActions(_ notes: [Note], now: Date = Date(), limit: Int = 5) -> [Note] {
        let b = board(notes, now: now)
        var out = (b[.today] ?? []) + (b[.week] ?? [])
        out += notes.filter { n in !n.example && !n.isLocked && checkItems(n.text).contains { !$0.done } && !out.contains { $0.id == n.id } }
        out += notes.filter { n in n.readLater == true && n.readAt == nil && now.timeIntervalSince(n.createdAt) > 3 * 86400 && !out.contains { $0.id == n.id } }
        return Array(out.filter { !$0.isLocked }.prefix(limit))
    }
}

// MARK: QR コード・バーコード

public struct ScannedCode: Sendable, Equatable {
    public var title: String
    public var text: String
    public var url: String?
}

extension Heuristics {
    /// 読み取ったコードを、メモにしやすい形にする（Wi-Fi・URL・連絡先・商品コードなど）
    public static func describeCode(_ raw: String) -> ScannedCode {
        let p = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        func field(_ s: String, _ key: String) -> String? {
            guard let r = s.range(of: key + ":") else { return nil }
            var v = "", esc = false
            for ch in s[r.upperBound...] {
                if esc { v.append(ch); esc = false; continue }
                if ch == "\\" { esc = true; continue }
                if ch == ";" { break }
                v.append(ch)
            }
            return v.isEmpty ? nil : v
        }
        if p.uppercased().hasPrefix("WIFI:") {
            let ssid = field(p, "S") ?? "", pass = field(p, "P") ?? "", type = field(p, "T") ?? ""
            var lines = [L("ネットワーク: ", "Network: ") + ssid]
            if !pass.isEmpty { lines.append(L("パスワード: ", "Password: ") + pass) }
            if !type.isEmpty { lines.append(L("方式: ", "Security: ") + type) }
            return ScannedCode(title: "Wi-Fi " + ssid, text: lines.joined(separator: "\n"), url: nil)
        }
        if p.range(of: #"^https?://\S+$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return ScannedCode(title: URL(string: p)?.host ?? p, text: p, url: p)
        }
        if p.uppercased().hasPrefix("MECARD:") {
            let name = field(p, "N")?.replacingOccurrences(of: ",", with: " ") ?? ""
            let lines = [name, field(p, "TEL").map { "TEL: " + $0 }, field(p, "EMAIL").map { "Mail: " + $0 }, field(p, "ADR")].compactMap { $0 }.filter { !$0.isEmpty }
            return ScannedCode(title: name.isEmpty ? L("連絡先", "Contact") : name, text: lines.joined(separator: "\n"), url: field(p, "URL"))
        }
        if p.uppercased().hasPrefix("BEGIN:VCARD") {
            let get = { (k: String) -> String? in
                p.components(separatedBy: .newlines).first { $0.uppercased().hasPrefix(k) }.flatMap { l in l.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init) }
            }
            let name = (get("FN") ?? get("N")?.replacingOccurrences(of: ";", with: " ") ?? "").trimmingCharacters(in: .whitespaces)
            let lines = [name, get("TEL").map { "TEL: " + $0 }, get("EMAIL").map { "Mail: " + $0 }, get("ORG")].compactMap { $0 }.filter { !$0.isEmpty }
            return ScannedCode(title: name.isEmpty ? L("連絡先", "Contact") : name, text: lines.joined(separator: "\n"), url: get("URL"))
        }
        if p.lowercased().hasPrefix("tel:") { return ScannedCode(title: L("電話番号", "Phone"), text: String(p.dropFirst(4)), url: nil) }
        if p.lowercased().hasPrefix("mailto:") { return ScannedCode(title: L("メール", "Email"), text: String(p.dropFirst(7)), url: nil) }
        if p.range(of: #"^\d{8}$|^\d{12,14}$"#, options: .regularExpression) != nil {
            let q = "https://www.google.com/search?q=" + p
            return ScannedCode(title: L("商品コード ", "Product code ") + p, text: L("商品コード（JAN）: ", "Product code: ") + p, url: q)
        }
        let first = p.components(separatedBy: .newlines).first ?? p
        return ScannedCode(title: String(first.prefix(40)), text: p, url: nil)
    }
}

extension Librarian {
    /// 次にやることの提案。AI があればメモ全体から選んで短い助言を、無ければ期限が近いもの・やり残しを並べる
    public func suggestNext(now: Date = Date()) async -> RecallOutcome {
        let q = L("今週やっておくと良さそうなことは？期限が近いもの・やり残し・季節や予定に合うものから選んで、短く提案して",
                  "What would be good to do this week? Pick from things due soon, unfinished items, and what fits the season or plans. Suggest briefly.")
        if hasAI {
            let r = await recall(q)
            if !r.keywordOnly { return r }
        }
        let picks = Heuristics.nextActions(store.notes.filter { $0.archived != true }, now: now)
        let answer = picks.isEmpty
            ? L("今すぐやることは見つかりませんでした。", "Nothing urgent right now.")
            : L("期限が近いものと、やり残しです。", "Things due soon and unfinished items.")
        return RecallOutcome(query: q, answer: answer, noteIDs: picks.map(\.id), keywordOnly: true)
    }
}

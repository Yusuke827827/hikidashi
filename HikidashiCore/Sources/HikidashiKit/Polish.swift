// 使いやすさのための小さな部品: 少しずつ出すヒント、共有フォルダのコメント、週のまとめ、AI のまとめ方の好み、印刷用の HTML。
// 規則は Web 版と同じ。

import Foundation

// MARK: AI のまとめ方の好み

public enum AIStyle {
    public enum Form: String, CaseIterable, Sendable { case bullets, prose }
    public enum Length: String, CaseIterable, Sendable { case short, normal, detailed }

    public static var form: Form {
        get { Form(rawValue: UserDefaults.standard.string(forKey: "aiStyle.form") ?? "") ?? .bullets }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "aiStyle.form") }
    }

    public static var length: Length {
        get { Length(rawValue: UserDefaults.standard.string(forKey: "aiStyle.length") ?? "") ?? .normal }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "aiStyle.length") }
    }

    /// AI への頼み方に足す一文（ふつうの箇条書きなら何も足さない）
    public static var hint: String { hint(form: form, length: length) }

    public static func hint(form: Form, length: Length) -> String {
        var parts: [String] = []
        if form == .prose { parts.append("Write it as one or two short plain paragraphs instead of \"・\" lines (keep numbered steps for procedures).") }
        switch length {
        case .short: parts.append("Keep it very short: at most about 3 lines.")
        case .detailed: parts.append("Be fairly detailed: keep supporting reasons and examples, not just the headline facts.")
        case .normal: break
        }
        return parts.isEmpty ? "" : " Style preference: " + parts.joined(separator: " ")
    }

    public static func label(_ f: Form) -> String { f == .bullets ? L("箇条書き", "Bullets") : L("文章", "Sentences") }
    public static func label(_ l: Length) -> String {
        switch l {
        case .short: return L("短め", "Short")
        case .normal: return L("ふつう", "Normal")
        case .detailed: return L("詳しめ", "Detailed")
        }
    }
}

// MARK: 少しずつ出すヒント（最初は「しまう・ひきだす・今日」だけ。慣れてきたら 1 日 1 つ）

public struct FeatureTip: Sendable, Equatable, Identifiable {
    public var id: String
    public var symbol: String
    public var title: String
    public var body: String
    /// メモがこの数を超えたら出す
    public var minNotes: Int
}

public enum FeatureTips {
    public static var all: [FeatureTip] {
        [
            FeatureTip(id: "share", symbol: "square.and.arrow.up", title: L("共有ボタンからしまう", "Save from the share sheet"),
                       body: L("X や Safari の共有ボタンで「Mindrawer」を選ぶと、そのまましまえます。", "Pick Mindrawer in the share sheet of X, Safari and more."), minNotes: 1),
            FeatureTip(id: "recall", symbol: "magnifyingglass", title: L("「これから◯◯する」で取り出す", "Say what you're about to do"),
                       body: L("上の「ひきだす」に、これからすることを書くと、役立つメモが出てきます。", "Type what you're about to do in Recall to get the notes that help."), minNotes: 3),
            FeatureTip(id: "palette", symbol: "command", title: L("機能は「探す」から", "Find any feature"),
                       body: L("右上の虫めがねで、機能の名前（ボード・同期・印刷など）からすぐ開けます。", "Tap the magnifier at the top and type a feature name (board, sync, print…)."), minNotes: 5),
            FeatureTip(id: "board", symbol: "rectangle.split.3x1", title: L("やることボード", "To-do board"),
                       body: L("メモの「…」→「やることボードへ」で、今日・今週・いつかに分けて片づけられます。", "From … → Add to to-do board, sort notes into Today, This week and Someday."), minNotes: 8),
            FeatureTip(id: "checklist", symbol: "checklist", title: L("チェックリストにする", "Make a checklist"),
                       body: L("買い物や持ち物のメモは「…」→「チェックリストにする」で、タップでチェックできます。", "Turn shopping or packing notes into tappable checklists from …."), minNotes: 10),
            FeatureTip(id: "widget", symbol: "square.grid.2x2", title: L("ウィジェットで見る", "Widgets"),
                       body: L("ホーム画面を長押しして「＋」から Mindrawer を選ぶと、今日のリスト・やることボード・あとで読むを出せます。", "Long-press the Home Screen, tap +, and add Mindrawer for your list, board or read-later."), minNotes: 12),
            FeatureTip(id: "sync", symbol: "arrow.triangle.2.circlepath", title: L("ほかの端末とそろえる", "Sync your devices"),
                       body: L("設定の「ほかの端末と同期」で、iPad・Mac・Web 版とメモがそろいます。", "Settings → Sync with your other devices keeps your iPad, Mac and the web in step."), minNotes: 15),
            FeatureTip(id: "voice", symbol: "mic", title: L("声で聞く", "Ask by voice"),
                       body: L("「聞く」でマイクを押して話すと、答えを読み上げます。手がふさがっているときに。", "In Ask, tap the mic and speak; answers are read aloud."), minNotes: 20),
        ]
    }

    static let seenKey = "tipsSeen", shownKey = "tipShownDay"

    public static var seen: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: seenKey) }
    }

    /// 今日出すヒント（まだ見ていないもので、メモの数に合うもの。1 日 1 つ）
    public static func today(noteCount: Int, seen: Set<String> = seen, now: Date = Date()) -> FeatureTip? {
        all.first { !seen.contains($0.id) && noteCount >= $0.minNotes }
    }

    public static func dismiss(_ id: String) { seen.insert(id) }
}

// MARK: 共有フォルダのコメント

public struct NoteComment: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var by: String
    public var text: String
    public var at: Date

    public init(id: String = UUID().uuidString, by: String, text: String, at: Date = Date()) {
        self.id = id
        self.by = by
        self.text = text
        self.at = at
    }

    enum CodingKeys: String, CodingKey { case id, by, text, at }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        by = (try? c.decode(String.self, forKey: .by)) ?? ""
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        at = Date(timeIntervalSince1970: ((try? c.decode(Double.self, forKey: .at)) ?? 0) / 1000)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(by, forKey: .by)
        try c.encode(text, forKey: .text)
        try c.encode((at.timeIntervalSince1970 * 1000).rounded(), forKey: .at)
    }

    /// 2 つの端末のコメントを合わせる（id で重ねず、古い順。50 件まで）
    public static func merge(_ a: [NoteComment]?, _ b: [NoteComment]?) -> [NoteComment]? {
        var byID: [String: NoteComment] = [:]
        for c in (a ?? []) + (b ?? []) { byID[c.id] = c }
        let all = byID.values.sorted { $0.at < $1.at }.suffix(50)
        return all.isEmpty ? nil : Array(all)
    }
}

extension NoteStore {
    /// コメントを足す（共有フォルダなら、次の同期で家族にも届く）
    public func addComment(_ id: String, text: String, by: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        update(id) { n in n.comments = (n.comments ?? []) + [NoteComment(by: by.isEmpty ? L("自分", "Me") : by, text: String(t.prefix(500)))] }
    }
}

// MARK: 週のまとめ

public struct WeeklyDigest: Sendable, Equatable {
    public var title: String
    public var body: String
}

extension Heuristics {
    /// 今週のやること・期限・あとで読むを 1 つの知らせに（何も無ければ nil）
    public static func weeklyDigest(_ notes: [Note], now: Date = Date()) -> WeeklyDigest? {
        let b = board(notes, now: now)
        let due = (b[.today] ?? []) + (b[.week] ?? [])
        let open = notes.filter { !$0.example && !$0.isLocked && $0.archived != true && checkItems($0.text).contains { !$0.done } }
        let later = notes.filter { $0.readLater == true && $0.readAt == nil }
        guard !due.isEmpty || !open.isEmpty || !later.isEmpty else { return nil }
        var parts: [String] = []
        if !due.isEmpty { parts.append(L("今週のやること \(due.count) 件（\(due.prefix(2).map(\.title).joined(separator: "・"))）", "\(due.count) due this week (\(due.prefix(2).map(\.title).joined(separator: ", ")))")) }
        if !open.isEmpty { parts.append(L("やり残しのチェック \(open.count) 件", "\(open.count) unfinished checklists")) }
        if !later.isEmpty { parts.append(L("あとで読む \(later.count) 件", "\(later.count) to read later")) }
        return WeeklyDigest(title: L("今週のまとめ", "Your week"), body: parts.joined(separator: "\n"))
    }
}

// MARK: 印刷・PDF

public enum NotePrint {
    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// メモを印刷用のきれいな 1 枚に（チェックリストは □ 付き。複数なら続けて並べる）
    public static func html(_ notes: [Note]) -> String {
        let body = notes.map { n -> String in
            let lines = n.text.components(separatedBy: "\n").map { l -> String in
                if l.hasPrefix(Heuristics.unchecked) { return "<li class=\"ck\">☐ " + esc(String(l.dropFirst(2))) + "</li>" }
                if l.hasPrefix(Heuristics.checked) { return "<li class=\"ck done\">☑ " + esc(String(l.dropFirst(2))) + "</li>" }
                if l.trimmingCharacters(in: .whitespaces).isEmpty { return "<li class=\"gap\"></li>" }
                return "<li>" + esc(l) + "</li>"
            }.joined()
            let meta = [n.category, n.url ?? ""].filter { !$0.isEmpty }.map(esc).joined(separator: " · ")
            return "<section><h1>\(esc(n.title))</h1>" + (n.summary.isEmpty ? "" : "<p class=\"sum\">\(esc(n.summary))</p>") + "<ul>\(lines)</ul>" + (meta.isEmpty ? "" : "<p class=\"meta\">\(meta)</p>") + "</section>"
        }.joined()
        return """
        <!doctype html><html><head><meta charset="utf-8"><style>
        body{font-family:-apple-system,"Hiragino Sans","Noto Sans JP",sans-serif;color:#1c1c1e;margin:28px;font-size:13pt;line-height:1.6}
        section{page-break-inside:avoid;margin-bottom:28px;padding-bottom:18px;border-bottom:1px solid #ddd}
        h1{font-size:18pt;margin:0 0 6px}.sum{color:#555;margin:0 0 8px}ul{list-style:none;padding:0;margin:0}
        li{margin:2px 0;white-space:pre-wrap}li.ck{font-size:14pt}li.done{color:#888;text-decoration:line-through}li.gap{height:8px}
        .meta{color:#888;font-size:10pt;margin-top:10px}
        </style></head><body>\(body)</body></html>
        """
    }
}

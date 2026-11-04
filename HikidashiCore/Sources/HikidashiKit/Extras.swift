// しまう・使うを広げる機能: テンプレート、外国語のメモの翻訳、使われ方のまとめ、カレンダー用のファイル（.ics）、
// メール・LINE の受け取り箱、1 枚だけの公開リンク。規則は Web 版と同じ。

import Foundation

// MARK: テンプレート

public struct NoteTemplate: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var icon: String
    public var name: String
    public var title: String
    public var text: String
    public var category: String

    public init(id: String = UUID().uuidString, icon: String = "📝", name: String, title: String = "", text: String, category: String = "") {
        self.id = id
        self.icon = icon
        self.name = name
        self.title = title
        self.text = text
        self.category = category
    }

    /// {{日付}} / {{date}} を今日の日付にする
    public func filled(now: Date = Date()) -> (title: String, text: String) {
        let d = Heuristics.dayFormatter.string(from: now)
        func f(_ s: String) -> String { s.replacingOccurrences(of: "{{日付}}", with: d).replacingOccurrences(of: "{{date}}", with: d) }
        return (f(title), f(text))
    }
}

public enum Templates {
    static let key = "noteTemplates"

    public static var builtIn: [NoteTemplate] {
        [
            NoteTemplate(id: "shopping", icon: "🛒", name: L("買い物リスト", "Shopping list"), title: L("買い物 {{日付}}", "Shopping {{date}}"),
                         text: L("☐ \n☐ \n☐ ", "☐ \n☐ \n☐ "), category: L("買い物", "Shopping")),
            NoteTemplate(id: "packing", icon: "🧳", name: L("旅行の持ち物", "Packing list"), title: L("持ち物", "Packing"),
                         text: L("☐ 財布・カード\n☐ スマホの充電器\n☐ 着替え（日数分）\n☐ 洗面用具\n☐ 常備薬\n☐ チケット・予約の控え", "☐ Wallet and cards\n☐ Phone charger\n☐ Clothes for each day\n☐ Toiletries\n☐ Medicine\n☐ Tickets and bookings"),
                         category: L("おでかけ・旅行", "Travel")),
            NoteTemplate(id: "recipe", icon: "🍳", name: L("レシピ", "Recipe"), title: "",
                         text: L("材料（  人分）\n・\n・\n\n作り方\n1. \n2. \n\nコツ\n・", "Ingredients (serves  )\n・\n・\n\nSteps\n1. \n2. \n\nTips\n・"), category: L("料理・食", "Food & Cooking")),
            NoteTemplate(id: "book", icon: "📚", name: L("読書メモ", "Book notes"), title: "",
                         text: L("本:\n著者:\n\n心に残ったこと\n・\n\n明日からやること\n・", "Book:\nAuthor:\n\nWhat stuck\n・\n\nWhat I'll do\n・"), category: L("仕事・勉強", "Work & Study")),
            NoteTemplate(id: "meeting", icon: "🗒", name: L("会議メモ", "Meeting notes"), title: L("会議 {{日付}}", "Meeting {{date}}"),
                         text: L("目的:\n決まったこと\n・\nやること（だれが・いつまで）\n☐ ", "Goal:\nDecided\n・\nTo do (who, by when)\n☐ "), category: L("仕事・勉強", "Work & Study")),
            NoteTemplate(id: "place", icon: "📍", name: L("行ってよかった場所", "A place I liked"), title: "",
                         text: L("場所:\nよかったこと:\nまた行くなら:\n", "Place:\nWhat was good:\nNext time:\n"), category: L("おでかけ・旅行", "Travel")),
        ]
    }

    public static func mine(_ d: UserDefaults = .standard) -> [NoteTemplate] {
        d.data(forKey: key).flatMap { try? JSONDecoder().decode([NoteTemplate].self, from: $0) } ?? []
    }

    public static func saveMine(_ all: [NoteTemplate], _ d: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(all) { d.set(data, forKey: key) }
    }

    /// 自分のテンプレートを先に、そのあと用意したもの
    public static func all(_ d: UserDefaults = .standard) -> [NoteTemplate] { mine(d) + builtIn }
}

// MARK: 外国語のメモ

extension Heuristics {
    /// アプリの言葉と違う言葉で書かれたメモか（日本語なら、かな・漢字がほとんど無く英字が多い）
    public static func looksForeign(_ text: String, language: AppLanguage = .current) -> Bool {
        var cjk = 0, latin = 0
        for u in text.unicodeScalars {
            switch u.value {
            case 0x3040...0x30FF, 0x3400...0x9FFF: cjk += 1
            case 0x41...0x5A, 0x61...0x7A: latin += 1
            default: break
            }
        }
        if language == .ja { return latin >= 30 && Double(cjk) < Double(latin) * 0.05 }
        return cjk >= 15 && Double(cjk) > Double(latin) * 0.5
    }
}

// MARK: 使われ方のまとめ

public struct UsageStats: Sendable, Equatable {
    public var total: Int
    /// この 12 か月の、月ごとにしまった数（古い順。"2026-11" のような鍵）
    public var perMonth: [MonthCount]
    /// フォルダごとの数（多い順・8 件まで）
    public var perFolder: [FolderCount]
    /// よく役立ったメモ（5 件まで）
    public var topHelpful: [Note]
    public var favorites: Int
    public var reviewing: Int
    /// 復習で 30 日以上の間隔まで覚えたもの
    public var learned: Int
    public var withNotification: Int
    public var addedThisMonth: Int

    public struct MonthCount: Sendable, Equatable { public var month: String; public var count: Int }
    public struct FolderCount: Sendable, Equatable { public var folder: String; public var count: Int }
}

extension Heuristics {
    public static func usageStats(_ notes: [Note], now: Date = Date(), calendar cal: Calendar = .current) -> UsageStats {
        let real = notes.filter { !$0.example }
        let f = DateFormatter()
        f.calendar = cal
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        let months: [String] = (0..<12).reversed().compactMap { cal.date(byAdding: .month, value: -$0, to: now).map(f.string) }
        var count: [String: Int] = [:]
        for n in real { count[f.string(from: n.createdAt), default: 0] += 1 }
        var folders: [String: Int] = [:]
        for n in real { folders[n.category.isEmpty ? otherFolder : n.category, default: 0] += 1 }
        return UsageStats(
            total: real.count,
            perMonth: months.map { UsageStats.MonthCount(month: $0, count: count[$0] ?? 0) },
            perFolder: folders.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(8).map { UsageStats.FolderCount(folder: $0.key, count: $0.value) },
            topHelpful: Array(real.filter { $0.helpful > 0 }.sorted { $0.helpful > $1.helpful }.prefix(5)),
            favorites: real.filter(\.pinned).count,
            reviewing: real.filter { $0.review != nil }.count,
            learned: real.filter { ($0.review?.step ?? 0) >= 4 }.count,
            withNotification: real.filter { $0.alarm != nil || $0.remindAt != nil }.count,
            addedThisMonth: count[f.string(from: now)] ?? 0)
    }
}

// MARK: カレンダー用のファイル（.ics）

public enum ICS {
    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,").replacingOccurrences(of: "\n", with: "\\n")
    }

    static func stamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: d)
    }

    /// メモ 1 件の予定（リマインド日は終日、通知は時刻つき・繰り返しつき）。日付が無ければ nil
    public static func event(for n: Note, now: Date = Date()) -> String? {
        var lines = ["BEGIN:VEVENT", "UID:\(n.id)@mindrawer", "DTSTAMP:\(stamp(now))", "SUMMARY:\(esc(n.title))",
                     "DESCRIPTION:\(esc(String((n.summary.isEmpty ? n.text : n.summary + "\n\n" + n.text).prefix(1500))))"]
        if let u = n.url { lines.append("URL:\(esc(u))") }
        if let a = n.alarm, a.hasSchedule {
            lines.append("DTSTART:\(stamp(a.date))")
            lines.append("DTEND:\(stamp(a.date.addingTimeInterval(15 * 60)))")
            switch a.kind {
            case .daily: lines.append("RRULE:FREQ=DAILY")
            case .interval: lines.append("RRULE:FREQ=DAILY;INTERVAL=\(a.intervalDays)")
            case .weekly:
                let names = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
                lines.append("RRULE:FREQ=WEEKLY;BYDAY=" + a.weekdays.sorted().map { names[max(1, min(7, $0)) - 1] }.joined(separator: ","))
            case .monthly: lines.append("RRULE:FREQ=MONTHLY")
            default: break
            }
        } else if let r = n.remindAt, let d = Heuristics.dayFormatter.date(from: r) {
            let day = r.replacingOccurrences(of: "-", with: "")
            let next = Heuristics.dayFormatter.string(from: d.addingTimeInterval(86400)).replacingOccurrences(of: "-", with: "")
            lines.append("DTSTART;VALUE=DATE:\(day)")
            lines.append("DTEND;VALUE=DATE:\(next)")
        } else {
            return nil
        }
        lines.append("END:VEVENT")
        return lines.joined(separator: "\r\n")
    }

    public static func calendar(_ notes: [Note], now: Date = Date()) -> String {
        (["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Mindrawer//JA", "CALSCALE:GREGORIAN"]
            + notes.compactMap { event(for: $0, now: now) } + ["END:VCALENDAR"]).joined(separator: "\r\n") + "\r\n"
    }
}

// MARK: メール・LINE の受け取り箱

public struct InboxConfig: Codable, Sendable, Equatable {
    public var server: String
    public var id: String
    public var key: String
    public var email: String?
    public var line: Bool
}

public struct InboxEntry: Codable, Sendable, Equatable {
    public var text: String
    public var url: String?
    public var from: String
    public var at: Double
}

public enum InboxClient {
    static let key = "mailInbox"

    public static func load(_ d: UserDefaults = .standard) -> InboxConfig? {
        d.data(forKey: key).flatMap { try? JSONDecoder().decode(InboxConfig.self, from: $0) }
    }

    public static func save(_ c: InboxConfig?, _ d: UserDefaults = .standard) {
        if let c, let data = try? JSONEncoder().encode(c) { d.set(data, forKey: key) } else { d.removeObject(forKey: key) }
    }

    public static func create(server: String) async throws -> InboxConfig {
        guard let url = URL(string: server + "/inbox") else { throw ShareError.noServer }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        let (data, res) = try await URLSession.shared.data(for: req)
        guard (res as? HTTPURLResponse)?.statusCode == 200 else { throw ShareError.server((res as? HTTPURLResponse)?.statusCode ?? 0) }
        struct R: Decodable { var id: String; var key: String; var email: String?; var line: Bool }
        let r = try JSONDecoder().decode(R.self, from: data)
        return InboxConfig(server: server, id: r.id, key: r.key, email: r.email, line: r.line)
    }

    /// たまっているメモを受け取る（サーバー側は空になる）
    public static func fetch(_ c: InboxConfig) async throws -> [InboxEntry] {
        guard let url = URL(string: c.server + "/inbox/" + c.id) else { return [] }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue(c.key, forHTTPHeaderField: "x-inbox-key")
        let (data, res) = try await URLSession.shared.data(for: req)
        guard (res as? HTTPURLResponse)?.statusCode == 200 else { throw ShareError.server((res as? HTTPURLResponse)?.statusCode ?? 0) }
        struct R: Decodable { var items: [InboxEntry] }
        return try JSONDecoder().decode(R.self, from: data).items
    }
}

// MARK: 1 枚だけの公開リンク

public struct PublicLink: Codable, Sendable, Equatable {
    public var url: String
    public var id: String
    public var key: String
    public var server: String
}

public enum PublicLinks {
    static let key = "publicLinks"

    /// メモの id → 公開リンク（この端末だけに覚えておく）
    public static func all(_ d: UserDefaults = .standard) -> [String: PublicLink] {
        d.data(forKey: key).flatMap { try? JSONDecoder().decode([String: PublicLink].self, from: $0) } ?? [:]
    }

    static func save(_ all: [String: PublicLink], _ d: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(all) { d.set(data, forKey: key) }
    }

    public static func create(_ n: Note, server: String) async throws -> PublicLink {
        if let have = all()[n.id] { return have }
        guard let url = URL(string: server + "/p") else { throw ShareError.noServer }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        var body: [String: Any] = ["title": n.title, "text": n.text, "category": n.category]
        if let u = n.url { body["url"] = u }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, res) = try await URLSession.shared.data(for: req)
        guard (res as? HTTPURLResponse)?.statusCode == 200 else { throw ShareError.server((res as? HTTPURLResponse)?.statusCode ?? 0) }
        struct R: Decodable { var id: String; var key: String; var url: String }
        let r = try JSONDecoder().decode(R.self, from: data)
        let link = PublicLink(url: r.url, id: r.id, key: r.key, server: server)
        var a = all()
        a[n.id] = link
        save(a)
        return link
    }

    public static func remove(noteID: String) async {
        guard let link = all()[noteID], let url = URL(string: link.server + "/p/" + link.id) else { return }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "DELETE"
        req.setValue(link.key, forHTTPHeaderField: "x-delete-key")
        _ = try? await URLSession.shared.data(for: req)
        var a = all()
        a[noteID] = nil
        save(a)
    }
}

extension Librarian {
    /// メール・LINE の受け取り箱にたまったメモを取り込む。取り込んだ数を返す
    @discardableResult
    /// メールで届いたメルマガを、要点だけのメモにするか（設定。最初はオン）
    public static var newsletterTips: Bool {
        get { UserDefaults.standard.object(forKey: "newsletterTips") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "newsletterTips") }
    }

    public func pullInbox() async -> Int {
        guard let c = InboxClient.load(), let items = try? await InboxClient.fetch(c), !items.isEmpty else { return 0 }
        var notes: [Note] = []
        for i in items {
            let at = Date(timeIntervalSince1970: i.at / 1000)
            // メルマガは、AI で要点だけにして 1 つずつメモにする
            if Self.newsletterTips, Heuristics.looksLikeNewsletter(i.text),
               let points = await condense(String(i.text.prefix(20_000))) {
                let tips = Heuristics.splitTips(points)
                if !tips.isEmpty {
                    notes += tips.map { Note(text: $0, url: i.url, createdAt: at, filed: false) }
                    continue
                }
                notes.append(Note(text: points, url: i.url, createdAt: at, filed: false, original: i.text))
                continue
            }
            notes.append(Note(text: i.text, url: i.url, createdAt: at, filed: false))
        }
        return importNotes(notes)
    }
}

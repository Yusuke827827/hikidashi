// メモ 1 件。Web 版（claude.ai の Hikidashi）の書き出し JSON と同じ形で読み書きする。
// 日時は Web 版に合わせて「1970 年からのミリ秒」の数値で保存する。

import Foundation

/// 着いたら知らせる場所
public struct Place: Codable, Hashable, Sendable {
    public var name: String
    public var latitude: Double
    public var longitude: Double
    /// 半径（メートル）
    public var radius: Double

    public init(name: String, latitude: Double, longitude: Double, radius: Double = 150) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
    }
}

public struct Note: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    /// 本文（共有された文、スクショから読み取った文、自分で書いた備忘録）
    public var text: String
    public var url: String?
    public var title: String
    public var summary: String
    /// フォルダ名
    public var category: String
    public var tags: [String]
    /// このメモが役立つ場面（「洗濯するとき」など）
    public var situations: [String]
    /// リマインド日（YYYY-MM-DD）
    public var remindAt: String?
    public var createdAt: Date
    public var pinned: Bool
    public var helpful: Int
    /// 「今日のひとつ」で最後に見た日時
    public var lastSeen: Date?
    /// 見本として入れたメモ
    public var example: Bool
    /// AI による整理が済んだか。共有シートから入った直後や、API キーが無いときは false
    public var filed: Bool
    /// 添付したスクショ（保存フォルダ内 Images/ のファイル名）
    public var imageFile: String?
    /// メモ風に整える前の元の文（AI が本文を書き換えたときだけ）
    public var original: String?
    /// 添付したファイル（保存フォルダ内 Images/ のファイル名）と、元のファイル名
    public var file: String?
    public var fileTitle: String?
    /// 画像・ファイル・リンク先から文字を取り出し済みか
    public var enriched: Bool
    /// 着いたら知らせる場所
    public var place: Place?
    /// アラーム（日時・繰り返し・言葉）
    public var alarm: Alarm?
    /// 「今日のリストに入れる」で入れた日（YYYY-MM-DD）
    public var plannedDay: String?
    /// 最後に変えた日時（iCloud の同期で新しい方を残すため）
    public var updatedAt: Date?

    /// 最後に変えた日時（無ければ作った日時）
    public var modifiedAt: Date { updatedAt ?? createdAt }

    public init(
        id: String = UUID().uuidString,
        text: String,
        url: String? = nil,
        title: String = "",
        summary: String = "",
        category: String = "",
        tags: [String] = [],
        situations: [String] = [],
        remindAt: String? = nil,
        createdAt: Date = Date(),
        pinned: Bool = false,
        helpful: Int = 0,
        lastSeen: Date? = nil,
        example: Bool = false,
        filed: Bool = false,
        imageFile: String? = nil,
        original: String? = nil,
        file: String? = nil,
        fileTitle: String? = nil,
        enriched: Bool = false,
        place: Place? = nil,
        alarm: Alarm? = nil,
        plannedDay: String? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.text = text
        self.url = url
        self.title = title
        self.summary = summary
        self.category = category
        self.tags = tags
        self.situations = situations
        self.remindAt = remindAt
        self.createdAt = createdAt
        self.pinned = pinned
        self.helpful = helpful
        self.lastSeen = lastSeen
        self.example = example
        self.filed = filed
        self.imageFile = imageFile
        self.original = original
        self.file = file
        self.fileTitle = fileTitle
        self.enriched = enriched
        self.place = place
        self.alarm = alarm
        self.plannedDay = plannedDay
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, text, url, title, summary, category, tags, situations, remindAt, createdAt, pinned, helpful, lastSeen, example, filed, imageFile, original, file, fileTitle, enriched, place, alarm, plannedDay, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Web 版の id は文字列。念のため数値も受ける
        if let s = try? c.decode(String.self, forKey: .id) {
            id = s
        } else if let n = try? c.decode(Double.self, forKey: .id) {
            id = String(Int(n))
        } else {
            id = UUID().uuidString
        }
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        url = Self.nonEmpty(try c.decodeIfPresent(String.self, forKey: .url))
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        situations = try c.decodeIfPresent([String].self, forKey: .situations) ?? []
        remindAt = Self.validDay(try c.decodeIfPresent(String.self, forKey: .remindAt))
        createdAt = Self.decodeDate(c, .createdAt) ?? Date()
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        helpful = try c.decodeIfPresent(Int.self, forKey: .helpful) ?? 0
        lastSeen = Self.decodeDate(c, .lastSeen)
        example = try c.decodeIfPresent(Bool.self, forKey: .example) ?? false
        // Web 版のメモは整理済み（filed の項目が無い）として扱う
        filed = try c.decodeIfPresent(Bool.self, forKey: .filed) ?? true
        imageFile = try c.decodeIfPresent(String.self, forKey: .imageFile)
        original = try c.decodeIfPresent(String.self, forKey: .original)
        file = try c.decodeIfPresent(String.self, forKey: .file)
        fileTitle = try c.decodeIfPresent(String.self, forKey: .fileTitle)
        // Web 版のメモ（項目なし）は取り出し済みとして扱う
        enriched = try c.decodeIfPresent(Bool.self, forKey: .enriched) ?? true
        place = try? c.decodeIfPresent(Place.self, forKey: .place)
        alarm = try? c.decodeIfPresent(Alarm.self, forKey: .alarm)
        plannedDay = Self.validDay(try? c.decodeIfPresent(String.self, forKey: .plannedDay))
        updatedAt = Self.decodeDate(c, .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(text, forKey: .text)
        try c.encode(url, forKey: .url)
        try c.encode(title, forKey: .title)
        try c.encode(summary, forKey: .summary)
        try c.encode(category, forKey: .category)
        try c.encode(tags, forKey: .tags)
        try c.encode(situations, forKey: .situations)
        try c.encode(remindAt, forKey: .remindAt)
        try c.encode(Self.millis(createdAt), forKey: .createdAt)
        try c.encode(pinned, forKey: .pinned)
        try c.encode(helpful, forKey: .helpful)
        try c.encodeIfPresent(lastSeen.map(Self.millis), forKey: .lastSeen)
        try c.encode(example, forKey: .example)
        try c.encode(filed, forKey: .filed)
        try c.encodeIfPresent(imageFile, forKey: .imageFile)
        try c.encodeIfPresent(original, forKey: .original)
        try c.encodeIfPresent(file, forKey: .file)
        try c.encodeIfPresent(fileTitle, forKey: .fileTitle)
        try c.encode(enriched, forKey: .enriched)
        try c.encodeIfPresent(place, forKey: .place)
        try c.encodeIfPresent(alarm, forKey: .alarm)
        try c.encodeIfPresent(plannedDay, forKey: .plannedDay)
        try c.encodeIfPresent(updatedAt.map(Self.millis), forKey: .updatedAt)
    }

    static func millis(_ d: Date) -> Double { (d.timeIntervalSince1970 * 1000).rounded() }

    static func decodeDate(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Date? {
        if let ms = try? c.decode(Double.self, forKey: key) { return Date(timeIntervalSince1970: ms / 1000) }
        if let s = try? c.decode(String.self, forKey: key) { return ISO8601DateFormatter().date(from: s) }
        return nil
    }

    static func nonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    /// YYYY-MM-DD の形のときだけ返す
    public static func validDay(_ s: String?) -> String? {
        guard let s, s.count == 10, s.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        return s
    }

    /// 検索・関連付けに使う文字列（小文字）
    public var haystack: String {
        ([title, summary, text, category] + tags + situations).joined(separator: " ").lowercased()
    }
}

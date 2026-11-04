// リンク先のページを丸ごと保存する（リンクが切れても読めるように）。YouTube は字幕（無ければ説明文）を読む。
// 端末から直接読む（Web 版は中継サーバーの /page が同じことをする）。規則は中継サーバーの tools.ts と同じ。

import Foundation

public enum PageReader {
    static let maxText = 40_000

    /// テストの中ではネットにつながない
    static var offline: Bool { NSClassFromString("XCTestCase") != nil }

    public static func fetch(_ urlString: String) async -> PageArchive? {
        guard !offline, let url = URL(string: urlString), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        if let id = youtubeID(urlString) { return await youtube(id) }
        guard let html = await get(url) else { return nil }
        let r = htmlToText(html)
        guard r.text.count >= 40 else { return nil }
        return PageArchive(title: r.title, text: r.text)
    }

    static func get(_ url: URL) async -> String? {
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mindrawer/1.0", forHTTPHeaderField: "User-Agent")
        req.setValue("ja,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        guard let (data, res) = try? await URLSession.shared.data(for: req),
              let http = res as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        let head = data.prefix(3_000_000)
        return String(data: head, encoding: .utf8) ?? String(decoding: head, as: UTF8.self)
    }

    // MARK: ふつうのページ

    static func decode(_ s: String) -> String {
        var out = s
        for (a, b) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"), ("&nbsp;", " "), ("&amp;", "&")] {
            out = out.replacingOccurrences(of: a, with: b)
        }
        return out
    }

    static func firstMatch(_ s: String, _ pattern: String, group: Int = 0) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range(at: group), in: s) else { return nil }
        return String(s[r])
    }

    /// HTML から本文らしい文字を取り出す（スクリプト・飾りを除き、段落ごとに改行）
    public static func htmlToText(_ html: String) -> (title: String, text: String) {
        let title = decode(firstMatch(html, #"<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']*)"#, group: 1)
            ?? firstMatch(html, #"<title[^>]*>([\s\S]*?)</title>"#, group: 1) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var body = firstMatch(html, #"<article[\s\S]*?</article>"#) ?? firstMatch(html, #"<main[\s\S]*?</main>"#)
            ?? firstMatch(html, #"<body[\s\S]*?</body>"#) ?? html
        for (p, r) in [(#"<(script|style|noscript|svg|nav|header|footer|aside|form|iframe)[\s\S]*?</\1>"#, " "), (#"<br\s*/?>"#, "\n"),
                       (#"</(p|div|li|h[1-6]|tr|section|blockquote|pre)>"#, "\n"), (#"<li[^>]*>"#, "・"), (#"<[^>]+>"#, " ")] {
            body = body.replacingOccurrences(of: p, with: r, options: [.regularExpression, .caseInsensitive])
        }
        let lines = decode(body).components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: #"[ \t\u{00a0}]+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 1 }
        return (title, String(lines.joined(separator: "\n").prefix(maxText)))
    }

    // MARK: YouTube

    /// YouTube の動画 id（youtu.be・watch?v=・shorts）
    public static func youtubeID(_ s: String) -> String? {
        guard let u = URLComponents(string: s), let host = u.host?.lowercased() else { return nil }
        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            let id = String(u.path.dropFirst().prefix(11))
            return id.isEmpty ? nil : id
        }
        guard host == "youtube.com" || host.hasSuffix(".youtube.com") else { return nil }
        if let v = u.queryItems?.first(where: { $0.name == "v" })?.value { return v }
        return firstMatch(u.path, #"/(?:shorts|embed|live)/([\w-]{11})"#, group: 1)
    }

    static func youtube(_ id: String) async -> PageArchive? {
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(id)&hl=ja"), let html = await get(url) else { return nil }
        let title = decode(firstMatch(html, #"<meta name="title" content="([^"]*)""#, group: 1) ?? "")
        let desc: String = {
            guard let m = firstMatch(html, #""shortDescription":"((?:[^"\\]|\\.)*)""#, group: 1),
                  let d = try? JSONDecoder().decode(String.self, from: Data(("\"" + m + "\"").utf8)) else { return "" }
            return d
        }()
        if let raw = firstMatch(html, #""captionTracks":(\[.*?\])"#, group: 1),
           let tracks = try? JSONDecoder().decode([Track].self, from: Data(raw.utf8)),
           let pick = tracks.first(where: { $0.languageCode == "ja" }) ?? tracks.first(where: { $0.languageCode.hasPrefix("en") }) ?? tracks.first,
           let turl = URL(string: pick.baseUrl), let xml = await get(turl) {
            let text = transcript(xml)
            if !text.isEmpty { return PageArchive(title: title, text: String(text.prefix(maxText))) }
        }
        return desc.isEmpty ? nil : PageArchive(title: title, text: String(desc.prefix(maxText)))
    }

    struct Track: Decodable {
        var baseUrl: String
        var languageCode: String
    }

    /// 字幕の XML から文だけを並べる
    public static func transcript(_ xml: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"<text[^>]*>([\s\S]*?)</text>"#) else { return "" }
        return re.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).compactMap { m in
            Range(m.range(at: 1), in: xml).map { decode(decode(String(xml[$0]))).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
        }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

extension PageArchive {
    /// 本文に動画の要点を足したことの目印
    public static let videoMarker = "▶ "
    /// ページを丸ごと残すか（設定。最初はオン）
    public static var isOn: Bool {
        get { UserDefaults.standard.object(forKey: "archivePages") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "archivePages") }
    }
}

extension Heuristics {
    /// 「・」「-」などで始まる行が 2 つ以上あれば、1 行ずつに分ける（メルマガの要点を別々のメモにするため）
    public static func splitTips(_ text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        let bullets = lines.filter { $0.range(of: #"^(?:[・•\-*●◆■]|\d+[.)、])\s*"#, options: .regularExpression) != nil }
            .map { $0.replacingOccurrences(of: #"^(?:[・•\-*●◆■]|\d+[.)、])\s*"#, with: "", options: .regularExpression) }
            .filter { $0.count >= 6 }
        return bullets.count >= 2 ? bullets : []
    }

    /// メルマガらしい長いメールか
    public static func looksLikeNewsletter(_ text: String) -> Bool {
        text.count >= 1200 || text.range(of: #"配信停止|unsubscribe|メールマガジン|メルマガ|newsletter"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

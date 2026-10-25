// リンク先の中身（タイトル・説明）を取ってきて、メモの本文に足す。
// URL 付きで保存したメモを初めて整理するときに 1 回だけ行う。端末から直接そのページを読む（サーバーは使わない）。

import Foundation

public struct LinkPreview: Sendable, Equatable {
    public var title: String
    public var description: String

    public init(title: String, description: String) {
        self.title = title
        self.description = description
    }

    /// 本文に足す文
    public var noteText: String {
        [title, description].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

public enum LinkFetcher {
    /// 本文に足したことの目印
    public static let marker = "🔗 "

    public static func fetch(_ urlString: String) async -> LinkPreview? {
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mindrawer/1.0", forHTTPHeaderField: "User-Agent")
        req.setValue("text/html", forHTTPHeaderField: "Accept")
        guard let (data, res) = try? await URLSession.shared.data(for: req),
              let http = res as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        let head = data.prefix(512 * 1024)
        let html = String(data: head, encoding: .utf8) ?? String(decoding: head, as: UTF8.self)
        return parse(html: html)
    }

    /// HTML から og:title / og:description（無ければ <title> と description）を取り出す
    public static func parse(html: String) -> LinkPreview? {
        let title = meta(html, "og:title") ?? meta(html, "twitter:title") ?? tag(html, "title") ?? ""
        let desc = meta(html, "og:description") ?? meta(html, "twitter:description") ?? meta(html, "description") ?? ""
        let t = clean(title), d = clean(desc)
        guard !t.isEmpty || !d.isEmpty else { return nil }
        return LinkPreview(title: String(t.prefix(200)), description: String(d.prefix(600)))
    }

    /// 本文に足した後の文。足すものが無ければ元のまま
    public static func merge(_ text: String, _ p: LinkPreview) -> String {
        let add = p.noteText
        guard !add.isEmpty, !text.contains(marker) else { return text }
        let base = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return base.isEmpty ? marker + add : base + "\n\n" + marker + add
    }

    static func meta(_ html: String, _ name: String) -> String? {
        let n = NSRegularExpression.escapedPattern(for: name)
        // <meta property="og:title" content="..."> と、属性の順が逆のものの両方
        let patterns = [
            "<meta[^>]+(?:property|name)\\s*=\\s*[\"']\(n)[\"'][^>]*content\\s*=\\s*\"([^\"]*)\"",
            "<meta[^>]+(?:property|name)\\s*=\\s*[\"']\(n)[\"'][^>]*content\\s*=\\s*'([^']*)'",
            "<meta[^>]+content\\s*=\\s*\"([^\"]*)\"[^>]*(?:property|name)\\s*=\\s*[\"']\(n)[\"']",
        ]
        for p in patterns {
            if let v = firstGroup(html, p), !v.isEmpty { return v }
        }
        return nil
    }

    static func tag(_ html: String, _ name: String) -> String? {
        firstGroup(html, "<\(name)[^>]*>([^<]*)</\(name)>")
    }

    static func firstGroup(_ s: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }

    static func clean(_ s: String) -> String {
        var t = s
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&#x27;": "'", "&apos;": "'", "&nbsp;": " "]
        for (k, v) in entities { t = t.replacingOccurrences(of: k, with: v) }
        return t.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }
}

// 他のアプリのメモを取り込む。読めるもの:
//   Evernote の書き出し（.enex）、Google Keep（Google データエクスポートの .json）、
//   CSV（title / text / url / tags 列。無ければ 1 列目を本文に）、テキスト・Markdown（.txt / .md。--- の行で区切ると複数件）、
//   HTML（Apple メモや Notion を HTML で書き出したもの）。Notion の .zip は、ファイル App で展開してから .md を選ぶ。
// 取り込んだメモは「整理待ち」にして、あとで AI（無ければ言葉の辞書）が整理する。規則は Web 版と同じ。

import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

public enum Importer {
    public static let extensions = ["enex", "json", "csv", "txt", "md", "markdown", "html", "htm", "pdf"]

    public static func parse(_ data: Data, filename: String) -> [Note] {
        let ext = (filename as NSString).pathExtension.lowercased()
        let base = ((filename as NSString).lastPathComponent as NSString).deletingPathExtension
        if ext == "pdf" { return pdfHighlights(data, title: base).map { [$0] } ?? [] }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS) else { return [] }
        // Kindle のハイライト（端末の My Clippings.txt・アプリの「ノートブックを書き出す」の HTML）
        if text.contains("=========="), text.range(of: #"(?m)^- .*(?:Highlight|ハイライト|Your Note|メモ)"#, options: .regularExpression) != nil {
            return kindleClippings(text)
        }
        if (ext == "html" || ext == "htm"), text.contains("noteText"), text.contains("bookTitle") {
            return kindleNotebook(text)
        }
        let notes: [Note]
        switch ext {
        case "enex": notes = evernote(text)
        case "json": notes = keep(data)
        case "csv": notes = csv(text)
        case "html", "htm": notes = [plain(stripHTML(text), fallbackTitle: htmlTitle(text) ?? base)].compactMap { $0 }
        default: notes = plainFile(text, fallbackTitle: base)
        }
        return notes.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: Kindle・PDF のハイライト

    /// Kindle の My Clippings.txt。本ごとに 1 つのメモ（ハイライトを「・」で並べる）
    static func kindleClippings(_ text: String) -> [Note] {
        var books: [(String, [String])] = []
        for block in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "==========") {
            let lines = block.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard lines.count >= 3 else { continue }
            let book = lines[0].replacingOccurrences(of: "\u{FEFF}", with: "")
            // 2 行目は「- ハイライト 位置No. 120-121 | 追加日: …」。ブックマークは飛ばす
            guard lines[1].range(of: #"ブックマーク|Bookmark"#, options: .regularExpression) == nil else { continue }
            let body = lines.dropFirst(2).joined(separator: " ")
            let isNote = lines[1].range(of: #"Your Note|メモ"#, options: .regularExpression) != nil
            let entry = (isNote ? "📝 " : "") + body
            if let i = books.firstIndex(where: { $0.0 == book }) {
                if !books[i].1.contains(entry) { books[i].1.append(entry) }
            } else { books.append((book, [entry])) }
        }
        return books.map { book, items in
            var n = Note(text: items.map { "・" + $0 }.joined(separator: "\n"), title: String(book.prefix(80)), filed: false)
            n.tags = ["Kindle"]
            return n
        }
    }

    /// Kindle アプリの「ノートブックを書き出す」（HTML）
    static func kindleNotebook(_ html: String) -> [Note] {
        let book = firstClass(html, "bookTitle").map { decode(stripHTML($0)) } ?? "Kindle"
        let items = allClass(html, "noteText").map { decode(stripHTML($0)) }.filter { !$0.isEmpty }
        guard !items.isEmpty else { return [] }
        var n = Note(text: items.map { "・" + $0 }.joined(separator: "\n"), title: String(book.prefix(80)), filed: false)
        n.tags = ["Kindle"]
        return [n]
    }

    static func allClass(_ s: String, _ cls: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: "<(div|h3|span)[^>]*class=[\"'][^\"']*\\b\(cls)\\b[^\"']*[\"'][^>]*>([\\s\\S]*?)</(?:div|h3|span)>") else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 2)) }
    }

    static func firstClass(_ s: String, _ cls: String) -> String? { allClass(s, cls).first }

    /// PDF のハイライト（マーカーを引いたところの文）を 1 つのメモに
    static func pdfHighlights(_ data: Data, title: String) -> Note? {
        #if canImport(PDFKit)
        guard let doc = PDFDocument(data: data) else { return nil }
        var items: [String] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            for a in page.annotations where (a.type ?? "").lowercased().contains("highlight") || (a.type ?? "").lowercased().contains("underline") {
                let quads = a.quadrilateralPoints ?? []
                var text = ""
                if quads.count >= 4 {
                    // 1 行ごとの四角から、その下の文を読む
                    for q in stride(from: 0, to: quads.count - 3, by: 4) {
                        let pts: [CGPoint] = (0..<4).map { i in
                            #if os(macOS)
                            return quads[q + i].pointValue
                            #else
                            return quads[q + i].cgPointValue
                            #endif
                        }
                        let xs = pts.map { $0.x }, ys = pts.map { $0.y }
                        let r = CGRect(x: a.bounds.minX + xs.min()!, y: a.bounds.minY + ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
                        if let s = page.selection(for: r)?.string { text += s }
                    }
                }
                if text.isEmpty { text = page.selection(for: a.bounds)?.string ?? "" }
                text = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
                if let c = a.contents, !c.isEmpty { text += (text.isEmpty ? "" : "\n  📝 ") + c }
                if !text.isEmpty { items.append(text + "（p.\(i + 1)）") }
            }
        }
        guard !items.isEmpty else { return nil }
        var n = Note(text: items.map { "・" + $0 }.joined(separator: "\n"), title: String(((doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String) ?? title).prefix(80)), filed: false)
        n.tags = ["PDF"]
        return n
        #else
        return nil
        #endif
    }

    // MARK: Evernote

    static func evernote(_ xml: String) -> [Note] {
        blocks(xml, tag: "note").compactMap { b in
            let title = decode(first(b, tag: "title") ?? "")
            var content = first(b, tag: "content") ?? ""
            content = content.replacingOccurrences(of: "<![CDATA[", with: "").replacingOccurrences(of: "]]>", with: "")
            let body = stripHTML(content)
            let tags = blocks(b, tag: "tag").map(decode)
            let url = first(b, tag: "source-url").map(decode)
            var n = plain(body, fallbackTitle: title)
            if !title.isEmpty { n?.title = title }
            n?.tags = tags
            n?.url = url
            if let c = first(b, tag: "created"), let d = enexDate(c) { n?.createdAt = d }
            return n
        }
    }

    static func enexDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.date(from: s.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: Google Keep

    static func keep(_ data: Data) -> [Note] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let items: [[String: Any]] = (obj as? [[String: Any]]) ?? ((obj as? [String: Any]).map { [$0] } ?? [])
        return items.compactMap { j in
            guard j["textContent"] != nil || j["listContent"] != nil else { return nil }
            if (j["isTrashed"] as? Bool) == true { return nil }
            var body = (j["textContent"] as? String) ?? ""
            if let list = j["listContent"] as? [[String: Any]] {
                body += list.map { ((($0["isChecked"] as? Bool) == true) ? "☑ " : "☐ ") + (($0["text"] as? String) ?? "") }.joined(separator: "\n")
            }
            let title = (j["title"] as? String) ?? ""
            var n = plain(body, fallbackTitle: title)
            if !title.isEmpty { n?.title = title }
            n?.tags = ((j["labels"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }
            n?.url = ((j["annotations"] as? [[String: Any]]) ?? []).compactMap { $0["url"] as? String }.first
            if let us = j["createdTimestampUsec"] as? Double { n?.createdAt = Date(timeIntervalSince1970: us / 1_000_000) }
            if (j["isPinned"] as? Bool) == true { n?.pinned = true }
            return n
        }
    }

    // MARK: CSV

    static func csv(_ text: String) -> [Note] {
        let rows = csvRows(text)
        guard let header = rows.first else { return [] }
        let h = header.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        func col(_ names: [String]) -> Int? { h.firstIndex { names.contains($0) } }
        let ti = col(["title", "タイトル", "件名", "name"])
        let xi = col(["text", "content", "body", "note", "memo", "本文", "内容", "メモ"])
        let ui = col(["url", "link", "source", "出典", "リンク"])
        let gi = col(["tags", "tag", "labels", "タグ"])
        let hasHeader = ti != nil || xi != nil
        let data = hasHeader ? Array(rows.dropFirst()) : rows
        return data.compactMap { r in
            func cell(_ i: Int?) -> String { i.flatMap { $0 < r.count ? r[$0] : nil } ?? "" }
            let body: String
            if !hasHeader {
                body = r.joined(separator: "\n")
            } else if xi != nil {
                body = cell(xi)
            } else {
                var rest: [String] = []
                for (i, c) in r.enumerated() where i != ti && i != ui && i != gi { rest.append(c) }
                body = rest.joined(separator: "\n")
            }
            let title = cell(ti)
            var n = plain(body.isEmpty ? title : body, fallbackTitle: title)
            if !title.isEmpty { n?.title = title }
            let u = cell(ui); if !u.isEmpty { n?.url = u }
            let tg = cell(gi); if !tg.isEmpty { n?.tags = tg.components(separatedBy: CharacterSet(charactersIn: ",、;|#")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
            return n
        }
    }

    static func csvRows(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], cell = "", quoted = false
        let chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n"))
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if quoted {
                if ch == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { cell.append("\""); i += 1 } else { quoted = false }
                } else {
                    cell.append(ch)
                }
            } else if ch == "\"" {
                quoted = true
            } else if ch == "," {
                row.append(cell); cell = ""
            } else if ch == "\n" {
                row.append(cell); rows.append(row); row = []; cell = ""
            } else {
                cell.append(ch)
            }
            i += 1
        }
        if !cell.isEmpty || !row.isEmpty { row.append(cell); rows.append(row) }
        return rows.filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
    }

    // MARK: テキスト・Markdown

    static func plainFile(_ text: String, fallbackTitle: String) -> [Note] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var parts: [[String]] = [[]]
        for l in lines {
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.count >= 3, Set(t).count == 1, t.first == "-" || t.first == "=" { parts.append([]) } else { parts[parts.count - 1].append(l) }
        }
        let chunks = parts.map { $0.joined(separator: "\n") }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return chunks.compactMap { plain($0, fallbackTitle: chunks.count == 1 ? fallbackTitle : "") }
    }

    /// 本文からメモを作る（「# 見出し」があればタイトルに）
    static func plain(_ body: String, fallbackTitle: String) -> Note? {
        var text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        var title = ""
        if let first = text.components(separatedBy: "\n").first, first.hasPrefix("#") {
            title = first.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).trimmingCharacters(in: .whitespaces)
            text = text.components(separatedBy: "\n").dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { text = title }
        }
        if title.isEmpty { title = Heuristics.title(for: text) }
        if title == Heuristics.title(for: "") && !fallbackTitle.isEmpty { title = fallbackTitle }
        let url = text.range(of: #"https?://[^\s)\]>"']+"#, options: .regularExpression).map { String(text[$0]) }
        return Note(text: text, url: url, title: String(title.prefix(80)), filed: false)
    }

    // MARK: XML・HTML の小道具

    static func blocks(_ s: String, tag: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: "<\(tag)(?:\\s[^>]*)?>([\\s\\S]*?)</\(tag)>") else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }

    static func first(_ s: String, tag: String) -> String? { blocks(s, tag: tag).first }

    static func htmlTitle(_ s: String) -> String? {
        first(s, tag: "title").map { decode(stripHTML($0)) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    static func stripHTML(_ html: String) -> String {
        var s = html
        for (p, r) in [("<(script|style|head|title)[\\s\\S]*?</\\1>", ""), ("<br\\s*/?>", "\n"), ("</(p|div|li|h[1-6]|tr|en-todo)>", "\n"),
                       ("<li[^>]*>", "・"), ("<en-todo checked=\"true\"[^>]*/?>", "☑ "), ("<en-todo[^>]*/?>", "☐ "), ("<[^>]+>", "")] {
            s = s.replacingOccurrences(of: p, with: r, options: [.regularExpression, .caseInsensitive])
        }
        s = decode(s)
        return s.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decode(_ s: String) -> String {
        var out = s
        for (a, b) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "), ("&amp;", "&")] {
            out = out.replacingOccurrences(of: a, with: b)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

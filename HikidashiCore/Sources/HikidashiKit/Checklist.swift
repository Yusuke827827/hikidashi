// メモを買い物リスト・ToDo（チェックボックス）にする、メモを Markdown（Obsidian・Notion）に書き出す。
// 規則は Web 版と同じ: 行の頭が「☐ 」ならまだ、「☑ 」なら済み。

import Foundation

public struct CheckItem: Sendable, Equatable {
    public var done: Bool
    public var text: String
    /// 本文の何行目か
    public var line: Int
}

extension Heuristics {
    public static let unchecked = "☐ ", checked = "☑ "

    /// 本文の中のチェック項目
    public static func checkItems(_ text: String) -> [CheckItem] {
        text.components(separatedBy: "\n").enumerated().compactMap { i, l in
            if l.hasPrefix(unchecked) { return CheckItem(done: false, text: String(l.dropFirst(unchecked.count)), line: i) }
            if l.hasPrefix(checked) { return CheckItem(done: true, text: String(l.dropFirst(checked.count)), line: i) }
            return nil
        }
    }

    /// その行のチェックを付け外しした本文
    public static func toggleCheck(_ text: String, line: Int) -> String {
        var lines = text.components(separatedBy: "\n")
        guard lines.indices.contains(line) else { return text }
        let l = lines[line]
        if l.hasPrefix(unchecked) { lines[line] = checked + l.dropFirst(unchecked.count) }
        else if l.hasPrefix(checked) { lines[line] = unchecked + l.dropFirst(checked.count) }
        return lines.joined(separator: "\n")
    }

    /// 本文をチェックリストにする（AI が無いとき）。行・「、」・「・」で区切り、URL や長すぎる行はそのまま
    public static func toChecklist(_ text: String) -> String {
        var out: [String] = []
        for raw in text.components(separatedBy: "\n") {
            let l = raw.trimmingCharacters(in: .whitespaces)
            if l.isEmpty || l.hasPrefix(unchecked) || l.hasPrefix(checked) { out.append(l); continue }
            if l.contains("://") || l.count > 60 { out.append(l); continue }
            let stripped = l.replacingOccurrences(of: #"^(?:[・•\-*●◆■]|\d+[.)、]|\[ ?\])\s*"#, with: "", options: .regularExpression)
            let parts = stripped.count <= 40 && stripped.contains("、") ? stripped.components(separatedBy: "、") : [stripped]
            out += parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.map { unchecked + $0 }
        }
        return out.joined(separator: "\n")
    }

    /// 済んだ項目を消した本文
    public static func clearChecked(_ text: String) -> String {
        text.components(separatedBy: "\n").filter { !$0.hasPrefix(checked) }.joined(separator: "\n")
    }
}

// MARK: Markdown（Obsidian・Notion）

public enum MarkdownExport {
    /// ファイル名に使えない文字を除く
    static func safe(_ s: String) -> String {
        let t = s.replacingOccurrences(of: #"[\\/:*?"<>|#\[\]\n\r\t]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return String((t.isEmpty ? "memo" : t).prefix(60))
    }

    static func yaml(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }

    /// 1 枚の Markdown（先頭に YAML のプロパティ。Obsidian と Notion の読み込みで使える）
    public static func markdown(_ n: Note) -> String {
        var fm = ["---", "title: " + yaml(n.title), "created: " + ISO8601DateFormatter().string(from: n.createdAt)]
        if let u = n.updatedAt { fm.append("updated: " + ISO8601DateFormatter().string(from: u)) }
        if !n.category.isEmpty { fm.append("folder: " + yaml(n.category)) }
        if !n.tags.isEmpty { fm.append("tags: [" + n.tags.map { yaml($0.replacingOccurrences(of: " ", with: "_")) }.joined(separator: ", ") + "]") }
        if let u = n.url { fm.append("source: " + yaml(u)) }
        if n.pinned { fm.append("favorite: true") }
        fm.append("---")
        let body = n.text
            .replacingOccurrences(of: Heuristics.unchecked, with: "- [ ] ")
            .replacingOccurrences(of: Heuristics.checked, with: "- [x] ")
        var parts = [fm.joined(separator: "\n"), "# " + n.title]
        if !n.summary.isEmpty { parts.append("> " + n.summary.replacingOccurrences(of: "\n", with: "\n> ")) }
        parts.append(body)
        if !n.situations.isEmpty { parts.append("**" + L("使う場面", "When it helps") + "**: " + n.situations.joined(separator: "、")) }
        return parts.joined(separator: "\n\n") + "\n"
    }

    /// フォルダごとの .md を入れた zip（秘密のメモ・見本は入れない）
    public static func zip(_ notes: [Note]) -> Data {
        var used = Set<String>()
        var files: [(String, Data)] = []
        for n in notes where !n.example && !n.isLocked {
            let dir = safe(n.category.isEmpty ? Heuristics.otherFolder : n.category)
            var name = "\(dir)/\(safe(n.title)).md", i = 2
            while used.contains(name) { name = "\(dir)/\(safe(n.title)) \(i).md"; i += 1 }
            used.insert(name)
            files.append((name, Data(markdown(n).utf8)))
        }
        return Zip.make(files)
    }
}

/// 圧縮しない zip を作る（Obsidian・Notion・Finder・ファイル App で開ける）
public enum Zip {
    static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    public static func crc32(_ d: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in d { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }

    public static func make(_ files: [(String, Data)]) -> Data {
        var out = Data(), central = Data()
        func u16(_ v: Int, _ d: inout Data) { var x = UInt16(truncatingIfNeeded: v).littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func u32(_ v: UInt32, _ d: inout Data) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        for (name, data) in files {
            let nameData = Data(name.utf8), crc = crc32(data), offset = UInt32(out.count)
            // ローカルヘッダー（UTF-8 の名前: フラグ 0x0800）
            u32(0x0403_4B50, &out); u16(20, &out); u16(0x0800, &out); u16(0, &out); u16(0, &out); u16(0x21, &out)
            u32(crc, &out); u32(UInt32(data.count), &out); u32(UInt32(data.count), &out); u16(nameData.count, &out); u16(0, &out)
            out.append(nameData); out.append(data)
            u32(0x0201_4B50, &central); u16(20, &central); u16(20, &central); u16(0x0800, &central); u16(0, &central); u16(0, &central); u16(0x21, &central)
            u32(crc, &central); u32(UInt32(data.count), &central); u32(UInt32(data.count), &central)
            u16(nameData.count, &central); u16(0, &central); u16(0, &central); u16(0, &central); u16(0, &central); u32(0, &central); u32(offset, &central)
            central.append(nameData)
        }
        let cdOffset = UInt32(out.count)
        out.append(central)
        u32(0x0605_4B50, &out); u16(0, &out); u16(0, &out); u16(files.count, &out); u16(files.count, &out)
        u32(UInt32(central.count), &out); u32(cdOffset, &out); u16(0, &out)
        return out
    }
}

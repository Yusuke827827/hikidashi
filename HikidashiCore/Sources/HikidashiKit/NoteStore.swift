// メモの保存。保存フォルダの notes.json に、Web 版の書き出しと同じ形（{app, version, notes}）で置く。
// そのため notes.json はそのまま Web 版に読み込める。

import Foundation
import Observation

public struct ExportFile: Codable, Sendable {
    public var app: String
    public var version: Int
    public var exportedAt: String?
    public var notes: [Note]

    public init(notes: [Note]) {
        app = "hikidashi"
        version = 1
        exportedAt = ISO8601DateFormatter().string(from: Date())
        self.notes = notes
    }
}

public enum ImportError: Error, Equatable {
    case notHikidashi
}

@Observable
@MainActor
public final class NoteStore {
    /// 新しい順
    public private(set) var notes: [Note] = []
    public let root: URL
    public var fileURL: URL { root.appendingPathComponent("notes.json") }

    public init(root: URL = SharedContainer.root) {
        self.root = root
        reload()
    }

    public func reload() {
        guard let data = try? Data(contentsOf: fileURL), let file = try? JSONDecoder().decode(ExportFile.self, from: data) else {
            notes = []
            return
        }
        notes = file.notes.sorted { $0.createdAt > $1.createdAt }
    }

    private func persist() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? enc.encode(ExportFile(notes: notes)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    public func note(_ id: String) -> Note? { notes.first { $0.id == id } }

    public func add(_ note: Note) {
        notes.insert(note, at: 0)
        notes.sort { $0.createdAt > $1.createdAt }
        persist()
    }

    public func update(_ id: String, _ change: (inout Note) -> Void) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        change(&notes[i])
        persist()
    }

    public func remove(_ id: String) {
        if let img = note(id)?.imageFile {
            try? FileManager.default.removeItem(at: imageURL(img))
        }
        notes.removeAll { $0.id == id }
        persist()
    }

    public func imageURL(_ name: String) -> URL {
        SharedContainer.images(in: root).appendingPathComponent(name)
    }

    /// 使われているフォルダ名（多い順）
    public var folders: [String] {
        var count: [String: Int] = [:]
        for n in notes where !n.category.isEmpty { count[n.category, default: 0] += 1 }
        return count.keys.sorted { (count[$0]!, $1) > (count[$1]!, $0) }
    }

    // MARK: 書き出し・読み込み

    public func exportData() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        // 画像は書き出しに含めない（Web 版では使えないため）
        return try enc.encode(ExportFile(notes: notes.map { var n = $0; n.imageFile = nil; return n }))
    }

    /// 読み込んだ件数を返す。同じ作成日時・タイトルのメモは重複として飛ばす（Web 版と同じ判定）
    @discardableResult
    public func importData(_ data: Data) throws -> Int {
        guard let file = try? JSONDecoder().decode(ExportFile.self, from: data), file.app == "hikidashi" else {
            throw ImportError.notHikidashi
        }
        var seen = Set(notes.map { Self.dedupeKey($0) })
        var added = 0
        for var n in file.notes where !n.text.isEmpty {
            let key = Self.dedupeKey(n)
            if seen.contains(key) { continue }
            seen.insert(key)
            if notes.contains(where: { $0.id == n.id }) { n.id = UUID().uuidString }
            n.imageFile = nil
            notes.append(n)
            added += 1
        }
        notes.sort { $0.createdAt > $1.createdAt }
        persist()
        return added
    }

    static func dedupeKey(_ n: Note) -> String {
        "\(Note.millis(n.createdAt))|\(n.title)"
    }
}

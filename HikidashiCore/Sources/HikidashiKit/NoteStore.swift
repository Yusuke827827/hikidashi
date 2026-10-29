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

/// フォルダの設定（作っただけで空のフォルダ・お気に入り）。保存フォルダの folders.json に置く
public struct FolderInfo: Codable, Hashable, Sendable {
    public var name: String
    public var favorite: Bool
    public var createdAt: Date

    public init(name: String, favorite: Bool = false, createdAt: Date = Date()) {
        self.name = name
        self.favorite = favorite
        self.createdAt = createdAt
    }
}

/// ゴミ箱に入れたメモ（30 日で消える）
public struct TrashedNote: Codable, Hashable, Sendable, Identifiable {
    public var note: Note
    public var deletedAt: Date
    public var id: String { note.id }

    public init(note: Note, deletedAt: Date) {
        self.note = note
        self.deletedAt = deletedAt
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

    /// 変わったメモ（保存・削除）を知らせる。iCloud の同期が使う
    public var onChange: ((_ saved: [String], _ deleted: [String]) -> Void)?

    /// 今日の確認リストでチェックしたメモ（日付 → メモの id）
    public private(set) var checks: [String: [String]] = [:]
    var checksURL: URL { root.appendingPathComponent("checks.json") }

    /// フォルダの設定
    public private(set) var folderInfo: [FolderInfo] = []
    var foldersURL: URL { root.appendingPathComponent("folders.json") }

    public init(root: URL = SharedContainer.root) {
        self.root = root
        reload()
        loadFolders()
        loadTrash()
        checks = (try? JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: checksURL))) ?? [:]
    }

    // MARK: 今日の確認リスト

    public func isChecked(_ id: String, day: String) -> Bool {
        checks[day]?.contains(id) ?? false
    }

    public func toggleCheck(_ id: String, day: String) {
        var list = checks[day] ?? []
        if let i = list.firstIndex(of: id) { list.remove(at: i) } else { list.append(id) }
        checks[day] = list
        // 2 週間より前のチェックは消す
        if let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) {
            let c = Heuristics.dayFormatter.string(from: cutoff)
            checks = checks.filter { $0.key >= c }
        }
        try? JSONEncoder().encode(checks).write(to: checksURL, options: .atomic)
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
        onChange?([note.id], [])
    }

    public func update(_ id: String, _ change: (inout Note) -> Void) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        let before = notes[i]
        change(&notes[i])
        guard notes[i] != before else { return }
        notes[i].updatedAt = Date()
        persist()
        onChange?([id], [])
    }

    /// ゴミ箱へ移す（30 日は元に戻せる。画像やファイルも残す）
    public func remove(_ id: String) {
        guard let n = note(id) else { return }
        trash.insert(TrashedNote(note: n, deletedAt: Date()), at: 0)
        saveTrash()
        notes.removeAll { $0.id == id }
        persist()
        onChange?([], [id])
    }

    // MARK: ゴミ箱

    public private(set) var trash: [TrashedNote] = []
    var trashURL: URL { root.appendingPathComponent("trash.json") }
    public static let trashDays = 30

    /// ゴミ箱から戻す
    public func restore(_ id: String) {
        guard let i = trash.firstIndex(where: { $0.id == id }) else { return }
        var n = trash.remove(at: i).note
        n.updatedAt = Date()
        saveTrash()
        notes.append(n)
        notes.sort { $0.createdAt > $1.createdAt }
        persist()
        onChange?([n.id], [])
    }

    /// ゴミ箱から完全に消す
    public func deleteForever(_ ids: [String]) {
        let set = Set(ids)
        for t in trash where set.contains(t.id) {
            for f in [t.note.imageFile, t.note.file].compactMap({ $0 }) { try? FileManager.default.removeItem(at: imageURL(f)) }
        }
        trash.removeAll { set.contains($0.id) }
        saveTrash()
    }

    public func emptyTrash() { deleteForever(trash.map(\.id)) }

    /// 30 日を過ぎたものを消す（アプリを開くたび）
    public func purgeTrash(now: Date = Date()) {
        let limit = now.addingTimeInterval(-Double(Self.trashDays) * 86400)
        let old = trash.filter { $0.deletedAt < limit }.map(\.id)
        if !old.isEmpty { deleteForever(old) }
    }

    private func loadTrash() {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .millisecondsSince1970
        trash = (try? dec.decode([TrashedNote].self, from: Data(contentsOf: trashURL))) ?? []
    }

    private func saveTrash() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .millisecondsSince1970
        try? enc.encode(trash).write(to: trashURL, options: .atomic)
    }

    public func imageURL(_ name: String) -> URL {
        SharedContainer.images(in: root).appendingPathComponent(name)
    }

    /// フォルダ名（お気に入り → メモの多い順。作っただけの空のフォルダも含む）
    public var folders: [String] {
        let count = folderCounts
        let fav = Set(folderInfo.filter(\.favorite).map(\.name))
        return count.keys.sorted { a, b in
            let fa = fav.contains(a), fb = fav.contains(b)
            if fa != fb { return fa }
            if count[a]! != count[b]! { return count[a]! > count[b]! }
            return a < b
        }
    }

    /// フォルダごとのメモの数（空のフォルダは 0）
    public var folderCounts: [String: Int] {
        var count: [String: Int] = [:]
        for f in folderInfo { count[f.name] = 0 }
        for n in notes where !n.category.isEmpty { count[n.category, default: 0] += 1 }
        return count
    }

    public func isFavoriteFolder(_ name: String) -> Bool {
        folderInfo.contains { $0.name == name && $0.favorite }
    }

    // MARK: フォルダの管理

    /// 空のフォルダを作る。作れたら true
    @discardableResult
    public func createFolder(_ name: String) -> Bool {
        let n = Self.cleanFolderName(name)
        guard !n.isEmpty, folderCounts[n] == nil else { return false }
        folderInfo.append(FolderInfo(name: n))
        saveFolders()
        return true
    }

    public func setFavoriteFolder(_ name: String, _ on: Bool) {
        if let i = folderInfo.firstIndex(where: { $0.name == name }) {
            folderInfo[i].favorite = on
        } else {
            folderInfo.append(FolderInfo(name: name, favorite: on))
        }
        saveFolders()
    }

    /// 名前を変える。同じ名前のフォルダがあれば、そこにまとめる
    public func renameFolder(_ old: String, to new: String) {
        let n = Self.cleanFolderName(new)
        guard !n.isEmpty, n != old else { return }
        let wasFavorite = isFavoriteFolder(old)
        moveNotes(from: [old], to: n)
        folderInfo.removeAll { $0.name == old }
        if folderInfo.contains(where: { $0.name == n }) {
            if wasFavorite { setFavoriteFolder(n, true) }
        } else {
            folderInfo.append(FolderInfo(name: n, favorite: wasFavorite))
        }
        saveFolders()
    }

    /// いくつかのフォルダを 1 つにまとめる
    public func mergeFolders(_ sources: [String], into target: String) {
        let t = Self.cleanFolderName(target)
        guard !t.isEmpty else { return }
        let from = sources.filter { $0 != t }
        guard !from.isEmpty else { return }
        let fav = from.contains { isFavoriteFolder($0) }
        moveNotes(from: from, to: t)
        folderInfo.removeAll { from.contains($0.name) }
        if !folderInfo.contains(where: { $0.name == t }) { folderInfo.append(FolderInfo(name: t, favorite: fav)) }
        saveFolders()
    }

    /// フォルダを消す。中のメモは moveTo（既定は「その他」）へ移す
    public func deleteFolder(_ name: String, moveTo: String = Heuristics.otherFolder) {
        if name != moveTo { moveNotes(from: [name], to: moveTo) }
        folderInfo.removeAll { $0.name == name }
        saveFolders()
    }

    private func moveNotes(from: [String], to: String) {
        let src = Set(from)
        var changed: [String] = []
        let now = Date()
        for i in notes.indices where src.contains(notes[i].category) {
            notes[i].category = to
            notes[i].updatedAt = now
            changed.append(notes[i].id)
        }
        guard !changed.isEmpty else { return }
        persist()
        onChange?(changed, [])
    }

    static func cleanFolderName(_ s: String) -> String {
        String(s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
    }

    private func loadFolders() {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .millisecondsSince1970
        guard let data = try? Data(contentsOf: foldersURL), let list = try? dec.decode([FolderInfo].self, from: data) else {
            folderInfo = []
            return
        }
        folderInfo = list
    }

    private func saveFolders() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .millisecondsSince1970
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(folderInfo) else { return }
        try? data.write(to: foldersURL, options: .atomic)
    }

    // MARK: 書き出し・読み込み

    public func exportData() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        // 画像は書き出しに含めない（Web 版では使えないため）
        return try enc.encode(ExportFile(notes: notes.map { var n = $0; n.imageFile = nil; n.file = nil; return n }))
    }

    /// 読み込んだ件数を返す。同じ作成日時・タイトルのメモは重複として飛ばす（Web 版と同じ判定）
    @discardableResult
    public func importData(_ data: Data) throws -> Int {
        guard let file = try? JSONDecoder().decode(ExportFile.self, from: data), file.app == "hikidashi" else {
            throw ImportError.notHikidashi
        }
        var seen = Set(notes.map { Self.dedupeKey($0) })
        var added = 0
        var addedIDs: [String] = []
        for var n in file.notes where !n.text.isEmpty {
            let key = Self.dedupeKey(n)
            if seen.contains(key) { continue }
            seen.insert(key)
            if notes.contains(where: { $0.id == n.id }) { n.id = UUID().uuidString }
            n.imageFile = nil
            n.file = nil
            notes.append(n)
            addedIDs.append(n.id)
            added += 1
        }
        notes.sort { $0.createdAt > $1.createdAt }
        persist()
        if !addedIDs.isEmpty { onChange?(addedIDs, []) }
        return added
    }

    // MARK: iCloud から届いた変更

    /// 他の端末からの変更を当てはめる。新しい方を残す。画像はこの端末のものを残す。onChange は呼ばない
    public func applyRemote(saved: [Note], deleted: [String]) {
        var changed = false
        for var r in saved {
            if let i = notes.firstIndex(where: { $0.id == r.id }) {
                guard r.modifiedAt > notes[i].modifiedAt else { continue }
                r.imageFile = notes[i].imageFile
                r.file = notes[i].file
                notes[i] = r
            } else {
                r.imageFile = nil
                r.file = nil
                notes.append(r)
            }
            changed = true
        }
        let gone = Set(deleted)
        if notes.contains(where: { gone.contains($0.id) }) {
            for n in notes where gone.contains(n.id) {
                trash.insert(TrashedNote(note: n, deletedAt: Date()), at: 0)
            }
            saveTrash()
            notes.removeAll { gone.contains($0.id) }
            changed = true
        }
        guard changed else { return }
        notes.sort { $0.createdAt > $1.createdAt }
        persist()
    }

    static func dedupeKey(_ n: Note) -> String {
        "\(Note.millis(n.createdAt))|\(n.title)"
    }
}

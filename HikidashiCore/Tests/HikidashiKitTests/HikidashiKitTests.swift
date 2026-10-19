import XCTest
@testable import HikidashiKit

final class NoteTests: XCTestCase {
    /// Web 版の書き出し JSON をそのまま読めること
    func testDecodesWebExport() throws {
        let json = """
        {"app":"hikidashi","version":1,"exportedAt":"2026-10-17T10:00:00.000Z","notes":[
          {"id":"n1abc","text":"シミは叩く","url":null,"title":"シミは叩いて落とす","summary":"外から内へ","category":"暮らし・家事",
           "tags":["シミ抜き"],"situations":["洗濯するとき"],"remindAt":null,"createdAt":1792243484000,"helpful":2,"pinned":true,"lastSeen":1792243500000}
        ]}
        """
        let file = try JSONDecoder().decode(ExportFile.self, from: Data(json.utf8))
        XCTAssertEqual(file.notes.count, 1)
        let n = file.notes[0]
        XCTAssertEqual(n.id, "n1abc")
        XCTAssertEqual(n.title, "シミは叩いて落とす")
        XCTAssertEqual(n.helpful, 2)
        XCTAssertTrue(n.pinned)
        XCTAssertTrue(n.filed, "Web 版のメモは整理済みとして扱う")
        XCTAssertNil(n.url)
        XCTAssertEqual(n.createdAt.timeIntervalSince1970, 1792243484, accuracy: 0.001)
        XCTAssertNotNil(n.lastSeen)
    }

    /// 書き出すと日時がミリ秒の数値になること（Web 版で読めるように）
    func testEncodesMillis() throws {
        let n = Note(id: "x", text: "t", createdAt: Date(timeIntervalSince1970: 1_700_000_000.123))
        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(n)) as! [String: Any]
        XCTAssertEqual(obj["createdAt"] as? Double, 1_700_000_000_123)
    }

    func testValidDay() {
        XCTAssertEqual(Note.validDay("2026-10-20"), "2026-10-20")
        XCTAssertNil(Note.validDay(""))
        XCTAssertNil(Note.validDay("10/20"))
        XCTAssertNil(Note.validDay(nil))
    }
}

@MainActor
final class StoreTests: XCTestCase {
    /// テストごとに空の保存フォルダを作る
    func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hikidashi-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func testPersistsAndReloads() throws {
        let root = try makeRoot()
        let store = NoteStore(root: root)
        store.add(Note(text: "a", title: "A", category: "X"))
        store.add(Note(text: "b", title: "B", category: "X"))
        store.add(Note(text: "c", title: "C", category: "Y"))
        XCTAssertEqual(NoteStore(root: root).notes.count, 3)
        XCTAssertEqual(store.folders, ["X", "Y"])
    }

    func testImportSkipsDuplicates() throws {
        let root = try makeRoot()
        let store = NoteStore(root: root)
        let data = try store.exportData()
        XCTAssertEqual(try store.importData(data), 0)
        store.add(Note(text: "a", title: "A"))
        let one = try store.exportData()
        XCTAssertEqual(try store.importData(one), 0, "同じメモは二重に入らない")
        XCTAssertThrowsError(try store.importData(Data("{}".utf8)))
    }

    func testInboxToNotes() throws {
        let root = try makeRoot()
        try Inbox.put(text: "ポイントは月末に失効する", url: "https://x.com/a/status/1", comment: "要チェック", image: Data([0xFF, 0xD8]), root: root)
        let store = NoteStore(root: root)
        let lib = Librarian(store: store, keyProvider: { nil })
        XCTAssertEqual(lib.ingestInbox(), 1)
        let n = try XCTUnwrap(store.notes.first)
        XCTAssertEqual(n.text, "要チェック\n\nポイントは月末に失効する")
        XCTAssertEqual(n.url, "https://x.com/a/status/1")
        XCTAssertFalse(n.filed)
        XCTAssertFalse(n.category.isEmpty, "API キーが無くても簡易の整理でフォルダに入る")
        let img = try XCTUnwrap(n.imageFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.imageURL(img).path))
        XCTAssertEqual(lib.ingestInbox(), 0, "取り出したものは消える")
    }

    func testKeywordRecallWithoutKey() async throws {
        let root = try makeRoot()
        let store = NoteStore(root: root)
        let lib = Librarian(store: store, keyProvider: { nil })
        lib.addExamples()
        let r = await lib.recall(AppLanguage.current == .ja ? "洗濯" : "laundry")
        XCTAssertTrue(r.keywordOnly)
        XCTAssertFalse(r.noteIDs.isEmpty)
    }
}

final class HeuristicsTests: XCTestCase {
    func testFolder() {
        XCTAssertEqual(Heuristics.folder(for: "洗濯物のシミ", language: .ja), "暮らし・家事")
        XCTAssertEqual(Heuristics.folder(for: "Cheap flight trick", language: .en), "Travel")
    }

    func testTitleIsFirstSentence() {
        XCTAssertEqual(Heuristics.title(for: "最初の文。次の文"), "最初の文")
    }

    func testRelated() {
        let a = Note(text: "", title: "a", category: "家事", tags: ["洗濯"])
        let b = Note(text: "", title: "b", category: "家事", tags: ["洗濯"])
        let c = Note(text: "", title: "c", category: "お金", tags: ["税"])
        XCTAssertEqual(Heuristics.related(to: a, in: [a, b, c]).map(\.title), ["b"])
    }

    func testUpcoming() {
        let now = Heuristics.dayFormatter.date(from: "2026-10-17")!
        let soon = Note(text: "", title: "soon", remindAt: "2026-10-20")
        let far = Note(text: "", title: "far", remindAt: "2026-12-01")
        XCTAssertEqual(Heuristics.upcoming([far, soon], now: now).map(\.title), ["soon"])
    }

    func testReminderSchedule() {
        // 10/17 の 10 時。当日 9 時はもう過ぎている
        let now = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Heuristics.dayFormatter.date(from: "2026-10-17")!)!
        let past = Note(text: "", title: "today", remindAt: "2026-10-17")
        let later = Note(text: "", title: "later", remindAt: "2026-12-01")
        let next = Note(text: "", title: "next", remindAt: "2026-10-18")
        let none = Note(text: "", title: "none")
        let plan = Heuristics.reminderSchedule([later, past, none, next], now: now)
        XCTAssertEqual(plan.map(\.note.title), ["next", "later"])
        XCTAssertEqual(Calendar.current.component(.hour, from: plan[0].fireAt), 9)
        XCTAssertEqual(Heuristics.reminderSchedule([later, next], now: now, limit: 1).map(\.note.title), ["next"])
    }
}

final class ClaudeClientTests: XCTestCase {
    func testRequestShape() throws {
        let client = ClaudeClient(apiKey: "sk-test")
        let req = try client.request(prompt: "hi", schema: Prompts.recallSchema, images: [.init(data: Data([1, 2, 3]))], effort: .low, maxTokens: 100)
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "sk-test")
        XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(req.httpBody)) as! [String: Any]
        XCTAssertEqual(body["model"] as? String, "claude-opus-5-5")
        XCTAssertEqual(body["fallbacks"] as? String, "default")
        let output = body["output_config"] as! [String: Any]
        XCTAssertEqual(output["effort"] as? String, "low")
        XCTAssertEqual((output["format"] as! [String: Any])["type"] as? String, "json_schema")
        let content = ((body["messages"] as! [[String: Any]])[0]["content"]) as! [[String: Any]]
        XCTAssertEqual(content.map { $0["type"] as? String }, ["image", "text"])
    }

    func testParsesTextBlockAfterThinking() throws {
        let json = """
        {"stop_reason":"end_turn","content":[{"type":"thinking","thinking":""},{"type":"text","text":"{\\"answer\\":\\"ok\\",\\"ids\\":[\\"a\\"]}"}]}
        """
        let r = try ClaudeClient.parse(RecallResult.self, data: Data(json.utf8), status: 200)
        XCTAssertEqual(r, RecallResult(answer: "ok", ids: ["a"]))
    }

    func testErrors() {
        XCTAssertThrowsError(try ClaudeClient.parse(RecallResult.self, data: Data("{}".utf8), status: 401)) {
            XCTAssertEqual($0 as? ClaudeError, .invalidKey)
        }
        XCTAssertThrowsError(try ClaudeClient.parse(RecallResult.self, data: Data(#"{"stop_reason":"refusal","content":[]}"#.utf8), status: 200)) {
            XCTAssertEqual($0 as? ClaudeError, .refused)
        }
    }

    func testApplyFiling() {
        var n = Note(text: "orig")
        n.apply(FilingResult(text: "from image", title: "T", summary: "S", category: "C", tags: ["a"], situations: ["b"], remindAt: "bad"), replaceText: false)
        XCTAssertEqual(n.text, "orig")
        XCTAssertNil(n.remindAt)
        XCTAssertTrue(n.filed)
        n.apply(FilingResult(text: "from image", title: "T", summary: "S", category: "C", tags: [], situations: [], remindAt: "2026-11-01"), replaceText: true)
        XCTAssertEqual(n.text, "from image")
        XCTAssertEqual(n.remindAt, "2026-11-01")
    }
}

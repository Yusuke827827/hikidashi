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
        let lib = Librarian(store: store, credentialProvider: { nil }, onDevice: nil)
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
        let lib = Librarian(store: store, credentialProvider: { nil }, onDevice: nil)
        lib.addExamples()
        let r = await lib.recall(AppLanguage.current == .ja ? "洗濯" : "laundry")
        XCTAssertTrue(r.keywordOnly)
        XCTAssertFalse(r.noteIDs.isEmpty)
    }
}

/// iPhone の中の AI の代わり
struct FakeAI: NoteAI {
    var readsImages: Bool { false }
    func file(_ note: Note, folders: [String], image: ClaudeClient.Image?, today: String, language: AppLanguage) async throws -> FilingResult {
        XCTAssertNil(image, "文字を読めない AI には画像を渡さない")
        return FilingResult(text: "", title: "AI title", summary: "AI summary", category: "AI folder", tags: ["t"], situations: ["s"], remindAt: "")
    }
    func recall(_ query: String, notes: [Note], today: String, language: AppLanguage) async throws -> RecallResult {
        RecallResult(answer: "advice", ids: [notes[0].id])
    }
}

@MainActor
final class OnDeviceTests: XCTestCase {
    func makeStore() throws -> NoteStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hikidashi-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return NoteStore(root: root)
    }

    func testUsesOnDeviceAIWithoutKey() async throws {
        let store = try makeStore()
        let lib = Librarian(store: store, credentialProvider: { nil }, onDevice: FakeAI())
        XCTAssertEqual(lib.aiKind, .onDevice)
        let note = lib.save(text: "元の本文", url: nil, image: Data([0xFF, 0xD8]))
        await lib.file(note.id)
        let n = try XCTUnwrap(store.note(note.id))
        XCTAssertEqual(n.title, "AI title")
        XCTAssertEqual(n.category, "AI folder")
        XCTAssertEqual(n.text, "元の本文", "本文はそのまま")
        XCTAssertTrue(n.filed)
        let r = await lib.recall("なにか")
        XCTAssertFalse(r.keywordOnly)
        XCTAssertEqual(r.answer, "advice")
    }

    func testSkipsScreenshotOnlyNotes() async throws {
        let store = try makeStore()
        let lib = Librarian(store: store, credentialProvider: { nil }, onDevice: FakeAI())
        let note = lib.save(text: "", url: nil, image: Data([0xFF, 0xD8]))
        await lib.file(note.id)
        XCTAssertFalse(try XCTUnwrap(store.note(note.id)).filed, "スクショだけのメモは Claude を待つ")
    }

    func testClaudeComesFirst() {
        let lib = Librarian(store: NoteStore(root: FileManager.default.temporaryDirectory), credentialProvider: { .apiKey("sk") }, onDevice: FakeAI())
        XCTAssertEqual(lib.aiKind, .claude)
        XCTAssertEqual(Librarian(store: lib.store, credentialProvider: { nil }, onDevice: nil).aiKind, .none)
    }

    func testRecallPoolAndNumbers() {
        let notes = (0..<60).map { i in Note(id: "n\(i)", text: "", title: i == 59 ? "洗濯のコツ" : "メモ\(i)", createdAt: Date(timeIntervalSince1970: Double(i))) }
        let pool = OnDeviceAI.recallPool(notes, query: "洗濯")
        XCTAssertEqual(pool.count, OnDeviceAI.recallPoolSize)
        XCTAssertEqual(pool.first?.id, "n59", "キーワードが近いものが先")
        XCTAssertEqual(OnDeviceAI.ids(from: [1, 1, 0, 99, 2], pool: pool), ["n59", pool[1].id])
        XCTAssertTrue(OnDeviceAI.recallList(Array(pool.prefix(2))).hasPrefix("1. 洗濯のコツ"))
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

    /// 購読者は API キーを送らず、購読の証明を付けて中継サーバーに送る
    func testSubscriptionRequest() throws {
        let server = URL(string: "https://mindrawer.example.workers.dev")!
        let client = ClaudeClient(credential: .subscription(server: server, transaction: "jws-token"))
        let req = try client.request(prompt: "hi", schema: Prompts.recallSchema, effort: .low, maxTokens: 100)
        XCTAssertEqual(req.url?.absoluteString, "https://mindrawer.example.workers.dev/v1/messages")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-mindrawer-transaction"), "jws-token")
        XCTAssertNil(req.value(forHTTPHeaderField: "x-api-key"))
    }

    func testSubscriptionErrors() {
        let limit = Data(#"{"type":"error","error":{"type":"rate_limit_error","message":"Monthly limit reached"}}"#.utf8)
        XCTAssertThrowsError(try ClaudeClient.parse(RecallResult.self, data: limit, status: 429, subscription: true)) {
            XCTAssertEqual($0 as? ClaudeError, .monthlyLimit)
        }
        XCTAssertThrowsError(try ClaudeClient.parse(RecallResult.self, data: Data("{}".utf8), status: 403, subscription: true)) {
            XCTAssertEqual($0 as? ClaudeError, .subscriptionInvalid)
        }
        XCTAssertThrowsError(try ClaudeClient.parse(RecallResult.self, data: Data("{}".utf8), status: 429, subscription: true)) {
            XCTAssertEqual($0 as? ClaudeError, .busy)
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

final class LinkPreviewTests: XCTestCase {
    func testParsesOpenGraph() {
        let html = """
        <html><head><title>ignored</title>
        <meta property="og:title" content="洗濯 &amp; シミ抜きのコツ">
        <meta content="叩いて落とす。" name="description">
        </head></html>
        """
        let p = LinkFetcher.parse(html: html)
        XCTAssertEqual(p, LinkPreview(title: "洗濯 & シミ抜きのコツ", description: "叩いて落とす。"))
        XCTAssertEqual(LinkFetcher.parse(html: "<title> Only  title </title>")?.title, "Only title")
        XCTAssertNil(LinkFetcher.parse(html: "<html></html>"))
    }

    func testMergeOnce() {
        let p = LinkPreview(title: "T", description: "D")
        let once = LinkFetcher.merge("メモ", p)
        XCTAssertEqual(once, "メモ\n\n\(LinkFetcher.marker)T\nD")
        XCTAssertEqual(LinkFetcher.merge(once, p), once, "二度は足さない")
        XCTAssertEqual(LinkFetcher.merge("", p), LinkFetcher.marker + "T\nD")
    }

    @MainActor
    func testLibrarianAddsLinkTextBeforeFiling() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hikidashi-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = NoteStore(root: root)
        let lib = Librarian(store: store, credentialProvider: { nil }, onDevice: FakeAI(),
                            linkFetcher: { _ in LinkPreview(title: "ページの題", description: "説明") })
        let note = lib.save(text: "", url: "https://example.com/a", image: nil)
        await lib.file(note.id)
        let n = try XCTUnwrap(store.note(note.id))
        XCTAssertTrue(n.text.contains("ページの題"))
        XCTAssertTrue(n.filed, "リンク先の文があれば、文字だけの AI でも整理できる")
    }
}

final class EventHintTests: XCTestCase {
    func testPlansEveningBefore() {
        let cal = Calendar.current
        let now = cal.date(bySettingHour: 10, minute: 0, second: 0, of: Heuristics.dayFormatter.date(from: "2026-10-20")!)!
        let trip = EventInfo(id: "e1", title: "大阪出張", start: cal.date(bySettingHour: 9, minute: 0, second: 0, of: Heuristics.dayFormatter.date(from: "2026-10-22")!)!)
        let soon = EventInfo(id: "e2", title: "プレゼン", start: now.addingTimeInterval(5 * 3600))
        let none = EventInfo(id: "e3", title: "歯医者", start: now.addingTimeInterval(30 * 3600))
        let notes = [
            Note(text: "", title: "服は 1 日ずつ袋に", situations: ["出張の準備"]),
            Note(text: "", title: "最初の 30 秒を暗記", situations: ["プレゼン前"]),
        ]
        let plan = EventHints.plan(events: [none, soon, trip], notes: notes, now: now)
        XCTAssertEqual(plan.map(\.event.id), ["e2", "e1"])
        XCTAssertEqual(plan[0].fireAt, soon.start.addingTimeInterval(-2 * 3600), "前の日の夜が過ぎていれば 2 時間前")
        XCTAssertEqual(cal.component(.hour, from: plan[1].fireAt), 20)
        XCTAssertEqual(cal.component(.day, from: plan[1].fireAt), 21)
        XCTAssertEqual(plan[1].notes.map(\.title), ["服は 1 日ずつ袋に"])
    }
}

@MainActor
final class SyncAndPlaceTests: XCTestCase {
    func makeStore() throws -> NoteStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hikidashi-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return NoteStore(root: root)
    }

    func testPlaceAndUpdatedAtRoundTrip() throws {
        var n = Note(text: "t", title: "T", place: Place(name: "スーパー", latitude: 35.1, longitude: 139.2))
        n.updatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let back = try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(n))
        XCTAssertEqual(back.place, n.place)
        XCTAssertEqual(back.updatedAt, n.updatedAt)
        XCTAssertEqual(back.modifiedAt, n.updatedAt)
    }

    func testOnChangeAndUpdatedAt() throws {
        let store = try makeStore()
        var log: [(saved: [String], deleted: [String])] = []
        store.onChange = { log.append((saved: $0, deleted: $1)) }
        store.add(Note(id: "a", text: "x"))
        XCTAssertNil(store.note("a")?.updatedAt)
        store.update("a") { $0.title = "new" }
        XCTAssertNotNil(store.note("a")?.updatedAt)
        store.update("a") { $0.title = "new" }
        store.remove("a")
        XCTAssertEqual(log.map(\.saved), [["a"], ["a"], []], "変わらない更新は知らせない")
        XCTAssertEqual(log.last?.deleted, ["a"])
    }

    func testApplyRemoteKeepsNewer() throws {
        let store = try makeStore()
        var calls = 0
        store.add(Note(id: "a", text: "local", createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 200)))
        store.add(Note(id: "b", text: "gone"))
        store.onChange = { _, _ in calls += 1 }
        let older = Note(id: "a", text: "older", createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 150))
        let newer = Note(id: "c", text: "from iPad")
        store.applyRemote(saved: [older, newer], deleted: ["b"])
        XCTAssertEqual(store.note("a")?.text, "local", "古い方は無視")
        XCTAssertEqual(store.note("c")?.text, "from iPad")
        XCTAssertNil(store.note("b"))
        let newest = Note(id: "a", text: "newest", createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 300))
        store.applyRemote(saved: [newest], deleted: [])
        XCTAssertEqual(store.note("a")?.text, "newest")
        XCTAssertEqual(calls, 0, "届いた変更は送り返さない")
        XCTAssertEqual(NoteStore(root: store.root).notes.count, 2, "保存される")
    }

    func testPlaceNotesLimit() {
        let notes = (0..<20).map { i in Note(id: "\(i)", text: "", pinned: i == 3, place: Place(name: "p", latitude: 0, longitude: 0)) } + [Note(text: "none")]
        let picked = Heuristics.placeNotes(notes)
        XCTAssertEqual(picked.count, 15)
        XCTAssertEqual(picked.first?.id, "3", "ピン留めが先")
    }
}

@MainActor
final class FolderAndAttachmentTests: XCTestCase {
    func makeStore() throws -> NoteStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hikidashi-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return NoteStore(root: root)
    }

    func testFolderManagement() throws {
        let store = try makeStore()
        store.add(Note(id: "1", text: "a", category: "お金"))
        store.add(Note(id: "2", text: "b", category: "お金・節約"))
        store.add(Note(id: "3", text: "c", category: "お金・節約"))
        XCTAssertTrue(store.createFolder("レシピ"))
        XCTAssertFalse(store.createFolder("お金"), "同じ名前は作らない")
        XCTAssertEqual(store.folderCounts["レシピ"], 0)
        store.setFavoriteFolder("レシピ", true)
        XCTAssertEqual(store.folders.first, "レシピ", "お気に入りが先")

        store.mergeFolders(["お金"], into: "お金・節約")
        XCTAssertEqual(store.note("1")?.category, "お金・節約")
        XCTAssertNil(store.folderCounts["お金"])

        store.renameFolder("レシピ", to: "料理")
        XCTAssertTrue(store.isFavoriteFolder("料理"), "お気に入りは引き継ぐ")
        XCTAssertNil(store.folderCounts["レシピ"])

        store.deleteFolder("お金・節約")
        XCTAssertEqual(store.note("2")?.category, Heuristics.otherFolder)

        let again = NoteStore(root: store.root)
        XCTAssertTrue(again.isFavoriteFolder("料理"), "保存される")
    }

    func testMergeSuggestions() {
        let notes = [
            Note(text: "", category: "お金・節約"), Note(text: "", category: "お金・節約"), Note(text: "", category: "お金"),
            Note(text: "", category: "料理", tags: ["レシピ", "時短", "作り置き"]),
            Note(text: "", category: "ごはん", tags: ["レシピ", "時短", "作り置き"]),
            Note(text: "", category: "旅行"),
        ]
        let folders = ["お金・節約", "お金", "料理", "ごはん", "旅行"]
        let all = Heuristics.folderMergeSuggestions(notes, folders: folders, limit: 5)
        XCTAssertTrue(all.contains(FolderMergeSuggestion(from: "お金", into: "お金・節約")))
        XCTAssertTrue(all.contains { Set([$0.from, $0.into]) == Set(["料理", "ごはん"]) }, "タグが重なるフォルダ")
        XCTAssertFalse(all.contains { $0.from == "旅行" || $0.into == "旅行" })
        let key = FolderMergeSuggestion(from: "お金", into: "お金・節約").key
        XCTAssertFalse(Heuristics.folderMergeSuggestions(notes, folders: folders, dismissed: [key], limit: 5).contains { $0.key == key })
    }

    func testExtractorHelpers() {
        XCTAssertEqual(TextExtractor.kind(ofExtension: "PDF"), .pdf)
        XCTAssertEqual(TextExtractor.kind(ofExtension: "heic"), .image)
        XCTAssertEqual(TextExtractor.kind(ofExtension: "md"), .text)
        let once = TextExtractor.merge("", extracted: "読んだ文字", marker: TextExtractor.fileMarker)
        XCTAssertEqual(once, TextExtractor.fileMarker + "読んだ文字")
        XCTAssertEqual(TextExtractor.merge(once, extracted: "別", marker: TextExtractor.fileMarker), once)
    }

    func testTextFileExtraction() async {
        let t = await TextExtractor.text(fromFile: Data("買い物リスト\n牛乳".utf8), extension: "txt")
        XCTAssertEqual(t, "買い物リスト\n牛乳")
    }

    func testAttachmentIsReadWithoutAI() async throws {
        let store = try makeStore()
        let lib = Librarian(store: store, credentialProvider: { nil }, onDevice: nil, linkFetcher: { _ in nil },
                            textExtractor: { _, ext in ext == "pdf" ? "請求書 10月分 支払期限 11/30" : nil })
        let note = lib.save(text: "", url: nil, image: nil, file: (data: Data("%PDF".utf8), name: "請求書.pdf"))
        XCTAssertEqual(note.fileTitle, "請求書.pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.imageURL(try XCTUnwrap(note.file)).path))
        await lib.fileAll()
        let n = try XCTUnwrap(store.note(note.id))
        XCTAssertTrue(n.text.contains("支払期限"))
        XCTAssertTrue(n.enriched)
        XCTAssertTrue(n.title.contains("請求書"), "AI が無くても取り出した文字でタイトルを付ける")
    }

    func testInboxCarriesFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hikidashi-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Inbox.put(text: "", url: nil, comment: "", image: nil, file: (data: Data("hello".utf8), name: "memo.txt"), root: root)
        let items = Inbox.drain(root: root)
        let f = try XCTUnwrap(items.first?.file)
        XCTAssertEqual(items.first?.fileTitle, "memo.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: SharedContainer.images(in: root).appendingPathComponent(f).path))
    }
}

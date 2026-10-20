import XCTest
@testable import Clipshot

final class HistoryStoreTests: XCTestCase {
    private var store: HistoryStore!

    override func setUpWithError() throws {
        store = try HistoryStore.inMemory()
    }

    override func tearDown() {
        store = nil
    }

    func testInsertAndFetch() throws {
        let outcome = try store.insert(
            kind: .text,
            text: "Hello world",
            sourceApp: "Notes",
            bundleId: "com.apple.Notes",
            hash: "hash-hello"
        )

        XCTAssertTrue(outcome.wasInserted)
        XCTAssertNotNil(outcome.item.id)
        XCTAssertEqual(outcome.item.text, "Hello world")

        let recent = try store.recent()
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first?.text, "Hello world")
        XCTAssertEqual(try store.itemCount(), 1)
    }

    func testDeduplicatesByHashAndBumpsTimestamp() throws {
        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        let first = try store.insert(
            kind: .text,
            text: "Duplicate me",
            hash: "same-hash",
            now: firstDate
        )

        let secondDate = firstDate.addingTimeInterval(120)
        let second = try store.insert(
            kind: .text,
            text: "Duplicate me",
            sourceApp: "Safari",
            bundleId: "com.apple.Safari",
            hash: "same-hash",
            now: secondDate
        )

        XCTAssertFalse(second.wasInserted)
        XCTAssertEqual(first.item.id, second.item.id)
        XCTAssertEqual(try store.itemCount(), 1)
        XCTAssertEqual(second.item.sourceApp, "Safari")
        XCTAssertEqual(second.item.createdAt.timeIntervalSince1970, secondDate.timeIntervalSince1970, accuracy: 0.001)
    }

    func testFullTextSearchSupportsPrefixes() throws {
        _ = try store.insert(kind: .text, text: "Hello world from Clipshot", hash: "1")
        _ = try store.insert(kind: .text, text: "Goodbye moon", hash: "2")
        _ = try store.insert(kind: .url, text: "https://medium.com/design-systems", hash: "3")

        XCTAssertEqual(try store.search("hell").first?.hash, "1")
        XCTAssertEqual(try store.search("clipshot").first?.hash, "1")
        XCTAssertEqual(try store.search("medium").first?.hash, "3")
        XCTAssertTrue(try store.search("nonexistentterm").isEmpty)
    }

    func testSearchHandlesPunctuationAndQuotesSafely() throws {
        _ = try store.insert(kind: .text, text: "Exception: 100% \"handled\"", hash: "punct")

        XCTAssertEqual(try store.search("exception").count, 1)
        XCTAssertEqual(try store.search("\"handled\" !!!").count, 1)
        XCTAssertEqual(try store.search("%").count, 1)
        XCTAssertNoThrow(try store.search("(unclosed OR"))
    }

    func testSearchFiltersByKindAndBundle() throws {
        _ = try store.insert(
            kind: .url,
            text: "https://example.com",
            bundleId: "com.apple.Safari",
            hash: "url-1"
        )
        _ = try store.insert(
            kind: .text,
            text: "https://not-a-link-field",
            bundleId: "com.apple.Notes",
            hash: "text-1"
        )

        XCTAssertEqual(try store.search("", kind: .url).count, 1)
        XCTAssertEqual(try store.search("", bundleId: "com.apple.Notes").count, 1)
        XCTAssertEqual(try store.search("example", kind: .url).count, 1)
        XCTAssertEqual(try store.search("example", kind: .text).count, 0)
    }

    func testRetentionPurgesOldUnpinnedItems() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let old = now.addingTimeInterval(-10 * 86_400)
        let recent = now.addingTimeInterval(-1 * 86_400)

        let oldItem = try store.insert(kind: .text, text: "old", hash: "old", now: old)
        _ = try store.insert(kind: .text, text: "recent", hash: "recent", now: recent)
        let pinned = try store.insert(kind: .text, text: "pinned", hash: "pinned", now: old)
        try store.setPinned(true, for: pinned.item.id!)

        XCTAssertEqual(try store.applyRetention(days: 7, now: now), 1)
        let remaining = try store.recent()
        XCTAssertEqual(remaining.count, 2)
        XCTAssertFalse(remaining.contains { $0.id == oldItem.item.id })
        XCTAssertTrue(remaining.contains { $0.hash == "pinned" })
    }

    func testRetentionZeroKeepsEverything() throws {
        let old = Date(timeIntervalSince1970: 1_000_000)
        _ = try store.insert(kind: .text, text: "ancient", hash: "ancient", now: old)
        XCTAssertEqual(try store.applyRetention(days: 0), 0)
        XCTAssertEqual(try store.itemCount(), 1)
    }

    func testPinboardsAndMembership() throws {
        let item = try store.insert(kind: .text, text: "Pin me", hash: "pinme")
        let board = try store.createPinboard(name: "Design", colorHex: "#FF9F0A")
        XCTAssertNotNil(board.id)

        try store.addItem(item.item.id!, toPinboard: board.id!)
        let members = try store.items(inPinboard: board.id!)
        XCTAssertEqual(members.count, 1)
        XCTAssertTrue(members[0].isPinned)

        XCTAssertEqual(try store.pinboards().count, 1)

        try store.deletePinboard(id: board.id!)
        let updated = try store.item(id: item.item.id!)
        XCTAssertNil(updated?.pinboardId)
        XCTAssertTrue(try store.pinboards().isEmpty)
    }

    func testShortLinkCacheRoundTrip() throws {
        let link = ShortLink(
            id: "bit.ly/abc123",
            shortUrl: "https://bit.ly/abc123",
            destinationUrl: "https://example.com/article",
            slug: "abc123",
            domain: "bit.ly",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            backendId: "bitly",
            tags: ["work", "news"]
        )

        try store.saveShortLink(link)
        let cached = try store.cachedShortLinks()
        XCTAssertEqual(cached.count, 1)
        XCTAssertEqual(cached.first?.shortUrl, link.shortUrl)
        XCTAssertEqual(cached.first?.tags, ["work", "news"])

        XCTAssertEqual(try store.shortLink(withShortURL: link.shortUrl)?.id, link.id)

        try store.updateShortLinkClickCount(id: link.id, clickCount: 42)
        XCTAssertEqual(try store.cachedShortLinks().first?.clickCount, 42)

        try store.deleteShortLink(id: link.id)
        XCTAssertTrue(try store.cachedShortLinks().isEmpty)
    }

    func testRulesAreSortedAndFiltered() throws {
        var low = ShortenRule(name: "Low", priority: 10)
        var high = ShortenRule(name: "High", priority: 1)
        var disabled = ShortenRule(name: "Off", isEnabled: false, priority: 0)
        low = try store.saveShortenRule(low)
        high = try store.saveShortenRule(high)
        disabled = try store.saveShortenRule(disabled)

        let all = try store.shortenRules()
        XCTAssertEqual(all.map(\.name), ["Off", "High", "Low"])

        let enabled = try store.enabledShortenRules()
        XCTAssertEqual(enabled.map(\.name), ["High", "Low"])

        try store.deleteShortenRule(id: high.id!)
        XCTAssertEqual(try store.shortenRules().count, 2)
    }

    func testUpdateAndDeleteItem() throws {
        let inserted = try store.insert(kind: .text, text: "before", hash: "edit")
        try store.updateText("after", title: "Titled", for: inserted.item.id!)
        try store.rename("Renamed", for: inserted.item.id!)

        let updated = try store.item(id: inserted.item.id!)
        XCTAssertEqual(updated?.text, "after")
        XCTAssertEqual(updated?.title, "Renamed")
        XCTAssertEqual(try store.search("after").count, 1)
        XCTAssertEqual(try store.search("before").count, 0)

        try store.deleteItem(id: inserted.item.id!)
        XCTAssertNil(try store.item(id: inserted.item.id!))
        XCTAssertEqual(try store.search("after").count, 0)
    }

    func testFTSQuerySanitizer() {
        XCTAssertEqual(FTSQuery.make(from: "hello world"), "\"hello\"* AND \"world\"*")
        XCTAssertEqual(FTSQuery.make(from: "  "), "")
        XCTAssertEqual(FTSQuery.make(from: "one, two!"), "\"one\"* AND \"two\"*")
        XCTAssertEqual(FTSQuery.make(from: "\"quoted\""), "\"quoted\"*")
    }

    func testColorItemTextRemainsSearchable() throws {
        _ = try store.insert(kind: .color, text: "#a51a15", hash: "color-search")

        let results = try store.search("a51a15")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.kind, .color)
        XCTAssertEqual(results.first?.text, "#a51a15")
    }

    func testFileDatabaseUsesWALAndBusyTimeout() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipshotDBTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try HistoryStore(path: directory.appendingPathComponent("test.sqlite").path)
        let journalMode = try store.dbQueue.read { db in
            try String.fetchOne(db, sql: "PRAGMA journal_mode")
        }
        let busyTimeout = try store.dbQueue.read { db in
            try Int.fetchOne(db, sql: "PRAGMA busy_timeout")
        }

        XCTAssertEqual(journalMode?.lowercased(), "wal")
        XCTAssertEqual(busyTimeout, 5000)
    }
}

import XCTest
@testable import Clipshot

final class MCPToolRouterTests: XCTestCase {
    private struct UnexpectedOutcome: Error {}

    private var store: HistoryStore!
    private var router: MCPToolRouter!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        store = try HistoryStore.inMemory()
        router = MCPToolRouter(store: store)
    }

    override func tearDown() {
        router = nil
        store = nil
    }

    // MARK: - Helpers

    private func call(_ name: String, _ arguments: [String: JSONValue] = [:]) -> MCPToolOutcome {
        router.call(name, arguments: arguments)
    }

    private func success(
        _ outcome: MCPToolOutcome,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> JSONValue {
        guard case .success(let value) = outcome else {
            XCTFail("Expected success, got \(outcome)", file: file, line: line)
            throw UnexpectedOutcome()
        }
        return value
    }

    private func failure(
        _ outcome: MCPToolOutcome,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        guard case .failure(let message) = outcome else {
            XCTFail("Expected failure, got \(outcome)", file: file, line: line)
            throw UnexpectedOutcome()
        }
        return message
    }

    private func items(_ value: JSONValue) throws -> [JSONValue] {
        try XCTUnwrap(value["items"]?.arrayValue)
    }

    // MARK: - Tool catalogue

    func testExposesExactlyTheSixV1Tools() {
        XCTAssertEqual(
            router.tools.map(\.name),
            [
                "search_history",
                "get_item",
                "list_pinboards",
                "get_pinboard_items",
                "create_pinboard",
                "add_item_to_pinboard",
            ]
        )

        for tool in router.tools {
            XCTAssertEqual(tool.inputSchema["type"]?.stringValue, "object", tool.name)
            XCTAssertNotNil(tool.inputSchema["properties"]?.objectValue, tool.name)
        }
    }

    // MARK: - search_history

    func testSearchHistoryReturnsRealStoreItems() throws {
        let inserted = try store.insert(
            kind: .text,
            text: "Hello world from Clipshot",
            sourceApp: "Notes",
            bundleId: "com.apple.Notes",
            hash: "mcp-hello",
            now: now
        ).item
        _ = try store.insert(kind: .text, text: "Goodbye moon", hash: "mcp-goodbye", now: now)

        let payload = try success(call("search_history", ["query": .string("hello")]))
        let results = try items(payload)

        XCTAssertEqual(payload["count"]?.int64Value, 1)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0]["id"]?.int64Value, inserted.id)
        XCTAssertEqual(results[0]["text"]?.stringValue, "Hello world from Clipshot")
        XCTAssertEqual(results[0]["kind"]?.stringValue, "text")
        XCTAssertEqual(results[0]["sourceApp"]?.stringValue, "Notes")
        XCTAssertNotNil(results[0]["createdAt"]?.stringValue)
        XCTAssertEqual(results[0]["isPinned"]?.boolValue, false)
    }

    func testSearchHistoryNeverReturnsDataPath() throws {
        let image = try store.insert(
            kind: .image,
            text: nil,
            title: "Screenshot",
            dataPath: "/Users/secret/Library/Clipshot/payload.png",
            hash: "mcp-image",
            now: now
        ).item

        let searchPayload = try success(call("search_history", ["query": .string("")]))
        let fetched = try success(call("get_item", ["id": .number(Double(try XCTUnwrap(image.id)))]))

        for payload in [searchPayload, fetched] {
            let encoded = String(data: payload.data(), encoding: .utf8) ?? ""
            XCTAssertFalse(encoded.contains("dataPath"))
            XCTAssertFalse(encoded.contains("payload.png"))
            XCTAssertFalse(encoded.contains("/Users/secret"))
        }
    }

    func testSearchHistoryKindArgumentComposesWithPowerSyntax() throws {
        let url = try store.insert(
            kind: .url,
            text: "https://example.com/article",
            hash: "mcp-url",
            now: now
        ).item
        _ = try store.insert(kind: .text, text: "kind:url notes", hash: "mcp-text", now: now)

        // Contradictory kind: argument + typed clause intersect to nothing.
        let conflict = try success(call("search_history", [
            "query": .string("kind:text"),
            "kind": .string("url"),
        ]))
        XCTAssertEqual(conflict["count"]?.int64Value, 0)

        // Agreement narrows normally.
        let agreed = try success(call("search_history", [
            "query": .string("kind:url"),
            "kind": .string("url"),
        ]))
        XCTAssertEqual(try items(agreed).map { $0["id"]?.int64Value }, [url.id])

        // Argument alone filters.
        let kindOnly = try success(call("search_history", [
            "query": .string(""),
            "kind": .string("url"),
        ]))
        XCTAssertEqual(try items(kindOnly).map { $0["id"]?.int64Value }, [url.id])
    }

    func testSearchHistoryAppliesFromAndDatePowerSyntax() throws {
        // The router resolves relative dates against the wall clock, so this
        // fixture anchors to now instead of the fixed `now` above.
        let clock = Date()
        let recentSafari = try store.insert(
            kind: .text,
            text: "recent safari note",
            sourceApp: "Safari",
            bundleId: "com.apple.Safari",
            hash: "mcp-recent-safari",
            now: clock.addingTimeInterval(-3600)
        ).item
        _ = try store.insert(
            kind: .text,
            text: "recent notes note",
            sourceApp: "Notes",
            bundleId: "com.apple.Notes",
            hash: "mcp-recent-notes",
            now: clock.addingTimeInterval(-3600)
        )
        _ = try store.insert(
            kind: .text,
            text: "old safari note",
            sourceApp: "Safari",
            bundleId: "com.apple.Safari",
            hash: "mcp-old-safari",
            now: clock.addingTimeInterval(-10 * 86_400)
        )

        let payload = try success(call("search_history", [
            "query": .string("from:Safari date:7d"),
        ]))
        XCTAssertEqual(try items(payload).map { $0["id"]?.int64Value }, [recentSafari.id])
    }

    func testSearchHistoryFiltersByPinboardAndFallsBackForUnknownNames() throws {
        let boardItem = try store.insert(
            kind: .text,
            text: "board member",
            hash: "mcp-board",
            now: now
        ).item
        let archiveItem = try store.insert(
            kind: .text,
            text: "archive notes",
            hash: "mcp-archive",
            now: now.addingTimeInterval(-60)
        ).item
        let board = try store.createPinboard(name: "Design", colorHex: "#FF9F0A", now: now)
        try store.addItem(try XCTUnwrap(boardItem.id), toPinboard: try XCTUnwrap(board.id))

        let pinned = try success(call("search_history", [
            "query": .string("pinboard:design"),
        ]))
        XCTAssertEqual(try items(pinned).map { $0["id"]?.int64Value }, [boardItem.id])
        XCTAssertEqual(try items(pinned).first?["pinboard"]?.stringValue, "Design")

        // An unknown board name stays searchable free text, matching the app.
        let fallback = try success(call("search_history", [
            "query": .string("pinboard:archive"),
        ]))
        XCTAssertEqual(try items(fallback).map { $0["id"]?.int64Value }, [archiveItem.id])
    }

    func testSearchHistoryRespectsLimit() throws {
        for index in 1...3 {
            _ = try store.insert(
                kind: .text,
                text: "limit item \(index)",
                hash: "mcp-limit-\(index)",
                now: now.addingTimeInterval(Double(index))
            )
        }

        let payload = try success(call("search_history", [
            "query": .string("limit"),
            "limit": .number(2),
        ]))
        XCTAssertEqual(try items(payload).count, 2)
        XCTAssertEqual(payload["count"]?.int64Value, 2)
    }

    func testSearchHistoryRejectsInvalidArguments() {
        if case .invalidParams = call("search_history", [:]) {} else {
            XCTFail("Missing query must be invalid params")
        }
        if case .invalidParams = call("search_history", ["query": .string(""), "kind": .string("banana")]) {} else {
            XCTFail("Unknown kind must be invalid params")
        }
        if case .invalidParams = call("search_history", ["query": .string(""), "limit": .string("ten")]) {} else {
            XCTFail("Non-numeric limit must be invalid params")
        }
    }

    // MARK: - get_item

    func testGetItemReturnsFullRecordWithPinboardAndShortURL() throws {
        let item = try store.insert(
            kind: .url,
            text: "https://example.com/very/long/path",
            title: "Example",
            dataPath: "/tmp/secret-preview.png",
            sourceApp: "Safari",
            bundleId: "com.apple.Safari",
            hash: "mcp-get-item",
            now: now
        ).item
        let id = try XCTUnwrap(item.id)
        let board = try store.createPinboard(name: "Reading", colorHex: "#0A84FF", now: now)
        try store.addItem(id, toPinboard: try XCTUnwrap(board.id))
        try store.setShortURL("https://bit.ly/abc", for: id)

        let payload = try success(call("get_item", ["id": .number(Double(id))]))

        XCTAssertEqual(payload["id"]?.int64Value, id)
        XCTAssertEqual(payload["kind"]?.stringValue, "url")
        XCTAssertEqual(payload["text"]?.stringValue, "https://example.com/very/long/path")
        XCTAssertEqual(payload["title"]?.stringValue, "Example")
        XCTAssertEqual(payload["sourceApp"]?.stringValue, "Safari")
        XCTAssertEqual(payload["bundleId"]?.stringValue, "com.apple.Safari")
        XCTAssertEqual(payload["shortUrl"]?.stringValue, "https://bit.ly/abc")
        XCTAssertEqual(payload["pinboard"]?.stringValue, "Reading")
        XCTAssertEqual(payload["isPinned"]?.boolValue, true)
        XCTAssertNil(payload["dataPath"])
    }

    func testGetItemMissingAndInvalidID() throws {
        let missing = try failure(call("get_item", ["id": .number(999)]))
        XCTAssertTrue(missing.contains("not found"))

        if case .invalidParams = call("get_item", ["id": .string("abc")]) {} else {
            XCTFail("Non-numeric id must be invalid params")
        }
        if case .invalidParams = call("get_item", [:]) {} else {
            XCTFail("Missing id must be invalid params")
        }
    }

    // MARK: - list_pinboards

    func testListPinboardsReportsItemCounts() throws {
        let empty = try store.createPinboard(name: "Empty", colorHex: "#FF453A", now: now)
        let filled = try store.createPinboard(name: "Filled", colorHex: "#0A84FF", now: now)
        let item = try store.insert(kind: .text, text: "member", hash: "mcp-count", now: now).item
        try store.addItem(try XCTUnwrap(item.id), toPinboard: try XCTUnwrap(filled.id))

        let payload = try success(call("list_pinboards"))
        let boards = try XCTUnwrap(payload["pinboards"]?.arrayValue)

        XCTAssertEqual(payload["count"]?.int64Value, 2)
        XCTAssertEqual(boards[0]["name"]?.stringValue, "Empty")
        XCTAssertEqual(boards[0]["itemCount"]?.int64Value, 0)
        XCTAssertEqual(boards[0]["colorHex"]?.stringValue, "#FF453A")
        XCTAssertEqual(boards[1]["name"]?.stringValue, "Filled")
        XCTAssertEqual(boards[1]["itemCount"]?.int64Value, 1)
        XCTAssertEqual(boards[1]["id"]?.int64Value, filled.id)
        XCTAssertEqual(boards[0]["id"]?.int64Value, empty.id)
    }

    // MARK: - get_pinboard_items

    func testGetPinboardItemsMatchesNameCaseInsensitively() throws {
        let board = try store.createPinboard(name: "Design Stuff", colorHex: "#BF5AF2", now: now)
        let first = try store.insert(kind: .text, text: "first", hash: "mcp-pb-1", now: now).item
        let second = try store.insert(kind: .text, text: "second", hash: "mcp-pb-2", now: now.addingTimeInterval(10)).item
        try store.addItem(try XCTUnwrap(first.id), toPinboard: try XCTUnwrap(board.id))
        try store.addItem(try XCTUnwrap(second.id), toPinboard: try XCTUnwrap(board.id))

        let payload = try success(call("get_pinboard_items", ["name": .string("design stuff")]))

        XCTAssertEqual(payload["pinboard"]?["name"]?.stringValue, "Design Stuff")
        XCTAssertEqual(payload["count"]?.int64Value, 2)
        XCTAssertEqual(
            try items(payload).map { $0["id"]?.int64Value },
            [second.id, first.id]
        )
        XCTAssertEqual(try items(payload).first?["pinboard"]?.stringValue, "Design Stuff")
    }

    func testGetPinboardItemsUnknownNameFails() throws {
        _ = try store.createPinboard(name: "Design", colorHex: "#FF9F0A", now: now)
        let message = try failure(call("get_pinboard_items", ["name": .string("designx")]))
        XCTAssertTrue(message.contains("Pinboard not found: designx"))
    }

    // MARK: - create_pinboard

    func testCreatePinboardTrimsNameAndUsesDefaultColor() throws {
        let payload = try success(call("create_pinboard", ["name": .string("  Reading List  ")]))

        XCTAssertEqual(payload["name"]?.stringValue, "Reading List")
        XCTAssertEqual(payload["colorHex"]?.stringValue, MCPToolRouter.defaultPinboardColor)
        XCTAssertEqual(payload["itemCount"]?.int64Value, 0)

        let stored = try store.pinboards()
        XCTAssertEqual(stored.map(\.name), ["Reading List"])
        XCTAssertEqual(stored.first?.colorHex, MCPToolRouter.defaultPinboardColor)
    }

    func testCreatePinboardRejectsEmptyName() throws {
        let message = try failure(call("create_pinboard", ["name": .string("   ")]))
        XCTAssertTrue(message.contains("required"))
        XCTAssertTrue(try store.pinboards().isEmpty)
    }

    // MARK: - add_item_to_pinboard

    func testAddItemToPinboardByNameAndByID() throws {
        let board = try store.createPinboard(name: "Reading", colorHex: "#FF9F0A", now: now)
        let byName = try store.insert(kind: .text, text: "by name", hash: "mcp-add-name", now: now).item
        let byID = try store.insert(kind: .text, text: "by id", hash: "mcp-add-id", now: now).item

        let nameResult = try success(call("add_item_to_pinboard", [
            "item_id": .number(Double(try XCTUnwrap(byName.id))),
            "pinboard": .string("reading"),
        ]))
        XCTAssertEqual(nameResult["pinboard"]?["name"]?.stringValue, "Reading")

        let idResult = try success(call("add_item_to_pinboard", [
            "item_id": .number(Double(try XCTUnwrap(byID.id))),
            "pinboard": .number(Double(try XCTUnwrap(board.id))),
        ]))
        XCTAssertEqual(idResult["pinboard"]?["id"]?.int64Value, board.id)

        let members = try store.items(inPinboard: try XCTUnwrap(board.id))
        XCTAssertEqual(Set(members.map(\.id)), Set([byName.id, byID.id]))
        XCTAssertTrue(members.allSatisfy(\.isPinned))
    }

    func testAddItemToPinboardRejectsUnknownItemOrBoard() throws {
        let board = try store.createPinboard(name: "Reading", colorHex: "#FF9F0A", now: now)
        let item = try store.insert(kind: .text, text: "lonely", hash: "mcp-lonely", now: now).item

        let missingItem = try failure(call("add_item_to_pinboard", [
            "item_id": .number(999),
            "pinboard": .string("Reading"),
        ]))
        XCTAssertTrue(missingItem.contains("Item not found: 999"))

        let missingBoard = try failure(call("add_item_to_pinboard", [
            "item_id": .number(Double(try XCTUnwrap(item.id))),
            "pinboard": .string("Nowhere"),
        ]))
        XCTAssertTrue(missingBoard.contains("Pinboard not found: Nowhere"))

        XCTAssertTrue(try store.items(inPinboard: try XCTUnwrap(board.id)).isEmpty)
    }
}

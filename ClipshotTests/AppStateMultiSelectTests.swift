import AppKit
import XCTest
@testable import Clipshot

@MainActor
final class AppStateMultiSelectTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipshotMultiSelectTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func makeAppState(store: HistoryStore) -> AppState {
        AppState(
            store: store,
            startMonitoring: false,
            dataStore: ItemDataStore(directory: directory)
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func insertText(_ store: HistoryStore, _ text: String, hash: String) throws -> Int64 {
        let inserted = try store.insert(
            kind: .text,
            text: text,
            bundleId: "com.apple.Notes",
            hash: hash
        ).item
        return try XCTUnwrap(inserted.id)
    }

    func testCommandClickTogglesSelectionSet() async throws {
        let store = try HistoryStore.inMemory()
        let appState = makeAppState(store: store)

        let first = try insertText(store, "one", hash: "one")
        let second = try insertText(store, "two", hash: "two")
        appState.reload()
        await waitUntil { appState.items.count == 2 }

        let itemOne = try XCTUnwrap(appState.items.first { $0.id == first })
        appState.select(itemOne)
        XCTAssertEqual(appState.selectedItemIDs, [first])

        let itemTwo = try XCTUnwrap(appState.items.first { $0.id == second })
        appState.select(itemTwo, modifiers: [.command])
        XCTAssertEqual(appState.selectedItemIDs, Set([first, second]))

        appState.select(itemTwo, modifiers: [.command])
        XCTAssertEqual(appState.selectedItemIDs, [first])
    }

    func testShiftClickSelectsInclusiveRangeInTimelineOrder() async throws {
        let store = try HistoryStore.inMemory()
        let appState = makeAppState(store: store)

        _ = try insertText(store, "a", hash: "a")
        _ = try insertText(store, "b", hash: "b")
        _ = try insertText(store, "c", hash: "c")
        appState.reload()
        await waitUntil { appState.items.count == 3 }

        let ordered = appState.items
        let firstItem = try XCTUnwrap(ordered.first)
        let lastItem = try XCTUnwrap(ordered.last)
        appState.select(firstItem)
        appState.select(lastItem, modifiers: [.shift])

        XCTAssertEqual(
            appState.selectedItemIDs,
            Set(ordered.compactMap(\.id)),
            "⇧-click selects the contiguous slice in timeline order"
        )
    }

    func testBulkDeleteRemovesAllSelectedItems() async throws {
        let store = try HistoryStore.inMemory()
        let appState = makeAppState(store: store)

        let keep = try insertText(store, "keep", hash: "keep")
        let dropA = try insertText(store, "drop-a", hash: "drop-a")
        let dropB = try insertText(store, "drop-b", hash: "drop-b")
        appState.reload()
        await waitUntil { appState.items.count == 3 }

        appState.selectedItemIDs = [dropA, dropB]
        appState.selectedItemID = dropA
        appState.deleteSelectedItems()

        await waitUntil { appState.items.count == 1 }
        XCTAssertEqual(appState.items.map(\.id), [keep])
        XCTAssertTrue(appState.selectedItemIDs.isEmpty || appState.selectedItemIDs == [keep])
    }

    func testBulkPinAndAddToPinboard() async throws {
        let store = try HistoryStore.inMemory()
        let appState = makeAppState(store: store)

        let one = try insertText(store, "one", hash: "pin-one")
        let two = try insertText(store, "two", hash: "pin-two")
        let pinboard = try store.createPinboard(name: "Bulk", colorHex: "#ff8800")
        let boardID = try XCTUnwrap(pinboard.id)
        appState.reload()
        await waitUntil { appState.items.count == 2 }

        appState.selectedItemIDs = [one, two]
        appState.pinSelectedItems()
        await waitUntil {
            (try? store.item(id: one))?.isPinned == true
                && (try? store.item(id: two))?.isPinned == true
        }

        appState.addSelectedItems(to: pinboard)
        await waitUntil {
            (try? store.item(id: one))?.pinboardId == boardID
                && (try? store.item(id: two))?.pinboardId == boardID
        }
    }
}

import XCTest
@testable import Clipshot

@MainActor
final class AppStateRevealTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipshotRevealTests-\(UUID().uuidString)", isDirectory: true)
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

    func testRevealClearsSearchAndFiltersAndSelectsItemAcrossReload() async throws {
        let store = try HistoryStore.inMemory()
        let appState = makeAppState(store: store)

        let target = try store.insert(
            kind: .url,
            text: "https://target.example.com/article",
            bundleId: "com.apple.Safari",
            hash: "target-url"
        ).item
        let targetID = try XCTUnwrap(target.id)
        try store.setPinned(true, for: targetID)
        _ = try store.insert(
            kind: .text,
            text: "unrelated note",
            bundleId: "com.apple.Notes",
            hash: "other-text"
        )

        appState.reload()
        await waitUntil { appState.items.count == 2 }

        appState.searchText = "target"
        await waitUntil { appState.items.map(\.id) == [targetID] }
        XCTAssertEqual(appState.items.map(\.id), [targetID])

        appState.filterKind = .url
        appState.filterBundleId = "com.apple.Safari"
        appState.filterPinnedOnly = true
        await waitUntil {
            appState.filterKind == .url
                && appState.filterBundleId == "com.apple.Safari"
                && appState.filterPinnedOnly
                && appState.items.map(\.id) == [targetID]
        }
        XCTAssertTrue(appState.hasActiveFilter)

        // Use the persisted snapshot, as the card would.
        let visibleItem = try XCTUnwrap(try store.item(id: targetID))
        appState.reveal(visibleItem)

        XCTAssertEqual(appState.searchText, "")
        XCTAssertNil(appState.filterKind)
        XCTAssertNil(appState.filterBundleId)
        XCTAssertFalse(appState.filterPinnedOnly)
        XCTAssertTrue(appState.filterPinboardIDs.isEmpty)
        XCTAssertFalse(appState.hasActiveFilter)
        XCTAssertEqual(appState.selectedItemID, targetID)
        XCTAssertEqual(appState.revealTargetID, targetID)

        // The reload is asynchronous: the selection must survive it.
        await waitUntil {
            appState.items.count == 2
                && appState.items.contains { $0.id == targetID }
        }
        XCTAssertTrue(appState.items.contains { $0.id == targetID })
        XCTAssertEqual(appState.selectedItemID, targetID)
    }

    func testRevealSwitchesBoardFilterToItemsBoard() async throws {
        let store = try HistoryStore.inMemory()
        let appState = makeAppState(store: store)

        let emptyBoard = try store.createPinboard(name: "Empty", colorHex: "#FF0000")
        let itemBoard = try store.createPinboard(name: "Item", colorHex: "#00FF00")
        let target = try store.insert(kind: .text, text: "boarded item", hash: "boarded").item
        let targetID = try XCTUnwrap(target.id)
        try store.addItem(targetID, toPinboard: try XCTUnwrap(itemBoard.id))
        _ = try store.insert(kind: .text, text: "elsewhere", hash: "elsewhere")

        appState.reload()
        await waitUntil { appState.items.count == 2 }

        appState.filterPinboardIDs = [try XCTUnwrap(emptyBoard.id)]
        await waitUntil { appState.items.isEmpty }
        XCTAssertTrue(appState.items.isEmpty)

        let visibleItem = try XCTUnwrap(try store.item(id: targetID))
        appState.reveal(visibleItem)

        XCTAssertEqual(appState.filterPinboardIDs, [try XCTUnwrap(itemBoard.id)])
        await waitUntil {
            appState.items.map(\.id) == [targetID]
                && appState.selectedItemID == targetID
        }
        XCTAssertEqual(appState.filterPinboardIDs, [try XCTUnwrap(itemBoard.id)])
        XCTAssertEqual(appState.items.map(\.id), [targetID])
        XCTAssertEqual(appState.selectedItemID, targetID)
    }

    func testRevealClearsBoardFilterWhenItemHasNoBoard() async throws {
        let store = try HistoryStore.inMemory()
        let appState = makeAppState(store: store)

        let board = try store.createPinboard(name: "Empty", colorHex: "#FF0000")
        let target = try store.insert(kind: .text, text: "loose item", hash: "loose").item
        let targetID = try XCTUnwrap(target.id)

        appState.reload()
        await waitUntil { appState.items.map(\.id) == [targetID] }

        appState.filterPinboardIDs = [try XCTUnwrap(board.id)]
        await waitUntil { appState.items.isEmpty }

        let visibleItem = try XCTUnwrap(try store.item(id: targetID))
        appState.reveal(visibleItem)

        XCTAssertTrue(appState.filterPinboardIDs.isEmpty)
        await waitUntil {
            appState.items.map(\.id) == [targetID]
                && appState.selectedItemID == targetID
        }
        XCTAssertTrue(appState.filterPinboardIDs.isEmpty)
        XCTAssertEqual(appState.selectedItemID, targetID)
    }

    func testRevealKeepsMultiBoardSelectionThatShowsItem() async throws {
        let store = try HistoryStore.inMemory()
        let appState = makeAppState(store: store)

        let boardA = try store.createPinboard(name: "A", colorHex: "#FF0000")
        let boardB = try store.createPinboard(name: "B", colorHex: "#00FF00")
        let itemA = try store.insert(kind: .text, text: "in A", hash: "reveal-a").item
        let itemB = try store.insert(kind: .text, text: "in B", hash: "reveal-b").item
        try store.addItem(try XCTUnwrap(itemA.id), toPinboard: try XCTUnwrap(boardA.id))
        try store.addItem(try XCTUnwrap(itemB.id), toPinboard: try XCTUnwrap(boardB.id))

        appState.filterPinboardIDs = [
            try XCTUnwrap(boardA.id),
            try XCTUnwrap(boardB.id)
        ]
        await waitUntil { appState.items.count == 2 }
        XCTAssertEqual(appState.items.count, 2)

        // The item's board is already in the set, so the union keeps showing it
        // and the multi-board context is preserved.
        let visibleItem = try XCTUnwrap(try store.item(id: try XCTUnwrap(itemB.id)))
        appState.reveal(visibleItem)

        XCTAssertEqual(
            appState.filterPinboardIDs,
            [try XCTUnwrap(boardA.id), try XCTUnwrap(boardB.id)]
        )
        XCTAssertEqual(appState.selectedItemID, itemB.id)
    }

    func testSelectionSurvivesDebouncedSearchReload() async throws {
        let store = try HistoryStore.inMemory()
        let appState = makeAppState(store: store)

        let target = try store.insert(kind: .text, text: "needle in history", hash: "needle").item
        let targetID = try XCTUnwrap(target.id)
        _ = try store.insert(kind: .text, text: "first other", hash: "other-1")
        _ = try store.insert(kind: .text, text: "second other", hash: "other-2")

        appState.reload()
        await waitUntil { appState.items.count == 3 }

        // Only the search query is active here, so the reload is debounced.
        appState.searchText = "needle"
        await waitUntil {
            appState.items.count == 1 && appState.items.first?.id == targetID
        }
        let searchedItem = try XCTUnwrap(appState.items.first)

        appState.reveal(searchedItem)

        XCTAssertEqual(appState.searchText, "")
        XCTAssertEqual(appState.selectedItemID, targetID)
        XCTAssertEqual(appState.revealTargetID, targetID)

        await waitUntil { appState.items.count == 3 }
        XCTAssertEqual(appState.selectedItemID, targetID)
    }

    func testHasActiveFilterTracksSearchAndEveryFilter() throws {
        let store = try HistoryStore.inMemory()
        let appState = makeAppState(store: store)

        XCTAssertFalse(appState.hasActiveFilter)

        appState.searchText = "hello"
        XCTAssertTrue(appState.hasActiveFilter)
        appState.searchText = ""
        XCTAssertFalse(appState.hasActiveFilter)

        appState.filterKind = .text
        XCTAssertTrue(appState.hasActiveFilter)
        appState.filterKind = nil

        appState.filterBundleId = "com.apple.Notes"
        XCTAssertTrue(appState.hasActiveFilter)
        appState.filterBundleId = nil

        appState.filterPinnedOnly = true
        XCTAssertTrue(appState.hasActiveFilter)
        appState.filterPinnedOnly = false

        appState.filterPinboardIDs = [1]
        XCTAssertTrue(appState.hasActiveFilter)
        appState.filterPinboardIDs = []

        XCTAssertFalse(appState.hasActiveFilter)
    }
}

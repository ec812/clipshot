import AppKit
import Carbon.HIToolbox
import Foundation
import XCTest
@testable import Clipshot

@MainActor
final class AppStateEditorTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipshotEditorTests-\(UUID().uuidString)", isDirectory: true)
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

    private func keyEvent(
        keyCode: Int,
        modifiers: NSEvent.ModifierFlags,
        characters: String
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: UInt16(keyCode)
            )
        )
    }

    // MARK: - New link item

    func testNewLinkSaveInsertsURLAtTimelineHead() async throws {
        let store = try HistoryStore.inMemory()
        let appState = makeAppState(store: store)

        _ = try store.insert(
            kind: .text,
            text: "older note",
            hash: "older-note",
            now: Date(timeIntervalSinceNow: -60)
        )
        appState.reload()
        await waitUntil { appState.items.count == 1 }

        appState.saveEditor(
            EditorRequest(mode: .newLink, item: nil),
            text: "  example.com/articles/one  ",
            title: "  Example  "
        )

        await waitUntil { appState.items.count == 2 }
        XCTAssertEqual(appState.items.count, 2)

        let link = try XCTUnwrap(appState.items.first)
        XCTAssertEqual(link.kind, .url)
        XCTAssertEqual(link.text, "https://example.com/articles/one")
        XCTAssertEqual(link.title, "Example")
        XCTAssertEqual(link.sourceApp, "Clipshot")
        XCTAssertEqual(link.bundleId, "com.ernest.clipshot")
        XCTAssertTrue(link.isSnippet)
        XCTAssertEqual(
            link.hash,
            ClipboardPayloadReader.hash(
                kind: .url,
                strings: ["https://example.com/articles/one"]
            )
        )
        XCTAssertEqual(appState.items.dropFirst().first?.kind, ClipboardItemKind.text)
    }

    func testNewLinkSaveDeduplicatesByHash() async throws {
        let store = try HistoryStore.inMemory()
        let appState = makeAppState(store: store)

        let normalized = "https://example.com/article"
        let existing = try store.insert(
            kind: .url,
            text: normalized,
            sourceApp: "Safari",
            bundleId: "com.apple.Safari",
            hash: ClipboardPayloadReader.hash(kind: .url, strings: [normalized]),
            now: Date(timeIntervalSinceNow: -600)
        ).item
        let existingID = try XCTUnwrap(existing.id)

        appState.saveEditor(
            EditorRequest(mode: .newLink, item: nil),
            text: "example.com/article",
            title: ""
        )

        await waitUntil {
            (try? store.item(id: existingID))?.sourceApp == "Clipshot"
        }

        XCTAssertEqual(try store.itemCount(), 1)
        let updated = try XCTUnwrap(try store.item(id: existingID))
        XCTAssertEqual(updated.text, normalized)
        XCTAssertEqual(updated.sourceApp, "Clipshot")
        XCTAssertEqual(updated.bundleId, "com.ernest.clipshot")
    }

    func testNewLinkRejectsEmptyAndInvalidURLs() async throws {
        let store = try HistoryStore.inMemory()
        let appState = makeAppState(store: store)

        for input in ["", "   ", "not a url", "ftp://example.com", "javascript:alert(1)"] {
            appState.saveEditor(
                EditorRequest(mode: .newLink, item: nil),
                text: input,
                title: ""
            )
        }

        // saveEditor rejects synchronously, before the background write starts.
        XCTAssertEqual(try store.itemCount(), 0)
    }

    // MARK: - New text item (regression)

    func testNewTextSnippetStillInsertsLabeledItemAtHead() async throws {
        let store = try HistoryStore.inMemory()
        let appState = makeAppState(store: store)

        _ = try store.insert(
            kind: .text,
            text: "captured earlier",
            hash: "captured-earlier",
            now: Date(timeIntervalSinceNow: -60)
        )
        appState.reload()
        await waitUntil { appState.items.count == 1 }

        appState.saveEditor(
            EditorRequest(mode: .newSnippet, item: nil),
            text: "manual note",
            title: ""
        )

        await waitUntil { appState.items.count == 2 }
        let item = try XCTUnwrap(appState.items.first)
        XCTAssertEqual(item.kind, .text)
        XCTAssertEqual(item.text, "manual note")
        XCTAssertEqual(item.sourceApp, "Clipshot")
        XCTAssertTrue(item.isSnippet)
        XCTAssertEqual(
            item.hash,
            ClipboardPayloadReader.hash(kind: .text, strings: ["manual note"])
        )
    }

    // MARK: - Keybindings

    func testCommandNStillOpensTextEditorAndCommandShiftNOpensLinkEditor() throws {
        let store = try HistoryStore.inMemory()
        let appState = makeAppState(store: store)

        let commandN = try keyEvent(keyCode: kVK_ANSI_N, modifiers: .command, characters: "n")
        XCTAssertTrue(appState.handleOverlayKey(commandN))
        XCTAssertEqual(appState.editorRequest?.mode, .newSnippet)

        appState.editorRequest = nil
        let commandShiftN = try keyEvent(
            keyCode: kVK_ANSI_N,
            modifiers: [.command, .shift],
            characters: "N"
        )
        XCTAssertTrue(appState.handleOverlayKey(commandShiftN))
        XCTAssertEqual(appState.editorRequest?.mode, .newLink)
    }

    // MARK: - URL normalization

    func testNormalizedURLStringAcceptsBareHostAndTrimsWhitespace() {
        XCTAssertEqual(
            ClipboardPayloadReader.normalizedURLString(from: "  example.com  "),
            "https://example.com"
        )
        XCTAssertEqual(
            ClipboardPayloadReader.normalizedURLString(from: "example.com/path?q=1"),
            "https://example.com/path?q=1"
        )
        XCTAssertEqual(
            ClipboardPayloadReader.normalizedURLString(from: "https://example.com/path"),
            "https://example.com/path"
        )
        XCTAssertEqual(
            ClipboardPayloadReader.normalizedURLString(from: "http://example.com"),
            "http://example.com"
        )
        XCTAssertEqual(
            ClipboardPayloadReader.normalizedURLString(from: "example.com:8080"),
            "https://example.com:8080"
        )
    }

    func testNormalizedURLStringRejectsInvalidInput() {
        XCTAssertNil(ClipboardPayloadReader.normalizedURLString(from: ""))
        XCTAssertNil(ClipboardPayloadReader.normalizedURLString(from: "   "))
        XCTAssertNil(ClipboardPayloadReader.normalizedURLString(from: "not a url"))
        XCTAssertNil(ClipboardPayloadReader.normalizedURLString(from: "ftp://example.com"))
        XCTAssertNil(ClipboardPayloadReader.normalizedURLString(from: "javascript:alert(1)"))
        XCTAssertNil(ClipboardPayloadReader.normalizedURLString(from: "https://"))
        XCTAssertNil(ClipboardPayloadReader.normalizedURLString(from: "https://localhost"))
    }
}

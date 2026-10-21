import SwiftUI
import XCTest
@testable import Clipshot

@MainActor
final class CodeHighlightStoreTests: XCTestCase {
    private final class Counter: @unchecked Sendable {
        var detections = 0
        var highlights = 0
    }

    private final class WorkBox: @unchecked Sendable {
        var works: [@Sendable () -> Void] = []
    }

    private func makeItem(_ text: String, hash: String = "hash") -> ClipboardItem {
        ClipboardItem(kind: .text, text: text, hash: hash)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let name = "CodeHighlightStoreTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    private func makeStore(
        counter: Counter,
        detection: CodeLanguage?,
        defaults: UserDefaults,
        scheduler: @escaping CodeHighlightStore.Scheduler = { work in work() }
    ) -> CodeHighlightStore {
        CodeHighlightStore(
            defaults: defaults,
            detect: { _ in
                counter.detections += 1
                return detection
            },
            highlight: { text, language, scheme in
                counter.highlights += 1
                let schemeName = scheme == .dark ? "dark" : "light"
                return AttributedString("\(language.rawValue)|\(schemeName)|\(text)")
            },
            scheduler: scheduler
        )
    }

    func testProcessesCodeOnceAndCachesBothThemes() throws {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let counter = Counter()
        let store = makeStore(counter: counter, detection: .swift, defaults: defaults)
        let item = makeItem("let value = 1")

        store.ensureProcessed(item)

        XCTAssertEqual(counter.detections, 1)
        XCTAssertEqual(counter.highlights, 2)
        XCTAssertEqual(store.revision, 1)
        XCTAssertTrue(store.isCode(for: item))

        let light = try XCTUnwrap(
            store.attributedPreview(for: item, colorScheme: .light)
        )
        let dark = try XCTUnwrap(
            store.attributedPreview(for: item, colorScheme: .dark)
        )
        XCTAssertEqual(String(light.characters), "swift|light|let value = 1")
        XCTAssertEqual(String(dark.characters), "swift|dark|let value = 1")

        store.ensureProcessed(item)
        XCTAssertEqual(counter.detections, 1)
    }

    func testPlainTextCachesNegativeResult() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let counter = Counter()
        let store = makeStore(counter: counter, detection: nil, defaults: defaults)
        let item = makeItem("Just some prose.")

        store.ensureProcessed(item)

        XCTAssertEqual(counter.detections, 1)
        XCTAssertEqual(counter.highlights, 0)
        XCTAssertFalse(store.isCode(for: item))
        XCTAssertNil(store.attributedPreview(for: item, colorScheme: .light))
        XCTAssertEqual(store.revision, 1)

        store.ensureProcessed(item)
        XCTAssertEqual(counter.detections, 1)
    }

    func testOverrideFalseHidesCodeAndNilRestoresDetection() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let counter = Counter()
        let store = makeStore(counter: counter, detection: .swift, defaults: defaults)
        let item = makeItem("let value = 1")

        store.ensureProcessed(item)
        XCTAssertNotNil(store.attributedPreview(for: item, colorScheme: .light))

        store.setOverride(false, for: item)
        XCTAssertFalse(store.isCode(for: item))
        XCTAssertNil(store.attributedPreview(for: item, colorScheme: .light))

        store.setOverride(nil, for: item)
        XCTAssertTrue(store.isCode(for: item))
        XCTAssertNotNil(store.attributedPreview(for: item, colorScheme: .light))
    }

    func testForcedCodeUsesGenericWhenDetectionFails() throws {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let counter = Counter()
        let store = makeStore(counter: counter, detection: nil, defaults: defaults)
        let item = makeItem("not detected as code")

        store.setOverride(true, for: item)

        XCTAssertTrue(store.isCode(for: item))
        XCTAssertEqual(counter.highlights, 2)
        let preview = try XCTUnwrap(
            store.attributedPreview(for: item, colorScheme: .light)
        )
        XCTAssertTrue(String(preview.characters).hasPrefix("generic|"))
    }

    func testOverridePersistsAcrossStoreInstances() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let item = makeItem("not detected as code")

        let first = makeStore(counter: Counter(), detection: nil, defaults: defaults)
        first.setOverride(true, for: item)

        let second = makeStore(counter: Counter(), detection: nil, defaults: defaults)
        XCTAssertTrue(second.isCode(for: item))

        second.setOverride(nil, for: item)
        let third = makeStore(counter: Counter(), detection: nil, defaults: defaults)
        XCTAssertFalse(third.isCode(for: item))
    }

    func testInFlightDeduplicatesPerHash() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let counter = Counter()
        let box = WorkBox()
        let store = makeStore(
            counter: counter,
            detection: .swift,
            defaults: defaults,
            scheduler: { work in box.works.append(work) }
        )
        let item = makeItem("let value = 1")

        store.ensureProcessed(item)
        store.ensureProcessed(item)

        XCTAssertEqual(box.works.count, 1)
        XCTAssertEqual(counter.detections, 0)
        XCTAssertNil(store.attributedPreview(for: item, colorScheme: .light))

        box.works[0]()

        XCTAssertEqual(counter.detections, 1)
        XCTAssertNotNil(store.attributedPreview(for: item, colorScheme: .light))
    }

    func testNonTextAndEmptyItemsAreIgnored() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let counter = Counter()
        let store = makeStore(counter: counter, detection: .swift, defaults: defaults)
        let urlItem = ClipboardItem(
            kind: .url,
            text: "https://example.com",
            hash: "url"
        )
        let emptyItem = makeItem("", hash: "empty")

        store.ensureProcessed(urlItem)
        store.ensureProcessed(emptyItem)
        store.setOverride(true, for: urlItem)

        XCTAssertEqual(counter.detections, 0)
        XCTAssertFalse(store.isCode(for: urlItem))
        XCTAssertNil(store.attributedPreview(for: urlItem, colorScheme: .light))
        XCTAssertFalse(store.isCode(for: emptyItem))
    }
}

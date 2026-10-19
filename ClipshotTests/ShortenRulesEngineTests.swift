import XCTest
@testable import Clipshot

final class ShortenRulesEngineTests: XCTestCase {
    private var store: HistoryStore!
    private var engine: ShortenRulesEngine!

    override func setUpWithError() throws {
        store = try HistoryStore.inMemory()
        engine = ShortenRulesEngine(store: store)
    }

    override func tearDown() {
        engine = nil
        store = nil
    }

    private func context(
        _ string: String,
        bundleId: String? = "com.apple.Safari",
        sourceApp: String? = "Safari",
        date: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> ShortenRuleContext {
        ShortenRuleContext(
            url: URL(string: string),
            sourceApp: sourceApp,
            bundleId: bundleId,
            date: date
        )
    }

    func testMatchesURLGlobAgainstFullURLAndHost() throws {
        _ = try store.saveShortenRule(ShortenRule(name: "Medium", urlPattern: "*medium.com*"))

        XCTAssertNotNil(try engine.matchingRule(for: context("https://medium.com/article")))
        XCTAssertNotNil(try engine.matchingRule(for: context("https://www.medium.com/article")))
        XCTAssertNil(try engine.matchingRule(for: context("https://example.com/article")))
    }

    func testMatchesSourceApp() throws {
        _ = try store.saveShortenRule(
            ShortenRule(name: "Twitter", urlPattern: "*", sourceAppPattern: "com.apple.Safari")
        )
        XCTAssertNotNil(try engine.matchingRule(for: context("https://example.com", bundleId: "com.apple.Safari")))
        XCTAssertNil(try engine.matchingRule(for: context("https://example.com", bundleId: "com.apple.Notes", sourceApp: "Notes")))
    }

    func testNoURLNeverMatches() throws {
        _ = try store.saveShortenRule(ShortenRule(name: "Catch all"))
        let empty = ShortenRuleContext(url: nil, sourceApp: "Safari", bundleId: "com.apple.Safari", date: Date())
        XCTAssertNil(try engine.matchingRule(for: empty))
    }

    func testFirstEnabledRuleInPriorityOrderWinsOnce() throws {
        _ = try store.saveShortenRule(ShortenRule(name: "Second", urlPattern: "*", priority: 5))
        _ = try store.saveShortenRule(ShortenRule(name: "First", urlPattern: "*example*", priority: 1))
        _ = try store.saveShortenRule(ShortenRule(name: "Disabled", isEnabled: false, urlPattern: "*", priority: 0))

        let match = try engine.matchingRule(for: context("https://example.com"))
        XCTAssertEqual(match?.name, "First")
    }

    func testDisabledOnlyRuleDoesNotMatch() throws {
        _ = try store.saveShortenRule(ShortenRule(name: "Off", isEnabled: false))
        XCTAssertNil(try engine.matchingRule(for: context("https://example.com")))
    }

    func testGlobEscaping() {
        XCTAssertTrue(ShortenRulesEngine.globMatch("https://example.com/*", "https://example.com/a/b"))
        XCTAssertTrue(ShortenRulesEngine.globMatch("*.COM", "https://Example.com"))
        XCTAssertFalse(ShortenRulesEngine.globMatch("https://example.com/a", "https://example.com/b"))
        XCTAssertTrue(ShortenRulesEngine.globMatch("a?c", "abc"))
        XCTAssertFalse(ShortenRulesEngine.globMatch("a.c", "abc"))
    }

    func testSlugTemplateRendering() {
        let date = Date(timeIntervalSince1970: 1_766_000_000) // 2025-12-17 UTC
        let slug = ShortenRulesEngine.renderSlug(
            template: "{host}-{path}-{word}-{date}",
            url: URL(string: "https://www.example.com/Design-Systems-2026?ref=x")!,
            date: date
        )
        XCTAssertEqual(slug, "example-com-design-systems-2026-design-20251217")
    }

    func testSlugTemplateRandomTokenIsReplaced() {
        let slug = ShortenRulesEngine.renderSlug(
            template: "promo-{rand}",
            url: URL(string: "https://example.com")!
        )
        XCTAssertTrue(slug.hasPrefix("promo-"))
        XCTAssertEqual(slug.count, "promo-".count + 4)
        XCTAssertFalse(slug.contains("{rand}"))
    }

    func testSlugSanitization() {
        XCTAssertEqual(ShortenRulesEngine.sanitizeSlug("Hello, World!"), "hello-world")
        XCTAssertEqual(ShortenRulesEngine.sanitizeSlug("--already--clean--"), "already-clean")
        XCTAssertEqual(ShortenRulesEngine.sanitizeSlug("Ünïcode Slug"), "ünïcode-slug")
        XCTAssertEqual(ShortenRulesEngine.sanitizeSlug("///"), "")

        let long = String(repeating: "a", count: 100)
        XCTAssertEqual(ShortenRulesEngine.sanitizeSlug(long).count, 64)
    }

    func testRuleMatchIsDeterministic() throws {
        _ = try store.saveShortenRule(ShortenRule(name: "All", urlPattern: "*"))
        let ctx = context("https://example.com/one")

        let matches = try (0..<5).map { _ in try engine.matchingRule(for: ctx)?.name }
        XCTAssertEqual(matches, Array(repeating: "All", count: 5))
    }
}

final class PasteStackTests: XCTestCase {
    private func makeItem(_ text: String, id: Int64) -> ClipboardItem {
        ClipboardItem(id: id, kind: .text, text: text, hash: "hash-\(id)")
    }

    func testQueueOrderAndCount() {
        let stack = PasteStack()
        XCTAssertFalse(stack.isActive)

        stack.enqueue([makeItem("one", id: 1), makeItem("two", id: 2)])
        stack.enqueue([makeItem("three", id: 3)])

        XCTAssertTrue(stack.isActive)
        XCTAssertEqual(stack.count, 3)
        XCTAssertEqual(stack.peek()?.text, "one")
        XCTAssertEqual(stack.popNext()?.text, "one")
        XCTAssertEqual(stack.popNext()?.text, "two")
        XCTAssertEqual(stack.count, 1)
        XCTAssertEqual(stack.popNext()?.text, "three")
        XCTAssertNil(stack.popNext())
        XCTAssertFalse(stack.isActive)
    }

    func testClear() {
        let stack = PasteStack()
        stack.enqueue([makeItem("one", id: 1)])
        stack.clear()
        XCTAssertFalse(stack.isActive)
        XCTAssertNil(stack.popNext())
    }

    func testPasteNextReportsRemaining() {
        let stack = PasteStack()
        stack.enqueue([makeItem("a", id: 1), makeItem("b", id: 2)])
        _ = stack.popNext()
        XCTAssertEqual(stack.count, 1)
        XCTAssertTrue(stack.isActive)
    }
}

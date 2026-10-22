import XCTest
@testable import Clipshot

final class SearchQueryParserTests: XCTestCase {
    private func assertParse(
        _ input: String,
        freeText: String = "",
        kind: ClipboardItemKind? = nil,
        fromApp: String? = nil,
        dateFilter: ParsedSearchQuery.DateFilter? = nil,
        pinboardName: String? = nil,
        phrase: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let parsed = SearchQueryParser.parse(input)
        XCTAssertEqual(parsed.freeText, freeText, "freeText for \(input)", file: file, line: line)
        XCTAssertEqual(parsed.kind, kind, "kind for \(input)", file: file, line: line)
        XCTAssertEqual(parsed.fromApp, fromApp, "fromApp for \(input)", file: file, line: line)
        XCTAssertEqual(parsed.dateFilter, dateFilter, "dateFilter for \(input)", file: file, line: line)
        XCTAssertEqual(
            parsed.pinboardName,
            pinboardName,
            "pinboardName for \(input)",
            file: file,
            line: line
        )
        XCTAssertEqual(parsed.phrase, phrase, "phrase for \(input)", file: file, line: line)
    }

    // MARK: - Empty and bare text

    func testEmptyQueryHasNoFilters() {
        assertParse("")
        assertParse("   \t\n ")
    }

    func testBareWordsBecomeFreeTextInOrder() {
        assertParse("hello world", freeText: "hello world")
        assertParse("  spaced   out  ", freeText: "spaced out")
        assertParse("kind:image clip kind:text", freeText: "clip", kind: .text)
        assertParse("\"quoted words\"", freeText: "quoted words")
    }

    // MARK: - kind

    func testKindAcceptsRawValuesCaseInsensitively() {
        let cases: [(String, ClipboardItemKind)] = [
            ("kind:text", .text),
            ("kind:url", .url),
            ("kind:rtf", .rtf),
            ("kind:image", .image),
            ("kind:file", .file),
            ("kind:color", .color),
            ("KIND:IMAGE", .image),
            ("Kind:Url", .url),
        ]
        for (input, expected) in cases {
            assertParse(input, kind: expected)
        }
    }

    func testKindAcceptsDisplayNamesIncludingQuotedSpaces() {
        assertParse("kind:Link", kind: .url)
        assertParse("kind:link", kind: .url)
        assertParse("kind:Text", kind: .text)
        assertParse("kind:\"Rich Text\"", kind: .rtf)
        assertParse("kind:Image", kind: .image)
        assertParse("kind:File", kind: .file)
        assertParse("kind:Color", kind: .color)
    }

    func testMalformedKindFallsBackToFreeText() {
        assertParse("kind:banana", freeText: "kind:banana")
        assertParse("kind:", freeText: "")
        assertParse("kind:\"\"", freeText: "")
    }

    // MARK: - from

    func testFromAcceptsQuotedAndBareValues() {
        assertParse("from:\"Safari\"", fromApp: "Safari")
        assertParse("from:Safari", fromApp: "Safari")
        assertParse("FROM:com.apple.Safari", fromApp: "com.apple.Safari")
        assertParse("from:\"My App\"", fromApp: "My App")
        assertParse("from:Notes clipboard", freeText: "clipboard", fromApp: "Notes")
    }

    func testEmptyFromIsIgnored() {
        assertParse("from:")
        assertParse("from:\"\"")
    }

    // MARK: - date

    func testDateAcceptsRelativeAndNamedValues() {
        let cases: [(String, ParsedSearchQuery.DateFilter)] = [
            ("date:7d", .lastHours(168)),
            ("date:24h", .lastHours(24)),
            ("date:30d", .lastHours(720)),
            ("date:1h", .lastHours(1)),
            ("date:today", .today),
            ("date:TODAY", .today),
            ("DATE:Yesterday", .yesterday),
        ]
        for (input, expected) in cases {
            assertParse(input, dateFilter: expected)
        }
    }

    func testMalformedDateFallsBackToFreeText() {
        assertParse("date:banana", freeText: "date:banana")
        assertParse("date:0d", freeText: "date:0d")
        assertParse("date:-5h", freeText: "date:-5h")
        assertParse("date:", freeText: "")
    }

    // MARK: - pinboard

    func testPinboardAcceptsBareAndQuotedNames() {
        assertParse("pinboard:Remote", pinboardName: "Remote")
        assertParse("pinboard:\"Remote Board\"", pinboardName: "Remote Board")
        assertParse("PINBOARD:Design", pinboardName: "Design")
    }

    func testEmptyPinboardIsIgnored() {
        assertParse("pinboard:")
        assertParse("pinboard:\"\"")
    }

    // MARK: - text phrase

    func testTextForcesExactPhrase() {
        assertParse("text:\"exact phrase\"", phrase: "exact phrase")
        assertParse("text:Solo", phrase: "Solo")
        assertParse("TEXT:\"Mixed Case\"", phrase: "Mixed Case")
    }

    func testEmptyTextIsIgnored() {
        assertParse("text:")
        assertParse("text:\"\"")
    }

    // MARK: - Composition and fallbacks

    func testAllKeysComposeInAnyOrder() {
        assertParse(
            "clip kind:image from:\"Safari\" date:7d pinboard:Remote text:\"hello world\"",
            freeText: "clip",
            kind: .image,
            fromApp: "Safari",
            dateFilter: .lastHours(168),
            pinboardName: "Remote",
            phrase: "hello world"
        )
        assertParse(
            "text:\"hello world\" pinboard:Remote date:24h from:Safari kind:file tail",
            freeText: "tail",
            kind: .file,
            fromApp: "Safari",
            dateFilter: .lastHours(24),
            pinboardName: "Remote",
            phrase: "hello world"
        )
    }

    func testUnknownKeysFallBackToFreeText() {
        assertParse("colour:red", freeText: "colour:red")
        assertParse("weird:\"a b\"", freeText: "weird:\"a b\"")
        assertParse("foo:bar baz", freeText: "foo:bar baz")
    }

    func testRepeatedKeysKeepLastValue() {
        assertParse("kind:image kind:text", kind: .text)
        assertParse("date:7d date:yesterday", dateFilter: .yesterday)
        assertParse("pinboard:Remote pinboard:Design", pinboardName: "Design")
        assertParse("text:first text:\"second phrase\"", phrase: "second phrase")
    }

    func testUnicodeValuesSurviveQuoting() {
        assertParse("from:\"日本語\"", fromApp: "日本語")
        assertParse("café ünïcode", freeText: "café ünïcode")
        assertParse("pinboard:\"Équipe\"", pinboardName: "Équipe")
    }

    // MARK: - Tokenizer

    func testTokenizerKeepsQuotedSpansTogether() {
        XCTAssertEqual(
            SearchQueryParser.tokenize("a \"b c\" d"),
            ["a", "\"b c\"", "d"]
        )
        XCTAssertEqual(
            SearchQueryParser.tokenize("from:\"Safari\" kind:image"),
            ["from:\"Safari\"", "kind:image"]
        )
    }

    // MARK: - Date resolution

    func testDateFiltersResolveAgainstInjectedClock() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let lastDay = ParsedSearchQuery.DateFilter.lastHours(24)
            .interval(now: now, calendar: calendar)
        XCTAssertEqual(lastDay.start, now.addingTimeInterval(-86_400))
        XCTAssertEqual(lastDay.end, now)

        let startOfToday = calendar.startOfDay(for: now)
        let today = ParsedSearchQuery.DateFilter.today
            .interval(now: now, calendar: calendar)
        XCTAssertEqual(today.start, startOfToday)
        XCTAssertEqual(today.end, now)

        let yesterday = ParsedSearchQuery.DateFilter.yesterday
            .interval(now: now, calendar: calendar)
        XCTAssertEqual(
            yesterday.start,
            calendar.date(byAdding: .day, value: -1, to: startOfToday)
        )
        XCTAssertEqual(yesterday.end, startOfToday)
        XCTAssertLessThan(yesterday.start, yesterday.end)
    }
}

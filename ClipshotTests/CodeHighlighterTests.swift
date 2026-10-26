import SwiftUI
import XCTest
@testable import Clipshot

final class CodeHighlighterTests: XCTestCase {
    private func token(
        _ needle: String,
        in code: String,
        language: CodeLanguage
    ) -> HighlightTokenKind? {
        CodeHighlighter.tokens(in: code, language: language)
            .first { String(code[$0.range]) == needle }?.kind
    }

    func testSwiftTokens() {
        let code = """
        // greeting
        let name = "world"
        let count = 42
        let text: String = name
        """
        XCTAssertEqual(token("let", in: code, language: .swift), .keyword)
        XCTAssertEqual(token("// greeting", in: code, language: .swift), .comment)
        XCTAssertEqual(token("\"world\"", in: code, language: .swift), .string)
        XCTAssertEqual(token("42", in: code, language: .swift), .number)
        XCTAssertEqual(token("String", in: code, language: .swift), .type)
    }

    func testJavaScriptTokens() {
        let code = """
        // add
        const value = `hello`;
        const total = 42;
        """
        XCTAssertEqual(token("const", in: code, language: .javascript), .keyword)
        XCTAssertEqual(token("// add", in: code, language: .javascript), .comment)
        XCTAssertEqual(token("`hello`", in: code, language: .javascript), .string)
        XCTAssertEqual(token("42", in: code, language: .javascript), .number)
    }

    func testPythonTokens() {
        let code = """
        # note
        def greet(name):
            text = \"\"\"hello\"\"\"
            return None
        """
        XCTAssertEqual(token("def", in: code, language: .python), .keyword)
        XCTAssertEqual(token("# note", in: code, language: .python), .comment)
        XCTAssertEqual(token("\"\"\"hello\"\"\"", in: code, language: .python), .string)
        XCTAssertEqual(token("None", in: code, language: .python), .keyword)
    }

    func testJSONTokens() {
        let code = #"{"name":"clip","count":3,"ok":true}"#
        XCTAssertEqual(token("\"name\"", in: code, language: .json), .string)
        XCTAssertEqual(token("3", in: code, language: .json), .number)
        XCTAssertEqual(token("true", in: code, language: .json), .keyword)
    }

    func testSQLTokens() {
        let code = """
        -- query
        SELECT id FROM items WHERE name = 'clip';
        """
        XCTAssertEqual(token("SELECT", in: code, language: .sql), .keyword)
        XCTAssertEqual(token("-- query", in: code, language: .sql), .comment)
        XCTAssertEqual(token("'clip'", in: code, language: .sql), .string)
    }

    func testHTMLTokens() {
        let code = #"<div class="card">Hello</div>"#
        XCTAssertEqual(token("div", in: code, language: .html), .keyword)
        XCTAssertEqual(token("class", in: code, language: .html), .type)
        XCTAssertEqual(token("\"card\"", in: code, language: .html), .string)
    }

    func testCSSPropertyTokens() {
        let code = ".card { background-color: #ffffff; display: flex; padding: 12px; }"
        XCTAssertEqual(token("background-color", in: code, language: .css), .type)
        XCTAssertEqual(token("display", in: code, language: .css), .type)
        XCTAssertEqual(token("padding", in: code, language: .css), .type)
        XCTAssertEqual(token("#ffffff", in: code, language: .css), .number)
        XCTAssertEqual(token("12", in: code, language: .css), .number)
    }

    func testUnterminatedStringConsumesToEnd() {
        let code = "let value = \"oops"
        XCTAssertEqual(token("\"oops", in: code, language: .swift), .string)
    }

    func testTabsBecomeFourSpaces() {
        let attributed = CodeHighlighter.attributedPreview(
            "\tlet value = 1",
            language: .swift,
            colorScheme: .light
        )
        XCTAssertTrue(String(attributed.characters).hasPrefix("    let"))
    }

    func testAttributedTextIsPreserved() {
        let code = "import Foundation\n\nfunc value() -> Int {\n    return 1\n}"
        let attributed = CodeHighlighter.attributedPreview(
            code,
            language: .swift,
            colorScheme: .dark
        )
        XCTAssertEqual(String(attributed.characters), CodeHighlighter.preparedText(code))
    }

    func testPreviewIsBoundedByCharacters() {
        let code = String(repeating: "let value = 1234567890\n", count: 500)
        let prepared = CodeHighlighter.preparedText(code)
        XCTAssertLessThanOrEqual(prepared.count, CodeHighlighter.maxPreviewCharacters)
    }

    func testPreviewIsBoundedByLines() {
        let code = (0..<100).map { "let value\($0) = \($0)" }.joined(separator: "\n")
        let prepared = CodeHighlighter.preparedText(code)
        XCTAssertLessThanOrEqual(
            prepared.split(separator: "\n", omittingEmptySubsequences: false).count,
            CodeHighlighter.maxPreviewLines
        )
    }

    func testThemeDiffersBetweenLightAndDark() throws {
        let light = CodeTheme.colors(for: .light)
        let dark = CodeTheme.colors(for: .dark)
        let lightKeyword = try XCTUnwrap(light.keyword.usingColorSpace(.sRGB))
        let darkKeyword = try XCTUnwrap(dark.keyword.usingColorSpace(.sRGB))
        XCTAssertNotEqual(lightKeyword.redComponent, darkKeyword.redComponent, accuracy: 0.0001)
        XCTAssertNotEqual(lightKeyword.blueComponent, darkKeyword.blueComponent, accuracy: 0.0001)
    }

    func testAttributedRunsCarryTokenColors() {
        let attributed = CodeHighlighter.attributedPreview(
            "let value = 1",
            language: .swift,
            colorScheme: .dark
        )
        let keywordRun = attributed.runs.first {
            String(attributed[$0.range].characters) == "let"
        }
        XCTAssertNotNil(keywordRun)
        XCTAssertNotNil(keywordRun?.foregroundColor)
    }

    // Regression: stray characters inside an HTML "tag" (anything that is
    // not an HTML-name character, whitespace, `>`, `/` or `=`) used to make
    // tokenizeHTMLTag's attribute loop spin forever without advancing,
    // permanently pinning a cooperative thread at 100% CPU per offending
    // clipboard item. Observed live: Clipshot at ~196% CPU with two items
    // (`a < b && c > d`-style text detected as HTML) stuck in the loop.
    // A regression here is an infinite loop, so every case is bounded by an
    // expectation: fail on timeout instead of hanging the suite.
    func testHTMLTagWithStrayCharactersTerminates() {
        let samples = [
            "a < b && c > d",
            "<div ?x>hi</div>",
            "<3 <3 coffee",
            "if (a<b) { x = a<b ? 1 : 2 }",
            "<span \u{1F600}>emoji</span>",
        ]
        let done = expectation(description: "tokenizes without hanging")
        DispatchQueue.global(qos: .utility).async {
            for sample in samples {
                let tokens = CodeHighlighter.tokens(in: sample, language: .html)
                for token in tokens {
                    XCTAssertLessThanOrEqual(token.range.lowerBound, token.range.upperBound)
                }
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    func testAttributedPreviewTerminatesOnStrayTagCharacters() {
        let done = expectation(description: "preview builds")
        DispatchQueue.global(qos: .utility).async {
            let result = CodeHighlighter.attributedPreview(
                "a < b && c > d",
                language: .html,
                colorScheme: .light
            )
            XCTAssertFalse(result.runs.isEmpty)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }
}

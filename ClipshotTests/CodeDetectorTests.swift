import XCTest
@testable import Clipshot

final class CodeDetectorTests: XCTestCase {
    func testDetectsSwift() {
        let code = """
        import SwiftUI

        @MainActor
        final class Panel {
            func show() -> Int {
                guard let value = optional else { return 0 }
                return value
            }
        }
        """
        XCTAssertEqual(CodeDetector.detect(code), .swift)
    }

    func testDetectsJavaScript() {
        let code = """
        const add = (a, b) => {
          return a + b;
        };
        console.log(add(1, 2));
        """
        XCTAssertEqual(CodeDetector.detect(code), .javascript)
    }

    func testDetectsTypeScript() {
        let code = """
        interface User {
          id: number;
          name: string;
        }

        export function greet(user: User): string {
          return `Hello ${user.name}`;
        }
        """
        XCTAssertEqual(CodeDetector.detect(code), .javascript)
    }

    func testDetectsPython() {
        let code = """
        def greet(name):
            if name:
                print(f"Hello {name}")
            return None
        """
        XCTAssertEqual(CodeDetector.detect(code), .python)
    }

    func testDetectsJSONObject() {
        XCTAssertEqual(
            CodeDetector.detect(#"{"name":"clip","count":3,"items":[1,2,3]}"#),
            .json
        )
    }

    func testDetectsJSONArray() {
        XCTAssertEqual(
            CodeDetector.detect(#"[{"id":1,"title":"one"},{"id":2,"title":"two"}]"#),
            .json
        )
    }

    func testDetectsShellScript() {
        let code = """
        #!/bin/bash
        set -e
        for file in *.txt; do
          echo "$file"
        done
        """
        XCTAssertEqual(CodeDetector.detect(code), .shell)
    }

    func testDetectsSQL() {
        let code = "SELECT id, name FROM items WHERE pinned = 1 ORDER BY created_at DESC;"
        XCTAssertEqual(CodeDetector.detect(code), .sql)
    }

    func testDetectsHTML() {
        let code = """
        <!DOCTYPE html>
        <html>
          <body><div class="card">Hello</div></body>
        </html>
        """
        XCTAssertEqual(CodeDetector.detect(code), .html)
    }

    func testDetectsCSS() {
        let code = """
        .card {
          display: flex;
          color: #ffffff;
          padding: 12px;
        }
        """
        XCTAssertEqual(CodeDetector.detect(code), .css)
    }

    func testDetectsCFamily() {
        let code = """
        #include <stdio.h>

        int main(void) {
            printf("hello\\n");
            return 0;
        }
        """
        XCTAssertEqual(CodeDetector.detect(code), .cLike)
    }

    func testDetectsIndentedMultilineCode() {
        let code = """
        import Foundation

        struct Store {
            let items: [String]

            func first() -> String? {
                items.first
            }
        }
        """
        XCTAssertEqual(CodeDetector.detect(code), .swift)
    }

    func testDetectsShortSingleLineCode() {
        XCTAssertEqual(CodeDetector.detect("const answer = 42;"), .javascript)
        XCTAssertEqual(CodeDetector.detect("def greet(name):"), .python)
    }

    func testDoesNotDetectProseParagraph() {
        let prose = """
        The quick brown fox jumps over the lazy dog. It was a bright cold day in April, and the clocks were striking thirteen. She walked to the window and looked out at the rain, wondering whether the train would be on time.
        """
        XCTAssertNil(CodeDetector.detect(prose))
    }

    func testDoesNotDetectEmail() {
        let email = """
        Hi John,

        Thanks for the update. Let's meet at 3pm on Tuesday to review the notes — I'll bring the drafts.

        Best,
        Ernest
        """
        XCTAssertNil(CodeDetector.detect(email))
    }

    func testDoesNotDetectProseWithDashesAndParentheses() {
        let prose = """
        The project — which had been delayed twice — finally shipped (to everyone's relief). We celebrated with coffee, then went back to work.
        """
        XCTAssertNil(CodeDetector.detect(prose))
    }

    func testDoesNotDetectSingleWord() {
        XCTAssertNil(CodeDetector.detect("hello"))
    }

    func testDoesNotDetectDatesOrIdentifiers() {
        XCTAssertNil(CodeDetector.detect("2026-10-21"))
        XCTAssertNil(CodeDetector.detect("ABC-12345"))
    }

    func testDoesNotDetectURLPlusProse() {
        let text = "Check out https://example.com/docs for the details — it explains everything clearly."
        XCTAssertNil(CodeDetector.detect(text))
    }

    func testDoesNotDetectOneLineNaturalLanguage() {
        XCTAssertNil(CodeDetector.detect("Please review the attached document before Friday."))
    }

    func testDoesNotDetectJSONLikeProse() {
        XCTAssertNil(CodeDetector.detect("The set {a, b, c} contains three elements."))
    }

    func testEmptyAndWhitespaceAreNotCode() {
        XCTAssertNil(CodeDetector.detect(""))
        XCTAssertNil(CodeDetector.detect("   \n\t\n  "))
    }

    func testHandlesCRLF() {
        let code = "import Foundation\r\n\r\nfunc value() -> Int {\r\n    return 1\r\n}\r\n"
        XCTAssertEqual(CodeDetector.detect(code), .swift)
    }

    func testLargeInputUsesBoundedPrefix() {
        let code = "import Foundation\nfunc value() -> Int { 1 }\n"
            + String(repeating: "// filler\n", count: 2_000)
        XCTAssertEqual(CodeDetector.detect(code), .swift)
    }
}

import XCTest
@testable import Clipshot

final class ColorCardStyleTests: XCTestCase {
    private func foreground(_ input: String) -> ColorCardForeground? {
        guard let color = ClipboardColorParser.parse(input) else { return nil }
        return ColorCardStyle.foreground(for: color)
    }

    func testWhiteUsesBlackText() {
        XCTAssertEqual(foreground("#ffffff"), .black)
    }

    func testBlackUsesWhiteText() {
        XCTAssertEqual(foreground("#000000"), .white)
    }

    func testDarkRedUsesWhiteText() {
        XCTAssertEqual(foreground("#a51a15"), .white)
    }

    func testKhakiUsesBlackText() {
        XCTAssertEqual(foreground("khaki"), .black)
    }

    func testLightYellowUsesBlackText() {
        XCTAssertEqual(foreground("lightyellow"), .black)
    }

    func testTranslucentBlueUsesWhiteTextOnDarkCard() throws {
        let color = try XCTUnwrap(ClipboardColorParser.parse("rgba(30,144,255,0.6)"))
        XCTAssertEqual(
            ColorCardStyle.foreground(for: color, over: ColorCardStyle.darkBackground),
            .white
        )
    }

    func testTranslucentBlueUsesBlackTextOnLightCard() throws {
        let color = try XCTUnwrap(ClipboardColorParser.parse("rgba(30,144,255,0.6)"))
        XCTAssertEqual(
            ColorCardStyle.foreground(for: color, over: ColorCardStyle.lightBackground),
            .black
        )
    }

    func testMidLuminanceBoundaryUsesBlackText() {
        // ~0.18 relative luminance: just above the WCAG crossover.
        XCTAssertEqual(foreground("#767676"), .black)
        // ~0.15 relative luminance: below the crossover.
        XCTAssertEqual(foreground("#6e6e6e"), .white)
    }

    func testLegacyTextAndRTFColorItemsResolveToColorForDisplay() {
        let text = ClipboardItem(kind: .text, text: "#ff0000", hash: "text-color")
        XCTAssertEqual(text.displayKind, .color)

        let rich = ClipboardItem(kind: .rtf, text: "rgba(30,144,255,0.6)", hash: "rtf-color")
        XCTAssertEqual(rich.displayKind, .color)

        let prose = ClipboardItem(kind: .text, text: "hello #ff0000", hash: "prose")
        XCTAssertEqual(prose.displayKind, .text)

        let code = ClipboardItem(kind: .text, text: "let value = 1", hash: "code")
        XCTAssertEqual(code.displayKind, .text)

        let url = ClipboardItem(kind: .url, text: "https://example.com", hash: "url")
        XCTAssertEqual(url.displayKind, .url)
    }
}

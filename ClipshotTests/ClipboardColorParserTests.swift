import XCTest
@testable import Clipshot

final class ClipboardColorParserTests: XCTestCase {
    private func assertColor(
        _ input: String,
        red: Double,
        green: Double,
        blue: Double,
        alpha: Double = 1,
        accuracy: Double = 0.01,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let color = ClipboardColorParser.parse(input) else {
            XCTFail("Expected \(input) to parse", file: file, line: line)
            return
        }
        XCTAssertEqual(color.red, red, accuracy: accuracy, "red for \(input)", file: file, line: line)
        XCTAssertEqual(color.green, green, accuracy: accuracy, "green for \(input)", file: file, line: line)
        XCTAssertEqual(color.blue, blue, accuracy: accuracy, "blue for \(input)", file: file, line: line)
        XCTAssertEqual(color.alpha, alpha, accuracy: accuracy, "alpha for \(input)", file: file, line: line)
    }

    // MARK: - Hex

    func testHexThreeDigits() {
        assertColor("#f00", red: 1, green: 0, blue: 0)
        assertColor("#0F0", red: 0, green: 1, blue: 0)
        assertColor("#00f", red: 0, green: 0, blue: 1)
    }

    func testHexFourDigits() {
        assertColor("#f008", red: 1, green: 0, blue: 0, alpha: 0x88 / 255.0)
    }

    func testHexSixDigits() {
        assertColor("#ff0000", red: 1, green: 0, blue: 0)
        assertColor("#3498db", red: 0x34 / 255.0, green: 0x98 / 255.0, blue: 0xdb / 255.0)
    }

    func testHexEightDigits() {
        assertColor("#FF000080", red: 1, green: 0, blue: 0, alpha: 0x80 / 255.0)
        assertColor("#12345678", red: 0x12 / 255.0, green: 0x34 / 255.0, blue: 0x56 / 255.0, alpha: 0x78 / 255.0)
    }

    func testHexRejectsInvalid() {
        XCTAssertNil(ClipboardColorParser.parse("#ff00001"))
        XCTAssertNil(ClipboardColorParser.parse("#gggggg"))
        XCTAssertNil(ClipboardColorParser.parse("#"))
        XCTAssertNil(ClipboardColorParser.parse("#ff0000 trailing"))
    }

    // MARK: - rgb()/rgba()

    func testRGBCommaAndSpaceSyntax() {
        assertColor("rgb(255, 0, 0)", red: 1, green: 0, blue: 0)
        assertColor("rgb(255 0 0)", red: 1, green: 0, blue: 0)
        assertColor("rgb(0, 128, 255)", red: 0, green: 0x80 / 255.0, blue: 1)
    }

    func testRGBPercentages() {
        assertColor("rgb(100%, 0%, 0%)", red: 1, green: 0, blue: 0)
        assertColor("rgb(50% 100% 0%)", red: 0.5, green: 1, blue: 0)
    }

    func testRGBAlphaVariants() {
        assertColor("rgb(255 0 0 / 50%)", red: 1, green: 0, blue: 0, alpha: 0.5)
        assertColor("rgba(255, 0, 0, 0.5)", red: 1, green: 0, blue: 0, alpha: 0.5)
        assertColor("rgba(255 0 0 / 25%)", red: 1, green: 0, blue: 0, alpha: 0.25)
        assertColor("rgba(255, 0, 0, 25%)", red: 1, green: 0, blue: 0, alpha: 0.25)
    }

    func testRGBRejectsOutOfRangeAndMissingComponents() {
        XCTAssertNil(ClipboardColorParser.parse("rgb(256, 0, 0)"))
        XCTAssertNil(ClipboardColorParser.parse("rgb(-1, 0, 0)"))
        XCTAssertNil(ClipboardColorParser.parse("rgb(101%, 0%, 0%)"))
        XCTAssertNil(ClipboardColorParser.parse("rgba(255, 0, 0, 1.2)"))
        XCTAssertNil(ClipboardColorParser.parse("rgba(255, 0, 0, -0.1)"))
        XCTAssertNil(ClipboardColorParser.parse("rgb(255, 0)"))
        XCTAssertNil(ClipboardColorParser.parse("rgb(255, 0, 0, 0.5, 0.2)"))
    }

    // MARK: - hsl()/hsla()

    func testHSLBasics() {
        assertColor("hsl(120, 100%, 50%)", red: 0, green: 1, blue: 0)
        assertColor("hsl(0 100% 50%)", red: 1, green: 0, blue: 0)
        assertColor("hsl(360 100% 50%)", red: 1, green: 0, blue: 0)
        assertColor("hsl(240 100% 50%)", red: 0, green: 0, blue: 1)
        assertColor("hsl(120deg 100% 50%)", red: 0, green: 1, blue: 0)
    }

    func testHSLAlphaAndGray() {
        assertColor("hsl(120 100% 50% / 0.5)", red: 0, green: 1, blue: 0, alpha: 0.5)
        assertColor("hsla(240, 100%, 50%, 0.25)", red: 0, green: 0, blue: 1, alpha: 0.25)
        assertColor("hsl(0 0% 50%)", red: 0.5, green: 0.5, blue: 0.5)
    }

    func testHSLRejectsOutOfRange() {
        XCTAssertNil(ClipboardColorParser.parse("hsl(120, 101%, 50%)"))
        XCTAssertNil(ClipboardColorParser.parse("hsl(120, 100%, 101%)"))
        XCTAssertNil(ClipboardColorParser.parse("hsl(120, 100%)"))
        XCTAssertNil(ClipboardColorParser.parse("hsl(120, 100%, 50%, 1.5)"))
    }

    // MARK: - OKLCH / OKLab

    func testOKLCHRedRoundsTripToSRGB() {
        guard let color = ClipboardColorParser.parse("oklch(0.62796 0.25768 29.234)") else {
            return XCTFail("Expected oklch red to parse")
        }
        XCTAssertGreaterThan(color.red, 0.92)
        XCTAssertLessThan(color.green, 0.25)
        XCTAssertLessThan(color.blue, 0.25)
    }

    func testOKCHLIsTreatedAsOKLCH() {
        let canonical = ClipboardColorParser.parse("oklch(0.62796 0.25768 29.234)")
        let typo = ClipboardColorParser.parse("okchl(0.62796 0.25768 29.234)")
        XCTAssertNotNil(canonical)
        XCTAssertEqual(canonical, typo)

        let upper = ClipboardColorParser.parse("OKCHL(0.62796 0.25768 29.234)")
        XCTAssertEqual(canonical, upper)
    }

    func testOKLCHHueDefaultsToZero() {
        let withHue = ClipboardColorParser.parse("oklch(0.7 0.15 0)")
        let withoutHue = ClipboardColorParser.parse("oklch(0.7 0.15)")
        XCTAssertNotNil(withHue)
        XCTAssertEqual(withHue, withoutHue)
    }

    func testOKLCHWhiteBlackAndPercentLightness() {
        assertColor("oklch(1 0 0)", red: 1, green: 1, blue: 1, accuracy: 0.02)
        assertColor("oklch(0 0 0)", red: 0, green: 0, blue: 0, accuracy: 0.02)
        assertColor("oklch(62.796% 0.25768 29.234)", red: 1, green: 0, blue: 0, accuracy: 0.08)
    }

    func testOKLabRed() {
        guard let color = ClipboardColorParser.parse("oklab(0.62796 0.22486 0.12585)") else {
            return XCTFail("Expected oklab red to parse")
        }
        XCTAssertGreaterThan(color.red, 0.85)
        XCTAssertLessThan(color.green, 0.3)
        XCTAssertLessThan(color.blue, 0.3)
    }

    func testOKLCHRejectsOutOfRange() {
        XCTAssertNil(ClipboardColorParser.parse("oklch(1.5 0.1 0)"))
        XCTAssertNil(ClipboardColorParser.parse("oklch(-0.1 0.1 0)"))
        XCTAssertNil(ClipboardColorParser.parse("oklch(0.6 0.6 0)"))
        XCTAssertNil(ClipboardColorParser.parse("oklch(0.6 -0.1 0)"))
        XCTAssertNil(ClipboardColorParser.parse("oklch(0.6 0.1 0 / 2)"))
        XCTAssertNil(ClipboardColorParser.parse("oklab(0.6 2 0)"))
    }

    // MARK: - Named colors

    func testNamedColors() {
        assertColor("red", red: 1, green: 0, blue: 0)
        assertColor("ReBeCcApUrPlE", red: 0x66 / 255.0, green: 0x33 / 255.0, blue: 0x99 / 255.0)
        assertColor("  blue\n", red: 0, green: 0, blue: 1)
        assertColor("transparent", red: 0, green: 0, blue: 0, alpha: 0)
        assertColor("white", red: 1, green: 1, blue: 1)
    }

    // MARK: - Whole-string requirement

    func testRejectsMixedContent() {
        XCTAssertNil(ClipboardColorParser.parse("hello #ff0000"))
        XCTAssertNil(ClipboardColorParser.parse("#ff0000 hello"))
        XCTAssertNil(ClipboardColorParser.parse("red blue"))
        XCTAssertNil(ClipboardColorParser.parse("rgb(255, 0, 0) extra"))
        XCTAssertNil(ClipboardColorParser.parse("color: red"))
        XCTAssertNil(ClipboardColorParser.parse(""))
        XCTAssertNil(ClipboardColorParser.parse("   \n\t"))
        XCTAssertNil(ClipboardColorParser.parse("rgb(255, 0, 0"))
        XCTAssertNil(ClipboardColorParser.parse("rgb(255, 0, 0))"))
    }
}

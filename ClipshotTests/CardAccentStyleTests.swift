import AppKit
import XCTest
@testable import Clipshot

final class CardAccentStyleTests: XCTestCase {
    private let safariBlue = NSColor(srgbRed: 0.094, green: 0.555, blue: 0.885, alpha: 1)
    private let notesYellow = NSColor(srgbRed: 0.905, green: 0.761, blue: 0.101, alpha: 1)
    private let darkBackground = (red: 0.11, green: 0.11, blue: 0.12)

    func testUnselectedTintIsVisiblyOpaque() {
        let border = CardAccentStyle.borderTint(for: safariBlue, isSelected: false)
        let background = CardAccentStyle.backgroundTint(for: safariBlue, isSelected: false)

        XCTAssertEqual(border?.opacity, 0.7)
        XCTAssertEqual(background?.opacity, 0.13)
        XCTAssertGreaterThanOrEqual(border?.opacity ?? 0, 0.5)
        XCTAssertGreaterThanOrEqual(background?.opacity ?? 0, 0.10)
    }

    func testSelectedTintIsStrongerThanUnselected() {
        let selectedBorder = CardAccentStyle.borderTint(for: safariBlue, isSelected: true)
        let unselectedBorder = CardAccentStyle.borderTint(for: safariBlue, isSelected: false)
        let selectedBackground = CardAccentStyle.backgroundTint(for: safariBlue, isSelected: true)
        let unselectedBackground = CardAccentStyle.backgroundTint(for: safariBlue, isSelected: false)

        XCTAssertGreaterThan(selectedBorder?.opacity ?? 0, unselectedBorder?.opacity ?? 0)
        XCTAssertGreaterThan(selectedBackground?.opacity ?? 0, unselectedBackground?.opacity ?? 0)
        XCTAssertGreaterThan(
            CardAccentStyle.borderWidth(isSelected: true),
            CardAccentStyle.borderWidth(isSelected: false)
        )
    }

    func testRenderedBlueBorderIsPerceptiblyBlueOverDarkBackground() throws {
        let tint = try XCTUnwrap(CardAccentStyle.borderTint(for: safariBlue, isSelected: false))
        let rendered = tint.composited(over: darkBackground)

        XCTAssertGreaterThan(rendered.blue, rendered.red + 0.25)
        XCTAssertGreaterThan(rendered.blue, rendered.green + 0.10)
        XCTAssertGreaterThan(rendered.blue, 0.5)
    }

    func testRenderedYellowBorderIsPerceptiblyYellowOverDarkBackground() throws {
        let tint = try XCTUnwrap(CardAccentStyle.borderTint(for: notesYellow, isSelected: false))
        let rendered = tint.composited(over: darkBackground)

        XCTAssertGreaterThan(rendered.red, rendered.blue + 0.3)
        XCTAssertGreaterThan(rendered.green, rendered.blue + 0.3)
        XCTAssertGreaterThan(rendered.red, 0.5)
    }

    func testBackgroundWashCarriesTheHue() throws {
        let tint = try XCTUnwrap(CardAccentStyle.backgroundTint(for: safariBlue, isSelected: false))
        let rendered = tint.composited(over: darkBackground)

        XCTAssertGreaterThan(rendered.blue, rendered.red + 0.05)
        XCTAssertGreaterThan(rendered.blue, rendered.green + 0.02)
    }

    func testMissingAccentProducesNoTint() {
        XCTAssertNil(CardAccentStyle.borderTint(for: nil, isSelected: false))
        XCTAssertNil(CardAccentStyle.backgroundTint(for: nil, isSelected: true))
    }
}

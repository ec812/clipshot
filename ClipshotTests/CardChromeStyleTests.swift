import AppKit
import XCTest
@testable import Clipshot

final class CardChromeStyleTests: XCTestCase {
    private let safariBlue = NSColor(
        srgbRed: 0.094,
        green: 0.555,
        blue: 0.885,
        alpha: 1
    )

    func testBandTintIsStrongerInDarkModeAndWhenSelected() throws {
        let dark = try XCTUnwrap(
            CardChromeStyle.bandTint(
                for: safariBlue,
                isSelected: false,
                colorScheme: .dark
            )
        )
        let light = try XCTUnwrap(
            CardChromeStyle.bandTint(
                for: safariBlue,
                isSelected: false,
                colorScheme: .light
            )
        )
        let selectedDark = try XCTUnwrap(
            CardChromeStyle.bandTint(
                for: safariBlue,
                isSelected: true,
                colorScheme: .dark
            )
        )

        XCTAssertEqual(dark.opacity, 0.34, accuracy: 0.001)
        XCTAssertEqual(light.opacity, 0.20, accuracy: 0.001)
        XCTAssertEqual(selectedDark.opacity, 0.40, accuracy: 0.001)
        XCTAssertGreaterThan(dark.opacity, light.opacity)
        XCTAssertGreaterThan(selectedDark.opacity, dark.opacity)
        XCTAssertEqual(dark.red, 0.094, accuracy: 0.001)
        XCTAssertEqual(dark.green, 0.555, accuracy: 0.001)
        XCTAssertEqual(dark.blue, 0.885, accuracy: 0.001)
    }

    func testMissingAccentHasNoTint() {
        XCTAssertNil(
            CardChromeStyle.bandTint(
                for: nil,
                isSelected: false,
                colorScheme: .dark
            )
        )
        XCTAssertNil(
            CardChromeStyle.bandTint(
                for: nil,
                isSelected: true,
                colorScheme: .light
            )
        )
    }

    func testFullAndCompactChromeDimensions() {
        XCTAssertEqual(CardChromeStyle.bandHeight(compact: false), 58)
        XCTAssertEqual(CardChromeStyle.bandHeight(compact: true), 50)
        XCTAssertEqual(CardChromeStyle.iconSize(compact: false), 40)
        XCTAssertEqual(CardChromeStyle.iconSize(compact: true), 32)
        XCTAssertEqual(CardChromeStyle.footerHeight(compact: false), 36)
        XCTAssertEqual(CardChromeStyle.footerHeight(compact: true), 32)
        XCTAssertEqual(CardChromeStyle.footerButtonSize(compact: false), 30)
        XCTAssertEqual(CardChromeStyle.footerButtonSize(compact: true), 26)
        XCTAssertEqual(CardChromeStyle.cornerRadius, 14)
        XCTAssertEqual(CardChromeStyle.fullOverlayMinimum, 450)
    }

    func testCompactThresholdBoundary() {
        XCTAssertTrue(CardChromeStyle.isCompact(overlayHeight: 449, alwaysCompact: false))
        XCTAssertFalse(CardChromeStyle.isCompact(overlayHeight: 450, alwaysCompact: false))
        XCTAssertFalse(CardChromeStyle.isCompact(overlayHeight: 560, alwaysCompact: false))
        XCTAssertTrue(CardChromeStyle.isCompact(overlayHeight: 560, alwaysCompact: true))
    }
}

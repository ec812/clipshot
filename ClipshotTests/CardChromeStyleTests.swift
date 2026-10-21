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

    private func assertThumbnailSize(
        image: CGSize,
        compact: Bool,
        width: CGFloat,
        height: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let size = CardChromeStyle.thumbnailSize(for: image, compact: compact)
        XCTAssertEqual(size.width, width, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(size.height, height, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(
            size.width / size.height,
            image.width / image.height,
            accuracy: 0.001,
            "aspect ratio must be preserved",
            file: file,
            line: line
        )
    }

    func testThumbnailSizeFillsWidthForLandscapeAndCapsPortrait() {
        XCTAssertEqual(CardChromeStyle.cardWidth, 360)
        XCTAssertEqual(CardChromeStyle.thumbnailWidth, 336)
        XCTAssertEqual(CardChromeStyle.thumbnailMaxHeight, 220)
        XCTAssertEqual(CardChromeStyle.compactThumbnailMaxHeight, 200)

        // Landscape fills the width.
        assertThumbnailSize(
            image: CGSize(width: 1600, height: 400),
            compact: false,
            width: 336,
            height: 84
        )
        assertThumbnailSize(
            image: CGSize(width: 1600, height: 900),
            compact: false,
            width: 336,
            height: 189
        )

        // Portrait is height-capped with auto width.
        assertThumbnailSize(
            image: CGSize(width: 600, height: 1800),
            compact: false,
            width: 73.333,
            height: 220
        )
        assertThumbnailSize(
            image: CGSize(width: 600, height: 1800),
            compact: true,
            width: 66.667,
            height: 200
        )

        // At 1:1 the height cap wins.
        assertThumbnailSize(
            image: CGSize(width: 800, height: 800),
            compact: false,
            width: 220,
            height: 220
        )
        assertThumbnailSize(
            image: CGSize(width: 800, height: 800),
            compact: true,
            width: 200,
            height: 200
        )
    }

    func testThumbnailSizeCompactStillFillsWidthForStandardLandscape() {
        assertThumbnailSize(
            image: CGSize(width: 1600, height: 900),
            compact: true,
            width: 336,
            height: 189
        )
        assertThumbnailSize(
            image: CGSize(width: 1600, height: 400),
            compact: true,
            width: 336,
            height: 84
        )
    }

    func testThumbnailSizeAtExactBoundaryAndInvalidSizes() {
        // 336/220 is the aspect where both bounds bind.
        assertThumbnailSize(
            image: CGSize(width: 336, height: 220),
            compact: false,
            width: 336,
            height: 220
        )

        XCTAssertEqual(
            CardChromeStyle.thumbnailSize(for: .zero, compact: false),
            .zero
        )
        XCTAssertEqual(
            CardChromeStyle.thumbnailSize(
                for: CGSize(width: 0, height: 100),
                compact: false
            ),
            .zero
        )
    }
}

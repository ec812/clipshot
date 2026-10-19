import AppKit
import XCTest
@testable import Clipshot

final class AppIconAccentTests: XCTestCase {
    private func solidImage(
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        alpha: CGFloat = 1,
        size: Int = 64
    ) -> NSImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(
            colorSpace: colorSpace,
            components: [red, green, blue, alpha]
        )!)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        let cgImage = context.makeImage()!
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }

    private func transparentImage(size: Int = 64) -> NSImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.clear(CGRect(x: 0, y: 0, width: size, height: size))
        let cgImage = context.makeImage()!
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }

    private func components(_ color: NSColor) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let rgb = color.usingColorSpace(.sRGB)!
        return (rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
    }

    func testSolidRedIconProducesRedAccent() {
        let accent = AppIconAccent.dominantAccent(from: solidImage(red: 1, green: 0, blue: 0))
        guard let accent else { return XCTFail("Expected an accent") }
        let rgb = components(accent)
        XCTAssertGreaterThan(rgb.r, 0.85)
        XCTAssertLessThan(rgb.g, 0.2)
        XCTAssertLessThan(rgb.b, 0.2)
    }

    func testSolidBlueIconProducesBlueAccent() {
        let accent = AppIconAccent.dominantAccent(from: solidImage(red: 0.1, green: 0.35, blue: 1))
        guard let accent else { return XCTFail("Expected an accent") }
        let rgb = components(accent)
        XCTAssertLessThan(rgb.r, 0.25)
        XCTAssertLessThan(rgb.g, 0.5)
        XCTAssertGreaterThan(rgb.b, 0.85)
    }

    func testSolidGreenIconProducesGreenAccent() {
        let accent = AppIconAccent.dominantAccent(from: solidImage(red: 0.1, green: 0.85, blue: 0.2))
        guard let accent else { return XCTFail("Expected an accent") }
        let rgb = components(accent)
        XCTAssertLessThan(rgb.r, 0.25)
        XCTAssertGreaterThan(rgb.g, 0.8)
        XCTAssertLessThan(rgb.b, 0.3)
    }

    func testHueIsPreservedAcrossPrimaryIcons() {
        let cases: [(String, CGFloat, CGFloat, CGFloat, (CGFloat, CGFloat, CGFloat) -> Bool)] = [
            ("red", 1, 0, 0, { $0 > $1 && $0 > $2 }),
            ("green", 0, 1, 0, { $1 > $0 && $1 > $2 }),
            ("blue", 0, 0, 1, { $2 > $0 && $2 > $1 })
        ]

        for (name, red, green, blue, isExpectedDominant) in cases {
            let accent = AppIconAccent.dominantAccent(
                from: solidImage(red: red, green: green, blue: blue)
            )
            guard let accent else {
                XCTFail("Expected an accent for \(name)")
                continue
            }
            let rgb = components(accent)
            XCTAssertTrue(
                isExpectedDominant(rgb.r, rgb.g, rgb.b),
                "\(name) accent lost its dominant hue: R=\(rgb.r) G=\(rgb.g) B=\(rgb.b)"
            )
        }
    }

    func testGrayIconHasNoAccent() {
        XCTAssertNil(AppIconAccent.dominantAccent(from: solidImage(red: 0.5, green: 0.5, blue: 0.5)))
        XCTAssertNil(AppIconAccent.dominantAccent(from: solidImage(red: 0.95, green: 0.95, blue: 0.95)))
        XCTAssertNil(AppIconAccent.dominantAccent(from: solidImage(red: 0.02, green: 0.02, blue: 0.02)))
    }

    func testTransparentImageHasNoAccent() {
        XCTAssertNil(AppIconAccent.dominantAccent(from: transparentImage()))
        XCTAssertNil(AppIconAccent.dominantAccent(from: solidImage(red: 1, green: 0, blue: 0, alpha: 0)))
    }

    func testExtractionIsDeterministic() {
        let image = solidImage(red: 0.2, green: 0.8, blue: 0.3)
        guard let first = AppIconAccent.dominantAccent(from: image),
              let second = AppIconAccent.dominantAccent(from: image)
        else { return XCTFail("Expected accents") }

        let a = components(first)
        let b = components(second)
        XCTAssertEqual(a.r, b.r, accuracy: 0.0001)
        XCTAssertEqual(a.g, b.g, accuracy: 0.0001)
        XCTAssertEqual(a.b, b.b, accuracy: 0.0001)
    }

    func testPartiallyTransparentColorIsRecovered() {
        let accent = AppIconAccent.dominantAccent(
            from: solidImage(red: 1, green: 0, blue: 0, alpha: 0.75)
        )
        guard let accent else { return XCTFail("Expected an accent") }
        let rgb = components(accent)
        XCTAssertGreaterThan(rgb.r, 0.8)
        XCTAssertLessThan(rgb.g, 0.25)
        XCTAssertLessThan(rgb.b, 0.25)
    }
}

@MainActor
final class AppIconProviderCacheTests: XCTestCase {
    private var directory: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = fileManager.temporaryDirectory
            .appendingPathComponent("ClipshotIconCacheTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: directory)
        directory = nil
        try super.tearDownWithError()
    }

    func testLegacyCacheIsClearedOnceAndMarkedV2() throws {
        let legacyIcon = directory.appendingPathComponent("legacy.png")
        let legacyAccent = directory.appendingPathComponent("legacy.accent")
        try Data([0x01]).write(to: legacyIcon)
        try Data([0x02]).write(to: legacyAccent)

        _ = AppIconProvider(cacheDirectory: directory)

        XCTAssertFalse(fileManager.fileExists(atPath: legacyIcon.path))
        XCTAssertFalse(fileManager.fileExists(atPath: legacyAccent.path))
        let marker = directory.appendingPathComponent("cache-version")
        XCTAssertEqual(
            try String(contentsOf: marker, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
            "v2"
        )
    }

    func testCurrentVersionCacheIsPreserved() throws {
        _ = AppIconProvider(cacheDirectory: directory)

        let sentinel = directory.appendingPathComponent("sentinel.txt")
        try Data([0x03]).write(to: sentinel)

        _ = AppIconProvider(cacheDirectory: directory)
        XCTAssertTrue(fileManager.fileExists(atPath: sentinel.path))
    }
}

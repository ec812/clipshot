import AppKit
import Foundation
import XCTest
@testable import Clipshot

final class ClipboardPayloadReaderTests: XCTestCase {
    private var dataStore: ItemDataStore!
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipshotPayloadTests-\(UUID().uuidString)", isDirectory: true)
        dataStore = ItemDataStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        dataStore = nil
        directory = nil
        try super.tearDownWithError()
    }

    private func snapshot(
        fileURLs: [URL] = [],
        pngData: Data? = nil,
        tiffData: Data? = nil,
        rtfData: Data? = nil,
        colorData: Data? = nil,
        string: String? = nil
    ) -> PasteboardCaptureSnapshot {
        PasteboardCaptureSnapshot(
            fileURLs: fileURLs,
            pngData: pngData,
            tiffData: tiffData,
            rtfData: rtfData,
            colorData: colorData,
            string: string
        )
    }

    private func rtfData(for string: String) throws -> Data {
        let attributed = NSAttributedString(string: string)
        return try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    private func archivedColor(red: CGFloat, green: CGFloat, blue: CGFloat) throws -> Data {
        try NSKeyedArchiver.archivedData(
            withRootObject: NSColor(srgbRed: red, green: green, blue: blue, alpha: 1),
            requiringSecureCoding: false
        )
    }

    func testTextString() {
        let payload = ClipboardPayloadReader.process(snapshot(string: "hello world"), dataStore: dataStore)
        XCTAssertEqual(payload?.kind, .text)
        XCTAssertEqual(payload?.text, "hello world")
    }

    /// Rich sources (browsers, design tools, devtools) attach an RTF flavor to
    /// copied color text. The color classification must win over RTF.
    func testColorStringWithRTFFlavorIsClassifiedAsColor() throws {
        let payload = ClipboardPayloadReader.process(
            snapshot(rtfData: try rtfData(for: "#ff0000"), string: "#ff0000"),
            dataStore: dataStore
        )
        XCTAssertEqual(payload?.kind, .color)
        XCTAssertEqual(payload?.text, "#ff0000")
    }

    func testColorStringWithRTFAndColorDataIsClassifiedAsColor() throws {
        let payload = ClipboardPayloadReader.process(
            snapshot(
                rtfData: try rtfData(for: "rgba(255, 0, 0, 0.5)"),
                colorData: try archivedColor(red: 1, green: 0, blue: 0),
                string: "rgba(255, 0, 0, 0.5)"
            ),
            dataStore: dataStore
        )
        XCTAssertEqual(payload?.kind, .color)
        XCTAssertEqual(payload?.text, "#FF0000")
    }

    func testCMYKStringIsClassifiedAsColor() {
        let payload = ClipboardPayloadReader.process(
            snapshot(string: "cmyk(0,100,100,0)"),
            dataStore: dataStore
        )
        XCTAssertEqual(payload?.kind, .color)
        XCTAssertEqual(payload?.text, "cmyk(0,100,100,0)")
    }

    func testHashlessHexStringIsClassifiedAsColor() {
        let payload = ClipboardPayloadReader.process(
            snapshot(string: "FF5733"),
            dataStore: dataStore
        )
        XCTAssertEqual(payload?.kind, .color)
        XCTAssertEqual(payload?.text, "FF5733")
    }

    func testGenuineRichTextRemainsRTF() throws {
        let payload = ClipboardPayloadReader.process(
            snapshot(rtfData: try rtfData(for: "hello rich text"), string: "hello rich text"),
            dataStore: dataStore
        )
        XCTAssertEqual(payload?.kind, .rtf)
        XCTAssertEqual(payload?.text, "hello rich text")
    }

    func testColorStringIsClassifiedAsColor() {
        let payload = ClipboardPayloadReader.process(snapshot(string: "#ff0000"), dataStore: dataStore)
        XCTAssertEqual(payload?.kind, .color)
        XCTAssertEqual(payload?.text, "#ff0000")
    }

    func testURLStringIsClassifiedAsURL() {
        let payload = ClipboardPayloadReader.process(
            snapshot(string: "https://example.com/article"),
            dataStore: dataStore
        )
        XCTAssertEqual(payload?.kind, .url)
    }

    func testURLCapturePathIsSynchronousAndDoesNotFetchPreviews() {
        let started = Date()
        let payload = ClipboardPayloadReader.process(
            snapshot(string: "https://example.com/article"),
            dataStore: dataStore
        )
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(payload?.kind, .url)
        XCTAssertNil(payload?.dataPath)
        XCTAssertLessThan(elapsed, 0.1)
    }

    func testFileURLs() {
        let url = URL(fileURLWithPath: "/tmp/clipshot-test.txt")
        let payload = ClipboardPayloadReader.process(snapshot(fileURLs: [url]), dataStore: dataStore)
        XCTAssertEqual(payload?.kind, .file)
        XCTAssertEqual(payload?.text, url.absoluteString)
        XCTAssertEqual(payload?.title, "clipshot-test.txt")
    }

    func testImageDataIsWrittenToDisk() throws {
        // 1×1 transparent PNG.
        let png = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2nWQAAAAASUVORK5CYII="
        ))
        let payload = try XCTUnwrap(
            ClipboardPayloadReader.process(snapshot(pngData: png), dataStore: dataStore)
        )

        XCTAssertEqual(payload.kind, .image)
        let path = try XCTUnwrap(payload.dataPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        XCTAssertEqual(dataStore.data(atPath: path), png)
    }

    func testEmptySnapshotProducesNoPayload() {
        XCTAssertNil(ClipboardPayloadReader.process(snapshot(), dataStore: dataStore))
    }
}

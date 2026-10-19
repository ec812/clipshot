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

    func testTextString() {
        let payload = ClipboardPayloadReader.process(snapshot(string: "hello world"), dataStore: dataStore)
        XCTAssertEqual(payload?.kind, .text)
        XCTAssertEqual(payload?.text, "hello world")
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

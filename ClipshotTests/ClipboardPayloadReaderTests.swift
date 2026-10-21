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

    // MARK: - Image/file classification

    static let pngBytes = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2nWQAAAAASUVORK5CYII="
    )!

    private func makeSourceFiles() throws -> (png: URL, pdf: URL) {
        let png = directory.appendingPathComponent("source-image.png")
        try Self.pngBytes.write(to: png)
        let pdf = directory.appendingPathComponent("document.pdf")
        try Data("%PDF-1.4\n".utf8).write(to: pdf)
        return (png, pdf)
    }

    func testImagePathStringIsClassifiedAsFile() throws {
        let files = try makeSourceFiles()
        let payload = ClipboardPayloadReader.process(
            snapshot(string: files.png.path),
            dataStore: dataStore
        )
        XCTAssertEqual(payload?.kind, .file)
        XCTAssertEqual(payload?.text, files.png.absoluteString)
        XCTAssertEqual(payload?.title, "source-image.png")
    }

    func testFileURLStringPointingAtImageIsClassifiedAsFile() throws {
        let files = try makeSourceFiles()
        let payload = ClipboardPayloadReader.process(
            snapshot(string: files.png.absoluteString),
            dataStore: dataStore
        )
        XCTAssertEqual(payload?.kind, .file)
        XCTAssertEqual(payload?.text, files.png.absoluteString)
    }

    func testNonImagePathStringsStayText() throws {
        let files = try makeSourceFiles()
        let missing = directory.appendingPathComponent("missing.png").path
        let directoryNamedLikeImage = directory.appendingPathComponent("folder.png")
        try FileManager.default.createDirectory(
            at: directoryNamedLikeImage,
            withIntermediateDirectories: true
        )

        XCTAssertEqual(
            ClipboardPayloadReader.process(snapshot(string: files.pdf.path), dataStore: dataStore)?.kind,
            .text
        )
        XCTAssertEqual(
            ClipboardPayloadReader.process(snapshot(string: missing), dataStore: dataStore)?.kind,
            .text
        )
        XCTAssertEqual(
            ClipboardPayloadReader.process(
                snapshot(string: "the file at \(files.png.path) is here"),
                dataStore: dataStore
            )?.kind,
            .text
        )
        XCTAssertEqual(
            ClipboardPayloadReader.process(
                snapshot(string: directoryNamedLikeImage.path),
                dataStore: dataStore
            )?.kind,
            .text
        )
    }

    func testPreviewImagePathForImageAndFileItems() throws {
        let files = try makeSourceFiles()

        let image = ClipboardItem(kind: .image, text: nil, dataPath: files.png.path, hash: "i")
        XCTAssertEqual(image.previewImagePath, files.png.path)

        let file = ClipboardItem(kind: .file, text: files.png.absoluteString, hash: "f")
        XCTAssertEqual(file.previewImagePath, files.png.path)

        let pdf = ClipboardItem(kind: .file, text: files.pdf.absoluteString, hash: "p")
        XCTAssertNil(pdf.previewImagePath)

        let multi = ClipboardItem(
            kind: .file,
            text: "\(files.png.absoluteString)\n\(files.pdf.absoluteString)",
            hash: "m"
        )
        XCTAssertNil(multi.previewImagePath)

        let text = ClipboardItem(kind: .text, text: files.png.absoluteString, hash: "t")
        XCTAssertNil(text.previewImagePath)
    }

    func testFinderImageCopyKeepsFileKind() throws {
        let files = try makeSourceFiles()
        let payload = ClipboardPayloadReader.process(
            snapshot(fileURLs: [files.png], pngData: Self.pngBytes),
            dataStore: dataStore
        )
        XCTAssertEqual(payload?.kind, .file)
        XCTAssertEqual(payload?.text, files.png.absoluteString)
    }

    func testBitmapOnlyCopyIsClassifiedAsImage() {
        let payload = ClipboardPayloadReader.process(
            snapshot(pngData: Self.pngBytes),
            dataStore: dataStore
        )
        XCTAssertEqual(payload?.kind, .image)
        XCTAssertNotNil(payload?.dataPath)
    }
}

@MainActor
final class PasteEnginePayloadTests: XCTestCase {
    private func makeEngine(_ pasteboard: NSPasteboard) -> PasteEngine {
        PasteEngine(pasteboard: pasteboard, accessibilityTrusted: { false })
    }

    func testPasteOverrideOnlyAppliesToShortLinks() {
        let text = ClipboardItem(kind: .text, text: "hello", hash: "override-text")
        XCTAssertNil(text.pasteTextOverride(preferShort: false))

        let file = ClipboardItem(kind: .file, text: "file:///tmp/a.png", hash: "override-file")
        XCTAssertNil(file.pasteTextOverride(preferShort: false))

        let image = ClipboardItem(kind: .image, text: nil, title: "Image 1×1", hash: "override-image")
        XCTAssertNil(image.pasteTextOverride(preferShort: false))

        let url = ClipboardItem(
            kind: .url,
            text: "https://example.com/long",
            shortUrl: "https://bit.ly/x",
            hash: "override-url"
        )
        XCTAssertNil(url.pasteTextOverride(preferShort: false))
        XCTAssertEqual(url.pasteTextOverride(preferShort: true), "https://bit.ly/x")
    }

    func testFileItemPastesAFileURL() async {
        let pasteboard = NSPasteboard.withUniqueName()
        let item = ClipboardItem(
            kind: .file,
            text: "file:///tmp/photo.png",
            hash: "file-paste"
        )

        let outcome = await makeEngine(pasteboard).paste(item)

        XCTAssertEqual(outcome, .copiedToClipboard)
        XCTAssertTrue(
            pasteboard.types?.contains(.fileURL) ?? false,
            "expected public.file-url, got \(pasteboard.types ?? [])"
        )
    }

    func testImageItemPastesPNGData() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipshotPasteTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageURL = directory.appendingPathComponent("image.png")
        try ClipboardPayloadReaderTests.pngBytes.write(to: imageURL)

        let pasteboard = NSPasteboard.withUniqueName()
        let item = ClipboardItem(
            kind: .image,
            text: nil,
            title: "Image 1×1",
            dataPath: imageURL.path,
            hash: "image-paste"
        )

        let outcome = await makeEngine(pasteboard).paste(item)

        XCTAssertEqual(outcome, .copiedToClipboard)
        XCTAssertTrue(
            pasteboard.types?.contains(.png) ?? false,
            "expected public.png, got \(pasteboard.types ?? [])"
        )
        XCTAssertEqual(
            pasteboard.data(forType: .png),
            ClipboardPayloadReaderTests.pngBytes
        )
    }
}

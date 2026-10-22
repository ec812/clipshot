import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import Clipshot

@MainActor
final class DragTempStoreTests: XCTestCase {
    private var root: URL!
    private var dataDirectory: URL!
    private var dragDirectory: URL!
    private var itemDataStore: ItemDataStore!
    private var dragTemp: DragTempStore!
    private var imageURL: URL!
    private var imageItem: ClipboardItem!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipshotDragTests-\(UUID().uuidString)", isDirectory: true)
        dataDirectory = root.appendingPathComponent("Data", isDirectory: true)
        dragDirectory = root.appendingPathComponent("ClipshotDrag", isDirectory: true)
        itemDataStore = ItemDataStore(directory: dataDirectory)
        dragTemp = DragTempStore(directory: dragDirectory)

        imageURL = dataDirectory.appendingPathComponent("source.png")
        try ClipboardPayloadReaderTests.pngBytes.write(to: imageURL)
        imageItem = ClipboardItem(
            kind: .image,
            text: nil,
            title: "Image 1×1",
            dataPath: imageURL.path,
            hash: "drag-hash"
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        dragTemp = nil
        itemDataStore = nil
        try super.tearDownWithError()
    }

    func testDragProviderAdvertisesFileAndImageRepresentations() throws {
        let provider = try XCTUnwrap(dragTemp.itemProvider(for: imageItem))

        XCTAssertTrue(
            provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
            "expected public.file-url, got \(provider.registeredTypeIdentifiers)"
        )
        XCTAssertTrue(
            provider.hasItemConformingToTypeIdentifier(UTType.png.identifier),
            "expected public.png, got \(provider.registeredTypeIdentifiers)"
        )
        XCTAssertTrue(
            provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
            "expected public.image, got \(provider.registeredTypeIdentifiers)"
        )
        XCTAssertTrue(provider.suggestedName?.hasSuffix(".png") ?? false)
    }

    func testDragCopyExistsOutsideDataDirectoryWithItemBytes() throws {
        let copy = try XCTUnwrap(dragTemp.prepareDragFile(for: imageItem))

        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
        XCTAssertEqual(try Data(contentsOf: copy), ClipboardPayloadReaderTests.pngBytes)
        XCTAssertTrue(copy.lastPathComponent.hasPrefix("clipshot-drag-hash-"))
        XCTAssertTrue(copy.lastPathComponent.hasSuffix(".png"))

        let dataPrefix = itemDataStore.directory.standardizedFileURL.path + "/"
        XCTAssertFalse(
            copy.standardizedFileURL.path.hasPrefix(dataPrefix),
            "drag copies must live outside ItemDataStore.directory or pruneOrphans would delete them"
        )
    }

    func testDragCopySurvivesOrphanPruning() throws {
        let copy = try XCTUnwrap(dragTemp.prepareDragFile(for: imageItem))

        // pruneOrphans compares the paths returned by contentsOfDirectory, so
        // use that same form for the known path (macOS canonicalizes /var to
        // /private/var there).
        let knownPath = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: itemDataStore.directory,
                includingPropertiesForKeys: nil
            ).first
        ).path
        itemDataStore.pruneOrphans(knownPaths: [knownPath])

        XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: copy.path),
            "pruneOrphans must not reach the drag temp directory"
        )
    }

    func testSweepRemovesOnlyStaleCopies() throws {
        let fresh = try XCTUnwrap(dragTemp.prepareDragFile(for: imageItem))
        let stale = try XCTUnwrap(
            dragTemp.prepareDragFile(
                for: imageItem,
                now: Date(timeIntervalSinceNow: -2 * DragTempStore.maxAge)
            )
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -2 * DragTempStore.maxAge)],
            ofItemAtPath: stale.path
        )

        let removed = dragTemp.sweepStale()

        XCTAssertEqual(removed.map { ($0 as NSString).lastPathComponent }, [stale.lastPathComponent])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
    }

    func testNonImageItemsHaveNoDragPayload() {
        let text = ClipboardItem(kind: .text, text: "hello", hash: "text-hash")
        XCTAssertNil(dragTemp.itemProvider(for: text))
        XCTAssertNil(dragTemp.prepareDragFile(for: text))

        let file = ClipboardItem(
            kind: .file,
            text: "file:///tmp/photo.png",
            hash: "file-hash"
        )
        XCTAssertNil(dragTemp.itemProvider(for: file))
        XCTAssertNil(dragTemp.prepareDragFile(for: file))
    }
}

@MainActor
final class PasteAsFileTests: XCTestCase {
    private var directory: URL!
    private var imageURL: URL!
    private var item: ClipboardItem!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipshotPasteAsFileTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        imageURL = directory.appendingPathComponent("item.png")
        try ClipboardPayloadReaderTests.pngBytes.write(to: imageURL)
        item = ClipboardItem(
            kind: .image,
            text: nil,
            title: "Image 1×1",
            dataPath: imageURL.path,
            hash: "paste-as-file"
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        item = nil
        imageURL = nil
        directory = nil
        try super.tearDownWithError()
    }

    private func makeEngine(_ pasteboard: NSPasteboard) -> PasteEngine {
        PasteEngine(pasteboard: pasteboard, accessibilityTrusted: { false })
    }

    func testPasteAsFileWritesFileURLPointingAtItemBytes() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        let engine = makeEngine(pasteboard)

        let outcome = await engine.pasteAsFile(item)

        XCTAssertEqual(outcome, .copiedToClipboard)
        XCTAssertTrue(
            pasteboard.types?.contains(.fileURL) ?? false,
            "expected public.file-url, got \(pasteboard.types ?? [])"
        )
        XCTAssertFalse(
            pasteboard.types?.contains(.png) ?? false,
            "Paste as File must not put PNG data on the pasteboard"
        )

        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        let pastedURL = try XCTUnwrap(urls?.first)
        XCTAssertEqual(pastedURL.standardizedFileURL, imageURL.standardizedFileURL)
        XCTAssertEqual(try Data(contentsOf: pastedURL), ClipboardPayloadReaderTests.pngBytes)
    }

    func testPasteAsFileRejectsItemsWithoutOwnedFile() async {
        let pasteboard = NSPasteboard.withUniqueName()
        let text = ClipboardItem(kind: .text, text: "hello", hash: "text-item")

        let outcome = await makeEngine(pasteboard).pasteAsFile(text)

        XCTAssertEqual(outcome, .failed("This item has no file to paste."))
    }

    func testPasteAsFileFailsWhenStoredFileIsGone() async throws {
        try FileManager.default.removeItem(at: imageURL)
        let pasteboard = NSPasteboard.withUniqueName()

        let outcome = await makeEngine(pasteboard).pasteAsFile(item)

        XCTAssertEqual(outcome, .failed("The image file is no longer available."))
    }
}

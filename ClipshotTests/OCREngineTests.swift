import AppKit
import XCTest
@testable import Clipshot

actor SpyOCREngine: OCREngine {
    private(set) var callCount = 0
    let result: String

    init(result: String = "hello world zebra") {
        self.result = result
    }

    func recognizeText(inImageAt url: URL) async throws -> String {
        callCount += 1
        return result
    }
}

private enum OCREngineTestError: Error {
    case fixtureEncodingFailed
}

@MainActor
final class OCREngineTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipshotOCRTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        try super.tearDownWithError()
    }

    private static let pngBytes = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2nWQAAAAASUVORK5CYII="
    )!

    private func writeTextImage(_ text: String) throws -> URL {
        let size = NSSize(width: 1000, height: 260)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 96, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        (text as NSString).draw(at: NSPoint(x: 40, y: 70), withAttributes: attributes)
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else {
            throw OCREngineTestError.fixtureEncodingFailed
        }

        let url = directory.appendingPathComponent("text-fixture.png")
        try png.write(to: url)
        return url
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testVisionExtractsDrawnText() async throws {
        let url = try writeTextImage("CLIPSHOT")
        let text = try await VisionOCREngine().recognizeText(inImageAt: url)
        XCTAssertTrue(text.uppercased().contains("CLIPSHOT"), "extracted text was: \(text)")
    }

    func testUnreadableImageThrows() async {
        do {
            _ = try await VisionOCREngine().recognizeText(
                inImageAt: directory.appendingPathComponent("missing.png")
            )
            XCTFail("Expected an unreadable-image error")
        } catch {
            XCTAssertEqual(error as? OCREngineError, .unreadableImage)
        }
    }

    func testClipboardMonitorHasNoOCRDependency() throws {
        let store = try HistoryStore.inMemory()
        _ = ClipboardMonitor(
            store: store,
            privacyFilter: PrivacyFilter(),
            rulesEngine: ShortenRulesEngine(store: store),
            dataStore: ItemDataStore(directory: directory)
        )
    }

    func testImageCapturePathDoesNotInvokeOCR() async throws {
        let spy = SpyOCREngine()
        let store = try HistoryStore.inMemory()
        let dataStore = ItemDataStore(directory: directory)
        let appState = AppState(
            store: store,
            startMonitoring: false,
            dataStore: dataStore,
            ocrEngine: spy
        )

        let payload = try XCTUnwrap(
            ClipboardPayloadReader.process(
                PasteboardCaptureSnapshot(
                    fileURLs: [],
                    pngData: Self.pngBytes,
                    tiffData: nil,
                    rtfData: nil,
                    colorData: nil,
                    string: nil
                ),
                dataStore: dataStore
            )
        )
        _ = try store.insert(
            kind: payload.kind,
            text: payload.text,
            title: payload.title,
            dataPath: payload.dataPath,
            hash: payload.hash
        )

        appState.reload()
        await waitUntil { !appState.items.isEmpty }

        let callCount = await spy.callCount
        XCTAssertEqual(callCount, 0)
    }

    func testExtractTextPersistsSearchableText() async throws {
        let spy = SpyOCREngine(result: "visible words zebra")
        let store = try HistoryStore.inMemory()
        let dataStore = ItemDataStore(directory: directory)
        let appState = AppState(
            store: store,
            startMonitoring: false,
            dataStore: dataStore,
            ocrEngine: spy
        )

        let imageURL = directory.appendingPathComponent("screenshot.png")
        try Self.pngBytes.write(to: imageURL)
        let item = try store.insert(
            kind: .image,
            text: nil,
            title: "Image",
            dataPath: imageURL.path,
            hash: "ocr-extract"
        ).item

        appState.extractTextFromImage(item)

        await waitUntil {
            (try? store.search("zebra"))?.isEmpty == false
        }
        XCTAssertEqual(try store.search("zebra").first?.id, item.id)
        XCTAssertEqual(try store.item(id: item.id!)?.ocrText, "visible words zebra")

        let callCount = await spy.callCount
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(appState.toast, "Text extracted")
    }
}

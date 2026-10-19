import XCTest
@testable import Clipshot

final class OGImageParserTests: XCTestCase {
    private let baseURL = URL(string: "https://example.com/articles/page")!

    func testOpenGraphImage() {
        let html = """
        <html><head>
        <meta property="og:title" content="Title">
        <meta property="og:image" content="https://cdn.example.com/og.png">
        </head></html>
        """
        XCTAssertEqual(
            OGImageParser.imageURL(fromHTML: html, baseURL: baseURL)?.absoluteString,
            "https://cdn.example.com/og.png"
        )
    }

    func testTwitterImageFallback() {
        let html = """
        <meta name="twitter:card" content="summary_large_image">
        <meta name="twitter:image" content='https://cdn.example.com/twitter.jpg'>
        """
        XCTAssertEqual(
            OGImageParser.imageURL(fromHTML: html, baseURL: baseURL)?.absoluteString,
            "https://cdn.example.com/twitter.jpg"
        )
    }

    func testOpenGraphWinsOverTwitter() {
        let html = """
        <meta name="twitter:image" content="https://cdn.example.com/twitter.jpg">
        <meta property="og:image" content="https://cdn.example.com/og.png">
        """
        XCTAssertEqual(
            OGImageParser.imageURL(fromHTML: html, baseURL: baseURL)?.absoluteString,
            "https://cdn.example.com/og.png"
        )
    }

    func testAttributeOrderAndCaseInsensitivity() {
        let html = """
        <META CONTENT="https://cdn.example.com/upper.png" PROPERTY="OG:IMAGE">
        <meta content="https://cdn.example.com/second.png" property="og:image">
        """
        XCTAssertEqual(
            OGImageParser.imageURL(fromHTML: html, baseURL: baseURL)?.absoluteString,
            "https://cdn.example.com/upper.png"
        )
    }

    func testRelativeURLResolution() {
        let absolutePath = "<meta property='og:image' content='/assets/og.png'>"
        XCTAssertEqual(
            OGImageParser.imageURL(fromHTML: absolutePath, baseURL: baseURL)?.absoluteString,
            "https://example.com/assets/og.png"
        )

        let relativePath = "<meta property='og:image' content='images/og.png'>"
        XCTAssertEqual(
            OGImageParser.imageURL(fromHTML: relativePath, baseURL: baseURL)?.absoluteString,
            "https://example.com/articles/images/og.png"
        )

        let protocolRelative = "<meta property='og:image' content='//cdn.example.com/og.png'>"
        XCTAssertEqual(
            OGImageParser.imageURL(fromHTML: protocolRelative, baseURL: baseURL)?.absoluteString,
            "https://cdn.example.com/og.png"
        )
    }

    func testHTMLEntitiesAreDecoded() {
        let html = "<meta property=\"og:image\" content=\"https://cdn.example.com/og.png?a=1&amp;b=2\">"
        let url = OGImageParser.imageURL(fromHTML: html, baseURL: baseURL)
        XCTAssertEqual(url?.query, "a=1&b=2")
    }

    func testMalformedHTMLIsTolerated() {
        let broken = "<html><head><meta property=\"og:image\" content=\"https://cdn.example.com/broken.png\"<<body>"
        XCTAssertEqual(
            OGImageParser.imageURL(fromHTML: broken, baseURL: baseURL)?.absoluteString,
            "https://cdn.example.com/broken.png"
        )

        XCTAssertNil(OGImageParser.imageURL(fromHTML: "<html><head><meta", baseURL: baseURL))
        XCTAssertNil(OGImageParser.imageURL(fromHTML: "", baseURL: baseURL))
    }

    func testMissingOrEmptyContent() {
        XCTAssertNil(OGImageParser.imageURL(
            fromHTML: "<meta property='og:image' content=''>",
            baseURL: baseURL
        ))
        XCTAssertNil(OGImageParser.imageURL(
            fromHTML: "<meta property='og:image' content='   '>",
            baseURL: baseURL
        ))
        XCTAssertNil(OGImageParser.imageURL(
            fromHTML: "<meta property='og:image'>",
            baseURL: baseURL
        ))
    }

    func testNonHTTPImageIsRejected() {
        XCTAssertNil(OGImageParser.imageURL(
            fromHTML: "<meta property='og:image' content='data:image/png;base64,AAAA'>",
            baseURL: baseURL
        ))
    }
}

final class OGImageCacheTests: XCTestCase {
    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    private var directory: URL!
    private var clock: Clock!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = fileManager.temporaryDirectory
            .appendingPathComponent("ClipshotOGCacheTests-\(UUID().uuidString)", isDirectory: true)
        clock = Clock()
    }

    override func tearDown() {
        try? fileManager.removeItem(at: directory)
        directory = nil
        clock = nil
        super.tearDown()
    }

    private func makeCache(
        ttl: TimeInterval = 7 * 24 * 60 * 60,
        negativeTTL: TimeInterval = 24 * 60 * 60,
        sizeLimit: Int = 200 * 1024 * 1024
    ) -> OGImageCache {
        let clock = self.clock!
        return OGImageCache(
            directory: directory,
            ttl: ttl,
            negativeTTL: negativeTTL,
            sizeLimit: sizeLimit,
            now: { clock.now }
        )
    }

    private func url(_ path: String) -> URL {
        URL(string: "https://example.com/\(path)")!
    }

    func testStoreAndLookupImage() {
        let cache = makeCache()
        let page = url("article")
        let data = Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02])

        cache.storeImage(data, for: page)

        XCTAssertEqual(cache.lookup(url: page), .image(data))
        XCTAssertTrue(fileManager.fileExists(atPath: cache.imageFileURL(for: page).path))
        XCTAssertFalse(fileManager.fileExists(atPath: cache.negativeFileURL(for: page).path))
    }

    func testPositiveTTLExpiry() {
        let cache = makeCache(ttl: 3600)
        let page = url("ttl")
        cache.storeImage(Data(repeating: 7, count: 32), for: page)

        clock.advance(3601)
        XCTAssertEqual(cache.lookup(url: page), .miss)
        XCTAssertFalse(fileManager.fileExists(atPath: cache.imageFileURL(for: page).path))
    }

    func testNegativeCacheAndExpiry() {
        let cache = makeCache(negativeTTL: 3600)
        let page = url("dead-page")

        cache.storeFailure(for: page)
        XCTAssertEqual(cache.lookup(url: page), .negative)
        XCTAssertTrue(fileManager.fileExists(atPath: cache.negativeFileURL(for: page).path))

        clock.advance(3601)
        XCTAssertEqual(cache.lookup(url: page), .miss)
    }

    func testImageReplacesNegativeAndViceVersa() {
        let cache = makeCache()
        let page = url("flip")

        cache.storeFailure(for: page)
        XCTAssertEqual(cache.lookup(url: page), .negative)

        cache.storeImage(Data(repeating: 1, count: 8), for: page)
        XCTAssertEqual(cache.lookup(url: page), .image(Data(repeating: 1, count: 8)))

        cache.storeFailure(for: page)
        XCTAssertEqual(cache.lookup(url: page), .negative)
    }

    func testLRUEvictsOldestEntry() {
        let cache = makeCache(sizeLimit: 100)
        let first = url("first")
        let second = url("second")

        cache.storeImage(Data(repeating: 1, count: 60), for: first)
        clock.advance(10)
        cache.storeImage(Data(repeating: 2, count: 60), for: second)

        XCTAssertEqual(cache.lookup(url: first), .miss)
        XCTAssertEqual(cache.lookup(url: second), .image(Data(repeating: 2, count: 60)))
    }

    func testClearRemovesEverything() {
        let cache = makeCache()
        let page = url("clear")
        cache.storeImage(Data(repeating: 3, count: 16), for: page)
        XCTAssertGreaterThan(cache.currentSize(), 0)

        cache.clear()
        XCTAssertEqual(cache.lookup(url: page), .miss)
        XCTAssertEqual(cache.currentSize(), 0)
    }
}

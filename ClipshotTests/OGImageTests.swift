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

    // MARK: - Full metadata

    func testOpenGraphMetadata() {
        let html = """
        <html><head>
        <meta property="og:title" content="The Title">
        <meta property="og:description" content="The description.">
        <meta property="og:image" content="https://cdn.example.com/og.png">
        <meta property="og:site_name" content="Ignored Site">
        </head></html>
        """
        let metadata = OGImageParser.metadata(fromHTML: html, baseURL: baseURL)
        XCTAssertEqual(metadata.title, "The Title")
        XCTAssertEqual(metadata.description, "The description.")
        XCTAssertEqual(metadata.imageURL?.absoluteString, "https://cdn.example.com/og.png")
    }

    func testTwitterMetadataFallbacks() {
        let html = """
        <meta name="twitter:title" content="Twitter Title">
        <meta name="twitter:description" content="Twitter description">
        <meta name="twitter:image" content="https://cdn.example.com/twitter.jpg">
        """
        let metadata = OGImageParser.metadata(fromHTML: html, baseURL: baseURL)
        XCTAssertEqual(metadata.title, "Twitter Title")
        XCTAssertEqual(metadata.description, "Twitter description")
        XCTAssertEqual(metadata.imageURL?.absoluteString, "https://cdn.example.com/twitter.jpg")
    }

    func testOpenGraphMetadataWinsOverTwitter() {
        let html = """
        <meta property="og:title" content="OG Title">
        <meta name="twitter:title" content="Twitter Title">
        <meta property="og:description" content="OG Description">
        <meta name="twitter:description" content="Twitter Description">
        <meta property="og:image" content="https://cdn.example.com/og.png">
        <meta name="twitter:image" content="https://cdn.example.com/twitter.jpg">
        """
        let metadata = OGImageParser.metadata(fromHTML: html, baseURL: baseURL)
        XCTAssertEqual(metadata.title, "OG Title")
        XCTAssertEqual(metadata.description, "OG Description")
        XCTAssertEqual(metadata.imageURL?.absoluteString, "https://cdn.example.com/og.png")
    }

    func testTitleTagAndMetaDescriptionFallbacks() {
        let html = """
        <html><head>
        <title>
            Plain &amp; Head Title
        </title>
        <meta name="description" content="Plain meta description">
        </head></html>
        """
        let metadata = OGImageParser.metadata(fromHTML: html, baseURL: baseURL)
        XCTAssertEqual(metadata.title, "Plain & Head Title")
        XCTAssertEqual(metadata.description, "Plain meta description")
        XCTAssertNil(metadata.imageURL)
    }

    func testPartialMetadata() {
        let metadata = OGImageParser.metadata(
            fromHTML: "<meta property='og:title' content='Only a title'>",
            baseURL: baseURL
        )
        XCTAssertEqual(metadata.title, "Only a title")
        XCTAssertNil(metadata.description)
        XCTAssertNil(metadata.imageURL)
    }

    func testMissingMetadata() {
        let metadata = OGImageParser.metadata(
            fromHTML: "<html><body>No metadata here</body></html>",
            baseURL: baseURL
        )
        XCTAssertTrue(metadata.isEmpty)
    }

    func testMetadataDescriptionWhitespaceAndEntities() {
        let html = """
        <meta property="og:description" content="Line one
        &amp; line two &quot;quoted&quot;">
        """
        let metadata = OGImageParser.metadata(fromHTML: html, baseURL: baseURL)
        XCTAssertEqual(metadata.description, "Line one & line two \"quoted\"")
    }

    func testMetadataResolvesRelativeImageAgainstBase() {
        let html = "<meta property='og:image' content='/assets/og.png'>"
        let metadata = OGImageParser.metadata(fromHTML: html, baseURL: baseURL)
        XCTAssertEqual(metadata.imageURL?.absoluteString, "https://example.com/assets/og.png")
    }

    func testOpenGraphImageURLVariants() {
        let secure = "<meta property='og:image:secure_url' content='https://cdn.example.com/secure.png'>"
        XCTAssertEqual(
            OGImageParser.metadata(fromHTML: secure, baseURL: baseURL).imageURL?.absoluteString,
            "https://cdn.example.com/secure.png"
        )

        let urlVariant = "<meta property='og:image:url' content='https://cdn.example.com/url.png'>"
        XCTAssertEqual(
            OGImageParser.metadata(fromHTML: urlVariant, baseURL: baseURL).imageURL?.absoluteString,
            "https://cdn.example.com/url.png"
        )
    }

    func testInvalidOpenGraphImageFallsBackToTwitter() {
        let html = """
        <meta property="og:image" content="data:image/png;base64,AAAA">
        <meta name="twitter:image" content="https://cdn.example.com/twitter.jpg">
        """
        let metadata = OGImageParser.metadata(fromHTML: html, baseURL: baseURL)
        XCTAssertEqual(metadata.imageURL?.absoluteString, "https://cdn.example.com/twitter.jpg")
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

    private func imageData(from result: OGImageCacheResult) -> Data? {
        guard case .preview(let preview) = result else { return nil }
        return preview.imageData
    }

    private func cachedMetadata(from result: OGImageCacheResult) -> OGMetadata? {
        guard case .preview(let preview) = result else { return nil }
        return preview.metadata
    }

    func testStoreAndLookupImage() {
        let cache = makeCache()
        let page = url("article")
        let data = Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02])

        cache.storeImage(data, for: page)

        XCTAssertEqual(imageData(from: cache.lookup(url: page)), data)
        XCTAssertTrue(fileManager.fileExists(atPath: cache.imageFileURL(for: page).path))
        XCTAssertTrue(fileManager.fileExists(atPath: cache.metadataFileURL(for: page).path))
        XCTAssertFalse(fileManager.fileExists(atPath: cache.negativeFileURL(for: page).path))
    }

    func testStoreAndLookupFullMetadataRecord() {
        let cache = makeCache()
        let page = url("metadata")
        let metadata = OGMetadata(
            title: "A title",
            description: "A description",
            imageURL: URL(string: "https://cdn.example.com/og.png")
        )
        let image = Data(repeating: 0x42, count: 64)

        cache.storePreview(OGPagePreview(imageData: image, metadata: metadata), for: page)

        let result = cache.lookup(url: page)
        XCTAssertEqual(imageData(from: result), image)
        XCTAssertEqual(cachedMetadata(from: result), metadata)
    }

    func testMetadataOnlyRecordRoundTrip() {
        let cache = makeCache()
        let page = url("metadata-only")
        let metadata = OGMetadata(title: "Title only", description: nil, imageURL: nil)

        cache.storePreview(OGPagePreview(imageData: nil, metadata: metadata), for: page)

        let result = cache.lookup(url: page)
        XCTAssertEqual(cachedMetadata(from: result), metadata)
        XCTAssertNil(imageData(from: result))
    }

    func testPositiveTTLExpiry() {
        let cache = makeCache(ttl: 3600)
        let page = url("ttl")
        cache.storeImage(Data(repeating: 7, count: 32), for: page)

        clock.advance(3601)
        XCTAssertEqual(cache.lookup(url: page), .miss)
        XCTAssertFalse(fileManager.fileExists(atPath: cache.imageFileURL(for: page).path))
        XCTAssertFalse(fileManager.fileExists(atPath: cache.metadataFileURL(for: page).path))
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

        let data = Data(repeating: 1, count: 8)
        cache.storeImage(data, for: page)
        XCTAssertEqual(imageData(from: cache.lookup(url: page)), data)

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
        XCTAssertEqual(imageData(from: cache.lookup(url: second)), Data(repeating: 2, count: 60))
    }

    func testClearRemovesEverything() {
        let cache = makeCache()
        let page = url("clear")
        cache.storePreview(
            OGPagePreview(
                imageData: Data(repeating: 3, count: 16),
                metadata: OGMetadata(title: "Clear", description: "Me", imageURL: nil)
            ),
            for: page
        )
        XCTAssertGreaterThan(cache.currentSize(), 0)

        cache.clear()
        XCTAssertEqual(cache.lookup(url: page), .miss)
        XCTAssertEqual(cache.currentSize(), 0)
    }
}

import XCTest
@testable import Clipshot

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    static var lastRequest: URLRequest?
    static var lastRequestBody: Data?
    static var requestCount = 0

    static func reset() {
        handler = nil
        lastRequest = nil
        lastRequestBody = nil
        requestCount = 0
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastRequestBody = Self.bodyData(for: request)
        Self.requestCount += 1

        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://api-ssl.bitly.com/v4")!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !data.isEmpty {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func bodyData(for request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while true {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

final class BitlyBackendTests: XCTestCase {
    private var store: HistoryStore!
    private var session: URLSession!
    private var backend: BitlyBackend!

    private let baseURL = URL(string: "https://api-ssl.bitly.com/v4")!

    override func setUpWithError() throws {
        try super.setUpWithError()
        store = try HistoryStore.inMemory()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
        backend = BitlyBackend(
            accessToken: "secret-token",
            session: session,
            baseURL: baseURL,
            cache: store,
            defaultDomain: "bit.ly",
            defaultGroupGUID: "GRP123"
        )
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        session.invalidateAndCancel()
        session = nil
        backend = nil
        store = nil
        super.tearDown()
    }

    private func respond(status: Int, json: String = "{}") {
        let data = Data(json.utf8)
        MockURLProtocol.handler = { _ in (status, data) }
    }

    private func capturedBody() throws -> [String: Any] {
        let data = try XCTUnwrap(MockURLProtocol.lastRequestBody)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func sampleLinkJSON(
        id: String = "bit.ly/3abc",
        link: String = "https://bit.ly/3abc",
        longURL: String = "https://example.com/article"
    ) -> String {
        """
        {
          "id": "\(id)",
          "link": "\(link)",
          "long_url": "\(longURL)",
          "title": "Example article",
          "created_at": "2026-10-19T12:00:00+0000",
          "archived": false,
          "custom_bitlinks": [],
          "tags": ["work"],
          "references": { "group": "https://api-ssl.bitly.com/v4/groups/GRP123" }
        }
        """
    }

    // MARK: - Shorten (auto slug)

    func testShortenSendsBearerTokenAndParsesResponse() async throws {
        respond(status: 200, json: sampleLinkJSON())

        let url = URL(string: "https://example.com/article")!
        let link = try await backend.createLink(
            destinationURL: url,
            domain: nil,
            slug: nil,
            tags: []
        )

        XCTAssertEqual(link.id, "bit.ly/3abc")
        XCTAssertEqual(link.shortUrl, "https://bit.ly/3abc")
        XCTAssertEqual(link.destinationUrl, "https://example.com/article")
        XCTAssertEqual(link.domain, "bit.ly")
        XCTAssertEqual(link.slug, "3abc")
        XCTAssertEqual(link.backendId, "bitly")
        XCTAssertEqual(link.tags, ["work"])
        XCTAssertNil(link.clickCount)

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.host, "api-ssl.bitly.com")
        XCTAssertEqual(request.url?.path, "/v4/shorten")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try capturedBody()
        XCTAssertEqual(body["long_url"] as? String, url.absoluteString)
        XCTAssertEqual(body["domain"] as? String, "bit.ly")
        XCTAssertEqual(body["group_guid"] as? String, "GRP123")
        XCTAssertNil(body["tags"])

        let cached = try store.cachedShortLinks(limit: 10)
        XCTAssertEqual(cached.count, 1)
        XCTAssertEqual(cached.first?.id, "bit.ly/3abc")
    }

    func testShortenUsesDefaultDomainWhenNoneGiven() async throws {
        respond(status: 200, json: sampleLinkJSON())

        _ = try await backend.createLink(
            destinationURL: URL(string: "https://example.com")!,
            domain: nil,
            slug: nil,
            tags: []
        )

        let body = try capturedBody()
        XCTAssertEqual(body["domain"] as? String, "bit.ly")
    }

    // MARK: - Custom slug / branded domain

    func testCustomSlugUsesBitlinksEndpoint() async throws {
        respond(status: 201, json: sampleLinkJSON(id: "brand.example/promo", link: "https://brand.example/promo"))

        let link = try await backend.createLink(
            destinationURL: URL(string: "https://example.com/article")!,
            domain: "brand.example",
            slug: "promo",
            tags: ["work"]
        )

        XCTAssertEqual(link.id, "brand.example/promo")
        XCTAssertEqual(link.domain, "brand.example")
        XCTAssertEqual(link.slug, "promo")

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/v4/bitlinks")

        let body = try capturedBody()
        XCTAssertEqual(body["long_url"] as? String, "https://example.com/article")
        XCTAssertEqual(body["domain"] as? String, "brand.example")
        XCTAssertEqual(body["keyword"] as? String, "promo")
        XCTAssertEqual(body["group_guid"] as? String, "GRP123")
        XCTAssertEqual(body["tags"] as? [String], ["work"])
    }

    // MARK: - Error mapping

    func testUnauthorizedInvalidAccessToken() async {
        respond(
            status: 401,
            json: #"{"message":"INVALID_ARG_ACCESS_TOKEN","description":"The access token is invalid.","resource":"auth"}"#
        )
        do {
            _ = try await backend.createLink(
                destinationURL: URL(string: "https://example.com")!,
                domain: nil,
                slug: nil,
                tags: []
            )
            XCTFail("Expected unauthorized error")
        } catch let error as ShortenerError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNotFound() async {
        respond(status: 404, json: #"{"message":"NOT_FOUND","description":"Bitlink not found","resource":"bitlinks"}"#)
        do {
            _ = try await backend.deleteLink(id: "bit.ly/missing")
            XCTFail("Expected notFound error")
        } catch let error as ShortenerError {
            XCTAssertEqual(error, .notFound)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testBrandedLinkMonthlyLimitExceeded() async {
        respond(
            status: 400,
            json: #"{"message":"BRANDED_LINK_MONTHLY_LIMIT_EXCEEDED","description":"You have exceeded your branded link limit.","resource":"bitlinks"}"#
        )
        do {
            _ = try await backend.createLink(
                destinationURL: URL(string: "https://example.com")!,
                domain: "brand.example",
                slug: nil,
                tags: []
            )
            XCTFail("Expected linkLimitReached error")
        } catch let error as ShortenerError {
            XCTAssertEqual(error, .linkLimitReached)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDNSConfigurationError() async {
        respond(
            status: 400,
            json: #"{"message":"DNS_CONFIGURATION_ERROR","description":"The custom domain is not configured.","resource":"bitlinks"}"#
        )
        do {
            _ = try await backend.createLink(
                destinationURL: URL(string: "https://example.com")!,
                domain: "brand.example",
                slug: "promo",
                tags: []
            )
            XCTFail("Expected validation error")
        } catch let error as ShortenerError {
            guard case .validation(let message) = error else {
                XCTFail("Expected validation error, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("DNS"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testValidationErrorCarriesServerDescription() async {
        respond(
            status: 422,
            json: #"{"message":"INVALID_ARG_LONG_URL","description":"long_url must be a valid URL","resource":"bitlinks"}"#
        )
        do {
            _ = try await backend.createLink(
                destinationURL: URL(string: "https://example.com")!,
                domain: nil,
                slug: nil,
                tags: []
            )
            XCTFail("Expected validation error")
        } catch let error as ShortenerError {
            XCTAssertEqual(error, .validation("long_url must be a valid URL"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testServerError() async {
        respond(status: 503, json: #"{"message":"TEMPORARILY_UNAVAILABLE","description":"Try later"}"#)
        do {
            _ = try await backend.createLink(
                destinationURL: URL(string: "https://example.com")!,
                domain: nil,
                slug: nil,
                tags: []
            )
            XCTFail("Expected server error")
        } catch let error as ShortenerError {
            XCTAssertEqual(error, .server(status: 503, message: "Try later"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMissingAccessToken() async {
        let unconfigured = BitlyBackend(accessToken: "", session: session, cache: store)
        do {
            _ = try await unconfigured.createLink(
                destinationURL: URL(string: "https://example.com")!,
                domain: nil,
                slug: nil,
                tags: []
            )
            XCTFail("Expected missingAPIKey error")
        } catch let error as ShortenerError {
            XCTAssertEqual(error, .missingAPIKey)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Update / delete

    func testUpdateUsesPatchAndSupportedFields() async throws {
        respond(status: 200, json: sampleLinkJSON())

        _ = try await backend.updateLink(
            id: "bit.ly/3abc",
            destinationURL: URL(string: "https://example.com/updated")!,
            slug: "ignored",
            tags: ["news"]
        )

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(request.url?.path, "/v4/bitlinks/bit.ly/3abc")

        let body = try capturedBody()
        XCTAssertEqual(body["long_url"] as? String, "https://example.com/updated")
        XCTAssertEqual(body["tags"] as? [String], ["news"])
        XCTAssertNil(body["keyword"])
        XCTAssertNil(body["slug"])
    }

    func testDeleteUsesDeleteWithBitlinkPath() async throws {
        respond(status: 200, json: #"{"links_deleted":[{"id":"bit.ly/3abc"}]}"#)

        try await backend.deleteLink(id: "bit.ly/3abc")

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, "/v4/bitlinks/bit.ly/3abc")
    }

    // MARK: - Click analytics

    func testClickStatsParsesTimelineAndCachesTotal() async throws {
        let cachedLink = ShortLink(
            id: "bit.ly/3abc",
            shortUrl: "https://bit.ly/3abc",
            destinationUrl: "https://example.com/article",
            slug: "3abc",
            domain: "bit.ly",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            backendId: "bitly"
        )
        try store.saveShortLink(cachedLink)

        respond(
            status: 200,
            json: """
            {
              "link_clicks": [
                { "date": "2026-10-18T00:00:00+0000", "clicks": 3 },
                { "date": "2026-10-19T00:00:00+0000", "clicks": 4 }
              ],
              "units": -1,
              "unit": "day",
              "unit_reference": "2026-10-19T12:00:00+0000"
            }
            """
        )

        let stats = try await backend.clickStats(for: "bit.ly/3abc")

        XCTAssertEqual(stats.totalClicks, 7)
        XCTAssertEqual(stats.points.map(\.clicks), [3, 4])
        XCTAssertEqual(stats.points.count, 2)

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/v4/bitlinks/bit.ly/3abc/clicks")
        let components = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        let query = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) }
        )
        XCTAssertEqual(query["units"], "-1")
        XCTAssertEqual(query["unit"], "day")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")

        let cached = try store.cachedShortLinks(limit: 10)
        XCTAssertEqual(cached.first?.clickCount, 7)
    }

    // MARK: - Credentials

    func testVerifyTokenUsesUserEndpoint() async {
        respond(status: 200, json: #"{"login":"ernest"}"#)

        let result = await backend.verifyCredentials()

        XCTAssertEqual(result, .valid)
        XCTAssertEqual(MockURLProtocol.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.path, "/v4/user")
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
    }

    func testVerifyTokenReportsInvalid() async {
        respond(status: 401, json: #"{"message":"INVALID_ARG_ACCESS_TOKEN","description":"Invalid token"}"#)
        let result = await backend.verifyCredentials()
        XCTAssertEqual(result, .invalid)
    }

    func testCapabilities() {
        XCTAssertTrue(backend.capabilities.supportsCustomSlug)
        XCTAssertTrue(backend.capabilities.supportsCustomDomain)
        XCTAssertTrue(backend.capabilities.supportsTags)
        XCTAssertTrue(backend.capabilities.supportsUpdateDestination)
        XCTAssertTrue(backend.capabilities.supportsUpdateTags)
        XCTAssertTrue(backend.capabilities.supportsDelete)
        XCTAssertTrue(backend.capabilities.supportsClickStats)
        XCTAssertFalse(backend.capabilities.supportsUpdateSlug)
        XCTAssertEqual(MockURLProtocol.requestCount, 0)
    }

    func testDateParsing() {
        XCTAssertNotNil(BitlyClient.parseDate("2026-10-19T12:00:00.000Z"))
        XCTAssertNotNil(BitlyClient.parseDate("2026-10-19T12:00:00Z"))
        XCTAssertNotNil(BitlyClient.parseDate("2026-10-19T12:00:00+0000"))
        XCTAssertNil(BitlyClient.parseDate("not-a-date"))
    }
}

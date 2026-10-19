import Foundation

/// Thin REST client for Bitly API v4.
/// Docs: https://dev.bitly.com/api-reference/
final class BitlyClient {
    static let defaultBaseURL = URL(string: "https://api-ssl.bitly.com/v4")!

    let baseURL: URL
    let session: URLSession

    private let accessToken: String

    init(
        accessToken: String,
        baseURL: URL = BitlyClient.defaultBaseURL,
        session: URLSession = .shared
    ) {
        self.accessToken = accessToken
        self.baseURL = baseURL
        self.session = session
    }

    var hasAccessToken: Bool {
        !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Endpoints

    /// Auto-generated slug. `POST /shorten`.
    func shorten(
        longURL: URL,
        domain: String?,
        groupGUID: String?
    ) async throws -> ShortLink {
        guard hasAccessToken else { throw ShortenerError.missingAPIKey }

        var body: [String: Any] = ["long_url": longURL.absoluteString]
        if let domain, !domain.isEmpty {
            body["domain"] = domain
        }
        if let groupGUID, !groupGUID.isEmpty {
            body["group_guid"] = groupGUID
        }

        let request = try makeRequest(method: "POST", path: "/shorten", body: body)
        let data = try await perform(request, acceptedStatusCodes: [200, 201])
        return try decodeLink(from: data, fallbackLongURL: longURL)
    }

    /// Custom slug / branded domain. `POST /bitlinks`.
    func createBitlink(
        longURL: URL,
        domain: String,
        keyword: String?,
        groupGUID: String?,
        tags: [String]
    ) async throws -> ShortLink {
        guard hasAccessToken else { throw ShortenerError.missingAPIKey }

        var body: [String: Any] = [
            "long_url": longURL.absoluteString,
            "domain": domain
        ]
        let trimmedKeyword = keyword?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedKeyword, !trimmedKeyword.isEmpty {
            // Bitly v4 names the custom back-half "keyword".
            body["keyword"] = trimmedKeyword
        }
        if let groupGUID, !groupGUID.isEmpty {
            body["group_guid"] = groupGUID
        }
        if !tags.isEmpty {
            body["tags"] = tags
        }

        let request = try makeRequest(method: "POST", path: "/bitlinks", body: body)
        let data = try await perform(request, acceptedStatusCodes: [200, 201])
        return try decodeLink(from: data, fallbackLongURL: longURL)
    }

    /// `PATCH /bitlinks/{bitlink}`. Slugs are immutable in Bitly.
    func updateBitlink(
        bitlink: String,
        longURL: URL?,
        tags: [String]?
    ) async throws -> ShortLink {
        guard hasAccessToken else { throw ShortenerError.missingAPIKey }

        var body: [String: Any] = [:]
        if let longURL {
            body["long_url"] = longURL.absoluteString
        }
        if let tags {
            body["tags"] = tags
        }

        let request = try makeRequest(
            method: "PATCH",
            path: bitlinkPath(bitlink),
            body: body
        )
        let data = try await perform(request, acceptedStatusCodes: [200])
        return try decodeLink(from: data, fallbackLongURL: longURL)
    }

    func deleteBitlink(bitlink: String) async throws {
        guard hasAccessToken else { throw ShortenerError.missingAPIKey }
        let request = try makeRequest(method: "DELETE", path: bitlinkPath(bitlink), body: nil)
        _ = try await perform(request, acceptedStatusCodes: [200, 204])
    }

    /// All-time daily click counts: `GET /bitlinks/{bitlink}/clicks?units=-1&unit=day`.
    func clicks(for bitlink: String) async throws -> LinkClickStats {
        guard hasAccessToken else { throw ShortenerError.missingAPIKey }

        let request = try makeRequest(
            method: "GET",
            path: bitlinkPath(bitlink) + "/clicks",
            queryItems: [
                URLQueryItem(name: "units", value: "-1"),
                URLQueryItem(name: "unit", value: "day")
            ],
            body: nil
        )
        let data = try await perform(request, acceptedStatusCodes: [200])
        let response: ClicksResponse
        do {
            response = try JSONDecoder().decode(ClicksResponse.self, from: data)
        } catch {
            throw ShortenerError.invalidResponse(error.localizedDescription)
        }

        let points = (response.link_clicks ?? []).map { entry in
            LinkClickStatPoint(
                date: Self.parseDate(entry.date) ?? Date(),
                clicks: entry.clicks
            )
        }
        return LinkClickStats(
            totalClicks: points.reduce(0) { $0 + $1.clicks },
            points: points
        )
    }

    /// `GET /user` — the non-mutating token check.
    func verifyAccessToken() async throws -> ShortenerCredentialResult {
        guard hasAccessToken else { return .invalid }

        let request = try makeRequest(method: "GET", path: "/user", body: nil)
        do {
            _ = try await perform(request, acceptedStatusCodes: [200])
            return .valid
        } catch let error as ShortenerError {
            switch error {
            case .unauthorized:
                return .invalid
            case .transport(let message):
                return .unavailable(message)
            case .server(_, let message):
                return .unavailable(message ?? "Server error")
            default:
                return .unavailable(error.localizedDescription)
            }
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    // MARK: - Requests

    private func makeRequest(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: [String: Any]?
    ) throws -> URLRequest {
        guard var components = URLComponents(string: baseURL.absoluteString) else {
            throw ShortenerError.invalidResponse("Invalid base URL")
        }
        components.percentEncodedPath += path
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw ShortenerError.invalidResponse("Invalid request URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            } catch {
                throw ShortenerError.invalidResponse("Could not encode request body")
            }
        }
        return request
    }

    private func perform(_ request: URLRequest, acceptedStatusCodes: Set<Int>) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ShortenerError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ShortenerError.invalidResponse("No HTTP response")
        }

        if acceptedStatusCodes.contains(http.statusCode) {
            return data
        }

        let errorBody = try? JSONDecoder().decode(BitlyErrorResponse.self, from: data)
        let rawCode = (errorBody?.code ?? errorBody?.message ?? "").uppercased()
        let description = errorBody?.description ?? errorBody?.message

        if http.statusCode == 401 || http.statusCode == 403 || rawCode.contains("INVALID_ARG_ACCESS_TOKEN") {
            throw ShortenerError.unauthorized
        }
        if http.statusCode == 404 {
            throw ShortenerError.notFound
        }
        if rawCode.contains("BRANDED_LINK_MONTHLY_LIMIT_EXCEEDED")
            || rawCode.contains("MONTHLY_LIMIT_EXCEEDED") {
            throw ShortenerError.linkLimitReached
        }
        if rawCode.contains("DNS_CONFIGURATION_ERROR") {
            throw ShortenerError.validation(
                "Bitly could not resolve the branded domain. Check its DNS configuration (DNS_CONFIGURATION_ERROR)."
            )
        }
        if http.statusCode == 429 {
            throw ShortenerError.rateLimited
        }
        if http.statusCode == 400 || http.statusCode == 422 {
            throw ShortenerError.validation(description ?? "Bitly rejected the request (HTTP \(http.statusCode)).")
        }
        throw ShortenerError.server(status: http.statusCode, message: description)
    }

    // MARK: - Paths and decoding

    private func bitlinkPath(_ bitlink: String) -> String {
        "/bitlinks/" + Self.encodePathComponent(bitlink)
    }

    /// Encodes the whole Bitlink (`bit.ly/abc`) as one path component.
    static func encodePathComponent(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func decodeLink(from data: Data, fallbackLongURL: URL?) throws -> ShortLink {
        let dto: BitlinkDTO
        do {
            dto = try JSONDecoder().decode(BitlinkDTO.self, from: data)
        } catch {
            throw ShortenerError.invalidResponse(error.localizedDescription)
        }

        let shortURL = dto.link
        let host = URL(string: shortURL)?.host
            ?? dto.id.split(separator: "/").first.map(String.init)
            ?? ""
        let slug = URL(string: shortURL)?.lastPathComponent
            ?? dto.id.split(separator: "/").last.map(String.init)
            ?? ""

        return ShortLink(
            id: dto.id,
            shortUrl: shortURL,
            destinationUrl: dto.long_url ?? fallbackLongURL?.absoluteString ?? "",
            slug: slug,
            domain: host,
            title: dto.title,
            clickCount: nil,
            createdAt: dto.created_at.flatMap(Self.parseDate) ?? Date(),
            backendId: BitlyBackend.backendIdentifier,
            tags: dto.tags ?? []
        )
    }

    static func parseDate(_ string: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: string) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: string) {
            return date
        }
        // Bitly sometimes returns "+0000" without a colon.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss.SSSZ"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: string) {
                return date
            }
        }
        return nil
    }
}

// MARK: - DTOs

private struct BitlyErrorResponse: Decodable {
    let message: String?
    let description: String?
    let resource: String?
    let code: String?
}

private struct BitlinkDTO: Decodable {
    let id: String
    let link: String
    let long_url: String?
    let created_at: String?
    let title: String?
    let tags: [String]?
}

private struct ClicksResponse: Decodable {
    let link_clicks: [ClickEntry]?
}

private struct ClickEntry: Decodable {
    let date: String
    let clicks: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = (try? container.decode(String.self, forKey: .date)) ?? ""
        if let value = try? container.decode(Int.self, forKey: .clicks) {
            clicks = value
        } else if let value = try? container.decode(String.self, forKey: .clicks) {
            clicks = Int(value) ?? 0
        } else {
            clicks = 0
        }
    }

    private enum CodingKeys: String, CodingKey {
        case date
        case clicks
    }
}

import Foundation

/// Default backend: Bitly API v4.
///
/// Auto-slug links use `POST /shorten`; custom slugs/branded domains use
/// `POST /bitlinks`. Tags are applied with a follow-up PATCH on the auto path
/// because `/shorten` has no tags field. Click analytics are read from
/// `GET /bitlinks/{bitlink}/clicks`.
final class BitlyBackend: ShortenerBackend {
    static let backendIdentifier = "bitly"

    let identifier = BitlyBackend.backendIdentifier
    let displayName = "Bitly"
    let capabilities = ShortenerCapabilities.bitly

    private let client: BitlyClient
    private let cache: ShortLinkCaching?
    private let defaultDomain: String
    private let defaultGroupGUID: String
    private let defaultTags: [String]

    init(
        accessToken: String,
        session: URLSession = .shared,
        baseURL: URL = BitlyClient.defaultBaseURL,
        cache: ShortLinkCaching? = nil,
        defaultDomain: String = "bit.ly",
        defaultGroupGUID: String = "",
        defaultTags: [String] = []
    ) {
        self.client = BitlyClient(accessToken: accessToken, baseURL: baseURL, session: session)
        self.cache = cache
        self.defaultDomain = defaultDomain
        self.defaultGroupGUID = defaultGroupGUID
        self.defaultTags = defaultTags
    }

    var isConfigured: Bool { client.hasAccessToken }

    func createLink(
        destinationURL: URL,
        domain: String? = nil,
        slug: String? = nil,
        tags: [String] = []
    ) async throws -> ShortLink {
        guard isConfigured else { throw ShortenerError.missingAPIKey }

        let resolvedDomain = resolvedDomain(domain)
        let resolvedTags = tags.isEmpty ? defaultTags : tags
        let groupGUID = trimmedGroupGUID
        let trimmedSlug = slug?.trimmingCharacters(in: .whitespacesAndNewlines)

        var link: ShortLink
        if let trimmedSlug, !trimmedSlug.isEmpty {
            link = try await client.createBitlink(
                longURL: destinationURL,
                domain: resolvedDomain,
                keyword: trimmedSlug,
                groupGUID: groupGUID,
                tags: resolvedTags
            )
        } else {
            link = try await client.shorten(
                longURL: destinationURL,
                domain: resolvedDomain,
                groupGUID: groupGUID
            )
            if !resolvedTags.isEmpty,
               let updated = try? await client.updateBitlink(
                   bitlink: link.id,
                   longURL: nil,
                   tags: resolvedTags
               ) {
                link = updated
            }
        }

        try? cache?.saveShortLink(link)
        return link
    }

    func updateLink(
        id: String,
        destinationURL: URL? = nil,
        slug: String? = nil,
        tags: [String]? = nil
    ) async throws -> ShortLink {
        guard isConfigured else { throw ShortenerError.missingAPIKey }

        // Bitly's PATCH endpoint supports long_url and tags; slugs are immutable.
        let link = try await client.updateBitlink(
            bitlink: id,
            longURL: destinationURL,
            tags: tags
        )
        try? cache?.saveShortLink(link)
        return link
    }

    func deleteLink(id: String) async throws {
        guard isConfigured else { throw ShortenerError.missingAPIKey }
        try await client.deleteBitlink(bitlink: id)
        try? cache?.deleteShortLink(id: id)
    }

    func cachedLinks(limit: Int = 50) throws -> [ShortLink] {
        guard let cache else { return [] }
        return try cache.cachedShortLinks(limit: limit)
            .filter { $0.backendId == identifier }
    }

    func clickStats(for linkID: String) async throws -> LinkClickStats {
        guard isConfigured else { throw ShortenerError.missingAPIKey }
        let stats = try await client.clicks(for: linkID)
        try? cache?.updateShortLinkClickCount(id: linkID, clickCount: stats.totalClicks)
        return stats
    }

    func verifyCredentials() async -> ShortenerCredentialResult {
        do {
            return try await client.verifyAccessToken()
        } catch let error as ShortenerError {
            switch error {
            case .transport(let message):
                return .unavailable(message)
            default:
                return .unavailable(error.localizedDescription)
            }
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private var trimmedGroupGUID: String? {
        let value = defaultGroupGUID.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func resolvedDomain(_ domain: String?) -> String {
        let trimmed = domain?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        let fallback = defaultDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? "bit.ly" : fallback
    }
}

import Foundation
import GRDB

/// Local cache contract for links created through a shortener backend.
/// Recent Links is app-owned state, so every response we see is cached.
protocol ShortLinkCaching: AnyObject {
    func saveShortLink(_ link: ShortLink) throws
    func cachedShortLinks(limit: Int) throws -> [ShortLink]
    func deleteShortLink(id: String) throws
    func updateShortLinkClickCount(id: String, clickCount: Int) throws
}

struct ShortLink: Identifiable, Equatable, Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "short_links"

    /// Provider-specific identifier. For Bitly this is the full Bitlink form
    /// (`bit.ly/abc123`) exactly as returned by the API.
    var id: String
    var shortUrl: String
    var destinationUrl: String
    var slug: String
    var domain: String
    var title: String?
    var clickCount: Int?
    var createdAt: Date
    var backendId: String
    var tags: [String]

    init(
        id: String,
        shortUrl: String,
        destinationUrl: String,
        slug: String,
        domain: String,
        title: String? = nil,
        clickCount: Int? = nil,
        createdAt: Date = Date(),
        backendId: String,
        tags: [String] = []
    ) {
        self.id = id
        self.shortUrl = shortUrl
        self.destinationUrl = destinationUrl
        self.slug = slug
        self.domain = domain
        self.title = title
        self.clickCount = clickCount
        self.createdAt = createdAt
        self.backendId = backendId
        self.tags = tags
    }
}

struct LinkClickStatPoint: Equatable, Sendable {
    let date: Date
    let clicks: Int
}

struct LinkClickStats: Equatable, Sendable {
    let totalClicks: Int
    let points: [LinkClickStatPoint]

    static let empty = LinkClickStats(totalClicks: 0, points: [])
}

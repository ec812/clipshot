import Foundation
import GRDB

/// A locally stored auto-shorten rule.
///
/// Matching is intentionally simple and deterministic:
/// - `urlPattern` is a glob (`*` = any run of characters) matched against the URL,
///   its host, and host+path. Empty or `*` matches every URL.
/// - `sourceAppPattern` is a glob matched against the source bundle id and app name.
/// - The first enabled rule in priority order wins, so a copy fires at most one rule.
struct ShortenRule: Identifiable, Equatable, Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    static let databaseTableName = "shorten_rules"

    var id: Int64?
    var name: String
    var isEnabled: Bool
    var urlPattern: String
    var sourceAppPattern: String?
    var domain: String?
    var slugTemplate: String?
    var autoCopy: Bool
    var priority: Int
    var createdAt: Date

    init(
        id: Int64? = nil,
        name: String,
        isEnabled: Bool = true,
        urlPattern: String = "*",
        sourceAppPattern: String? = nil,
        domain: String? = nil,
        slugTemplate: String? = nil,
        autoCopy: Bool = true,
        priority: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.urlPattern = urlPattern
        self.sourceAppPattern = sourceAppPattern
        self.domain = domain
        self.slugTemplate = slugTemplate
        self.autoCopy = autoCopy
        self.priority = priority
        self.createdAt = createdAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

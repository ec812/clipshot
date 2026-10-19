import Foundation

struct ShortenerCapabilities: Equatable, Sendable {
    var supportsCustomSlug: Bool
    var supportsCustomDomain: Bool
    var supportsTags: Bool
    var supportsUpdateDestination: Bool
    var supportsUpdateSlug: Bool
    var supportsUpdateTags: Bool
    var supportsDelete: Bool
    var supportsClickStats: Bool

    static let bitly = ShortenerCapabilities(
        supportsCustomSlug: true,
        supportsCustomDomain: true,
        supportsTags: true,
        supportsUpdateDestination: true,
        supportsUpdateSlug: false,
        supportsUpdateTags: true,
        supportsDelete: true,
        supportsClickStats: true
    )
}

enum ShortenerError: LocalizedError, Equatable {
    case missingAPIKey
    case unauthorized
    case notFound
    case linkLimitReached
    case validation(String)
    case rateLimited
    case server(status: Int, message: String?)
    case invalidResponse(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add a Bitly access token in Settings → Integrations."
        case .unauthorized:
            return "The Bitly access token was rejected. Check it in Settings → Integrations."
        case .notFound:
            return "That Bitlink could not be found. It may have been deleted."
        case .linkLimitReached:
            return "Your Bitly plan's branded-link monthly limit has been reached."
        case .validation(let message):
            return message
        case .rateLimited:
            return "Too many requests. Try again in a moment."
        case .server(let status, let message):
            return message ?? "Bitly returned an error (HTTP \(status))."
        case .invalidResponse(let message):
            return "Unexpected response from Bitly: \(message)"
        case .transport(let message):
            return "Network error: \(message)"
        }
    }
}

enum ShortenerCredentialResult: Equatable, Sendable {
    case valid
    case invalid
    case unavailable(String)
}

/// The only surface the UI is allowed to use for shortening.
/// Concrete providers (Bitly today; dub or others later) are registered in
/// `ShortenerBackendRegistry` and selected in Settings.
protocol ShortenerBackend: AnyObject {
    var identifier: String { get }
    var displayName: String { get }
    var capabilities: ShortenerCapabilities { get }
    var isConfigured: Bool { get }

    func createLink(
        destinationURL: URL,
        domain: String?,
        slug: String?,
        tags: [String]
    ) async throws -> ShortLink

    func updateLink(
        id: String,
        destinationURL: URL?,
        slug: String?,
        tags: [String]?
    ) async throws -> ShortLink

    func deleteLink(id: String) async throws

    /// Links this backend has created, read from the local cache.
    /// Bitly's list endpoint is group-scoped, so the app keeps its own view.
    func cachedLinks(limit: Int) throws -> [ShortLink]

    /// Click counts over time for a Bitlink, when the provider supports them.
    func clickStats(for linkID: String) async throws -> LinkClickStats

    func verifyCredentials() async -> ShortenerCredentialResult
}

struct ShortenerCredentials {
    var accessToken: String?
    var defaultDomain: String
    var defaultGroupGUID: String
    var defaultTags: [String]
    var session: URLSession
    var cache: ShortLinkCaching?

    init(
        accessToken: String? = nil,
        defaultDomain: String = "bit.ly",
        defaultGroupGUID: String = "",
        defaultTags: [String] = [],
        session: URLSession = .shared,
        cache: ShortLinkCaching? = nil
    ) {
        self.accessToken = accessToken
        self.defaultDomain = defaultDomain
        self.defaultGroupGUID = defaultGroupGUID
        self.defaultTags = defaultTags
        self.session = session
        self.cache = cache
    }
}

/// Swappable provider registry. Each descriptor knows how to build a backend
/// from the credentials the app owns.
final class ShortenerBackendRegistry {
    struct Descriptor {
        let id: String
        let displayName: String
        let make: (ShortenerCredentials) -> ShortenerBackend
    }

    static let shared = ShortenerBackendRegistry()

    private(set) var descriptors: [Descriptor] = []

    init() {}

    func register(id: String, displayName: String, make: @escaping (ShortenerCredentials) -> ShortenerBackend) {
        guard !descriptors.contains(where: { $0.id == id }) else { return }
        descriptors.append(Descriptor(id: id, displayName: displayName, make: make))
    }

    func registerBuiltIns() {
        register(id: BitlyBackend.backendIdentifier, displayName: "Bitly") { credentials in
            BitlyBackend(
                accessToken: credentials.accessToken ?? "",
                session: credentials.session,
                cache: credentials.cache,
                defaultDomain: credentials.defaultDomain,
                defaultGroupGUID: credentials.defaultGroupGUID,
                defaultTags: credentials.defaultTags
            )
        }
    }

    func descriptor(for id: String) -> Descriptor? {
        descriptors.first { $0.id == id }
    }

    func makeBackend(id: String, credentials: ShortenerCredentials) -> ShortenerBackend? {
        descriptor(for: id)?.make(credentials)
    }

    var defaultBackendID: String {
        descriptors.first?.id ?? BitlyBackend.backendIdentifier
    }
}

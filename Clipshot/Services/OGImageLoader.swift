import Foundation
import ImageIO

/// Fetches and caches a page's Open Graph image, title and description.
///
/// One HTML fetch supplies all metadata; the image is downloaded separately.
/// All work is async and intended to run off the main thread. Failures are
/// negative-cached by `OGImageCache` so dead pages are not hammered.
final class OGImageLoader: @unchecked Sendable {
    struct Configuration {
        var pageTimeout: TimeInterval = 5
        var imageTimeout: TimeInterval = 10
        var maxHTMLBytes: Int = 1_500_000
        var maxImageBytes: Int = 10_000_000
    }

    let cache: OGImageCache
    let configuration: Configuration

    private let session: URLSession

    init(
        cache: OGImageCache = OGImageCache(directory: OGImageCache.defaultDirectory()),
        session: URLSession? = nil,
        configuration: Configuration = Configuration()
    ) {
        self.cache = cache
        self.configuration = configuration

        if let session {
            self.session = session
        } else {
            let sessionConfiguration = URLSessionConfiguration.ephemeral
            sessionConfiguration.timeoutIntervalForRequest = max(
                configuration.pageTimeout,
                configuration.imageTimeout
            )
            sessionConfiguration.timeoutIntervalForResource = max(
                configuration.pageTimeout,
                configuration.imageTimeout
            ) + 5
            sessionConfiguration.httpAdditionalHeaders = [
                "User-Agent": "Clipshot/1.0 (macOS; link preview)"
            ]
            self.session = URLSession(configuration: sessionConfiguration)
        }
    }

    /// Returns cached or freshly fetched OG metadata and image bytes.
    func preview(for pageURL: URL) async -> OGPagePreview? {
        guard let scheme = pageURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              pageURL.host != nil
        else { return nil }

        switch cache.lookup(url: pageURL) {
        case .preview(let preview):
            return preview
        case .negative:
            return nil
        case .miss:
            break
        }

        do {
            let (htmlData, htmlResponse) = try await fetch(
                pageURL,
                timeout: configuration.pageTimeout,
                maxBytes: configuration.maxHTMLBytes,
                accept: "text/html,application/xhtml+xml;q=0.9,*/*;q=0.1"
            )
            guard Self.isHTMLResponse(htmlResponse) else {
                throw OGImageError.notHTML
            }
            guard let html = String(data: htmlData, encoding: .utf8)
                ?? String(data: htmlData, encoding: .isoLatin1)
            else {
                throw OGImageError.notHTML
            }

            let metadata = OGImageParser.metadata(
                fromHTML: html,
                baseURL: htmlResponse.url ?? pageURL
            )
            guard !metadata.isEmpty else {
                throw OGImageError.noMetadata
            }

            var imageData: Data?
            if let imageURL = metadata.imageURL {
                do {
                    let (data, response) = try await fetch(
                        imageURL,
                        timeout: configuration.imageTimeout,
                        maxBytes: configuration.maxImageBytes,
                        accept: "image/*,*/*;q=0.1"
                    )
                    if Self.isImageResponse(response), Self.isDecodableImage(data) {
                        imageData = data
                    }
                } catch {
                    if Task.isCancelled || Self.isCancellation(error) {
                        throw error
                    }
                    // Keep the title/description even if the image fails.
                }
            }

            let preview = OGPagePreview(imageData: imageData, metadata: metadata)
            guard !preview.isEmpty else {
                throw OGImageError.noMetadata
            }
            cache.storePreview(preview, for: pageURL)
            return preview
        } catch {
            if Task.isCancelled || Self.isCancellation(error) {
                return nil
            }
            cache.storeFailure(for: pageURL)
            return nil
        }
    }

    /// Backwards-compatible image-only entry point.
    func imageData(for pageURL: URL) async -> Data? {
        await preview(for: pageURL)?.imageData
    }

    func clearCache() {
        cache.clear()
    }

    // MARK: - Networking

    private func fetch(
        _ url: URL,
        timeout: TimeInterval,
        maxBytes: Int,
        accept: String
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: timeout
        )
        request.setValue(accept, forHTTPHeaderField: "Accept")

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OGImageError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OGImageError.httpStatus(http.statusCode)
        }

        var data = Data()
        data.reserveCapacity(min(maxBytes, 128 * 1024))
        for try await byte in bytes {
            data.append(byte)
            if data.count > maxBytes {
                throw OGImageError.tooLarge
            }
        }
        return (data, http)
    }

    private static func isHTMLResponse(_ response: HTTPURLResponse) -> Bool {
        let mime = (response.mimeType
            ?? response.value(forHTTPHeaderField: "Content-Type")
            ?? "").lowercased()
        if mime.isEmpty { return true }
        return mime.contains("text/html") || mime.contains("application/xhtml")
    }

    private static func isImageResponse(_ response: HTTPURLResponse) -> Bool {
        let mime = (response.mimeType
            ?? response.value(forHTTPHeaderField: "Content-Type")
            ?? "").lowercased()
        return mime.hasPrefix("image/")
    }

    private static func isDecodableImage(_ data: Data) -> Bool {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
        else { return false }
        return true
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}

enum OGImageError: Error {
    case invalidResponse
    case httpStatus(Int)
    case notHTML
    case noMetadata
    case notImage
    case tooLarge
}

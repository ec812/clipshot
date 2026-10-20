import Foundation

struct OGMetadata: Codable, Equatable, Sendable {
    var title: String?
    var description: String?
    var imageURL: URL?

    var isEmpty: Bool {
        title == nil && description == nil && imageURL == nil
    }
}

struct OGPagePreview: Equatable, Sendable {
    var imageData: Data?
    var metadata: OGMetadata

    var isEmpty: Bool {
        imageData == nil && metadata.title == nil && metadata.description == nil
    }
}

/// Extracts Open Graph / Twitter / plain-head metadata from HTML without a
/// full parser. Regex-based on purpose: it tolerates malformed markup.
enum OGImageParser {
    static func metadata(fromHTML html: String, baseURL: URL) -> OGMetadata {
        let nsHTML = html as NSString
        let matches = metaRegex.matches(
            in: html,
            range: NSRange(location: 0, length: nsHTML.length)
        )

        var ogImage: String?
        var twitterImage: String?
        var ogTitle: String?
        var twitterTitle: String?
        var ogDescription: String?
        var twitterDescription: String?
        var metaDescription: String?

        for match in matches {
            let tag = nsHTML.substring(with: match.range)
            let attributes = parseAttributes(tag)
            guard let content = attributes["content"],
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }

            let key = (attributes["property"] ?? attributes["name"])?.lowercased()
            switch key {
            case "og:image", "og:image:url", "og:image:secure_url":
                if ogImage == nil { ogImage = content }
            case "twitter:image", "twitter:image:src":
                if twitterImage == nil { twitterImage = content }
            case "og:title":
                if ogTitle == nil { ogTitle = content }
            case "twitter:title":
                if twitterTitle == nil { twitterTitle = content }
            case "og:description":
                if ogDescription == nil { ogDescription = content }
            case "twitter:description":
                if twitterDescription == nil { twitterDescription = content }
            case "description":
                if metaDescription == nil { metaDescription = content }
            default:
                break
            }
        }

        return OGMetadata(
            title: normalizedText(ogTitle)
                ?? normalizedText(twitterTitle)
                ?? titleTag(in: html),
            description: normalizedText(ogDescription)
                ?? normalizedText(twitterDescription)
                ?? normalizedText(metaDescription),
            imageURL: resolve(ogImage, baseURL: baseURL)
                ?? resolve(twitterImage, baseURL: baseURL)
        )
    }

    /// Backwards-compatible image-only entry point.
    static func imageURL(fromHTML html: String, baseURL: URL) -> URL? {
        metadata(fromHTML: html, baseURL: baseURL).imageURL
    }

    // MARK: - Parsing helpers

    private static let metaRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"<meta\b[^>]*>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
    }()

    private static let titleRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"<title\b[^>]*>(.*?)</title>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
    }()

    private static let attributeRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"([A-Za-z_:][A-Za-z0-9_:.\-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>"']+))"#,
            options: [.caseInsensitive]
        )
    }()

    static func titleTag(in html: String) -> String? {
        let nsHTML = html as NSString
        guard let match = titleRegex.firstMatch(
            in: html,
            range: NSRange(location: 0, length: nsHTML.length)
        ), let range = Range(match.range(at: 1), in: html)
        else { return nil }
        return normalizedText(String(html[range]))
    }

    static func parseAttributes(_ tag: String) -> [String: String] {
        let nsTag = tag as NSString
        let matches = attributeRegex.matches(
            in: tag,
            range: NSRange(location: 0, length: nsTag.length)
        )
        var result: [String: String] = [:]
        for match in matches {
            guard let nameRange = Range(match.range(at: 1), in: tag) else { continue }
            let name = String(tag[nameRange]).lowercased()
            var value: String?
            for group in 2...4 {
                if match.range(at: group).location != NSNotFound,
                   let range = Range(match.range(at: group), in: tag) {
                    value = String(tag[range])
                    break
                }
            }
            if let value {
                result[name] = value
            }
        }
        return result
    }

    static func resolve(_ candidate: String?, baseURL: URL) -> URL? {
        guard let candidate else { return nil }
        let decoded = decodeHTMLEntities(candidate)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !decoded.isEmpty else { return nil }
        guard let url = URL(string: decoded, relativeTo: baseURL)?.absoluteURL else { return nil }
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else { return nil }
        return url
    }

    static func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let decoded = decodeHTMLEntities(value)
        let collapsed = decoded.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func decodeHTMLEntities(_ value: String) -> String {
        var result = value
        let replacements: [(String, String)] = [
            ("&quot;", "\""),
            ("&#34;", "\""),
            ("&apos;", "'"),
            ("&#39;", "'"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&#x2F;", "/"),
            ("&#47;", "/"),
            ("&nbsp;", " "),
            ("&amp;", "&")
        ]
        for (entity, replacement) in replacements {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }
}

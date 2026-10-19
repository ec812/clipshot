import Foundation

/// Extracts an Open Graph or Twitter image URL from HTML without a full parser.
/// Regex-based on purpose: it tolerates malformed markup and works on partial pages.
enum OGImageParser {
    static func imageURL(fromHTML html: String, baseURL: URL) -> URL? {
        let nsHTML = html as NSString
        let matches = metaRegex.matches(
            in: html,
            range: NSRange(location: 0, length: nsHTML.length)
        )

        var openGraph: String?
        var twitter: String?

        for match in matches {
            let tag = nsHTML.substring(with: match.range)
            let attributes = parseAttributes(tag)
            guard let content = attributes["content"],
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }

            let key = (attributes["property"] ?? attributes["name"])?.lowercased()
            switch key {
            case "og:image", "og:image:url", "og:image:secure_url":
                if openGraph == nil { openGraph = content }
            case "twitter:image", "twitter:image:src":
                if twitter == nil { twitter = content }
            default:
                break
            }
        }

        for candidate in [openGraph, twitter].compactMap({ $0 }) {
            if let url = resolve(candidate, baseURL: baseURL) {
                return url
            }
        }
        return nil
    }

    // MARK: - Parsing helpers

    private static let metaRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"<meta\b[^>]*>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
    }()

    private static let attributeRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"([A-Za-z_:][A-Za-z0-9_:.\-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>"']+))"#,
            options: [.caseInsensitive]
        )
    }()

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

    static func resolve(_ candidate: String, baseURL: URL) -> URL? {
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

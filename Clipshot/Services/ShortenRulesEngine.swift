import Foundation

struct ShortenRuleContext: Equatable {
    var url: URL?
    var sourceApp: String?
    var bundleId: String?
    var date: Date

    init(url: URL?, sourceApp: String? = nil, bundleId: String? = nil, date: Date = Date()) {
        self.url = url
        self.sourceApp = sourceApp
        self.bundleId = bundleId
        self.date = date
    }
}

/// Evaluates stored auto-shorten rules.
///
/// Rules are ordered by priority; the first enabled match is returned, so a
/// single clipboard capture can trigger at most one auto-shorten action.
final class ShortenRulesEngine {
    private let store: HistoryStore

    init(store: HistoryStore) {
        self.store = store
    }

    func matchingRule(for context: ShortenRuleContext) throws -> ShortenRule? {
        guard let url = context.url else { return nil }
        for rule in try store.enabledShortenRules() {
            if Self.rule(rule, matches: context, url: url) {
                return rule
            }
        }
        return nil
    }

    static func rule(_ rule: ShortenRule, matches context: ShortenRuleContext, url: URL) -> Bool {
        guard rule.isEnabled else { return false }

        if !matchesGlob(rule.urlPattern, candidates: urlCandidates(for: url)) {
            return false
        }

        if let sourcePattern = rule.sourceAppPattern?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sourcePattern.isEmpty {
            let candidates = [context.bundleId, context.sourceApp].compactMap { $0 }
            guard matchesGlob(sourcePattern, candidates: candidates) else {
                return false
            }
        }

        return true
    }

    static func urlCandidates(for url: URL) -> [String] {
        var candidates = [url.absoluteString]
        if let host = url.host {
            candidates.append(host)
            candidates.append(host + url.path)
        }
        return candidates
    }

    static func matchesGlob(_ pattern: String, candidates: [String]) -> Bool {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard !candidates.isEmpty else { return false }
        return candidates.contains { globMatch(trimmed, $0) }
    }

    static func globMatch(_ pattern: String, _ value: String) -> Bool {
        if pattern == "*" { return true }
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
        let expression = "^"
            + escaped
                .replacingOccurrences(of: "\\*", with: ".*")
                .replacingOccurrences(of: "\\?", with: ".")
            + "$"
        return value.range(of: expression, options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: - Slug templating

    static func renderSlug(template: String, url: URL, date: Date = Date()) -> String {
        var result = template

        let host = (url.host ?? "")
            .replacingOccurrences(of: "www.", with: "", options: [.anchored, .caseInsensitive])
        result = result.replacingOccurrences(of: "{host}", with: host)

        let lastPathComponent = url.pathComponents
            .last { $0 != "/" } ?? ""
        result = result.replacingOccurrences(of: "{path}", with: lastPathComponent)

        let firstWord = firstWord(in: lastPathComponent) ?? firstWord(in: host) ?? "link"
        result = result.replacingOccurrences(of: "{word}", with: firstWord)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd"
        result = result.replacingOccurrences(of: "{date}", with: formatter.string(from: date))

        for _ in 0..<8 {
            guard let range = result.range(of: "{rand}") else { break }
            result.replaceSubrange(range, with: String(randomSlug(length: 4)))
        }

        return sanitizeSlug(result)
    }

    static func sanitizeSlug(_ raw: String) -> String {
        let lowered = raw.lowercased()
        var output = ""
        var lastWasSeparator = false
        for character in lowered {
            if character.isLetter || character.isNumber {
                output.append(character)
                lastWasSeparator = false
            } else if !lastWasSeparator {
                output.append("-")
                lastWasSeparator = true
            }
        }
        while output.hasPrefix("-") { output.removeFirst() }
        while output.hasSuffix("-") { output.removeLast() }
        if output.count > 64 {
            output = String(output.prefix(64))
            while output.hasSuffix("-") { output.removeLast() }
        }
        return output
    }

    private static func firstWord(in value: String) -> String? {
        let words = value
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }
        return words.first
    }

    private static func randomSlug(length: Int) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<length).map { _ in alphabet.randomElement() ?? "a" })
    }
}

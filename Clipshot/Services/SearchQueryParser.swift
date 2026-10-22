import Foundation

/// A search bar query after power-search syntax has been extracted.
///
/// The parser is pure: it performs no I/O and never reads the clock. Relative
/// date filters are kept symbolic (`.lastHours`, `.today`, `.yesterday`) and
/// resolved to a `DateInterval` by the caller with an injected `now`.
struct ParsedSearchQuery: Equatable {
    enum DateFilter: Equatable {
        case lastHours(Int)
        case today
        case yesterday

        /// Resolves the symbolic filter against `now`. Callers pass the clock so
        /// parsing and tests stay deterministic.
        func interval(now: Date, calendar: Calendar = .current) -> DateInterval {
            switch self {
            case .lastHours(let hours):
                return DateInterval(
                    start: now.addingTimeInterval(-Double(hours) * 3600),
                    end: now
                )
            case .today:
                return DateInterval(start: calendar.startOfDay(for: now), end: now)
            case .yesterday:
                let startOfToday = calendar.startOfDay(for: now)
                let startOfYesterday = calendar.date(
                    byAdding: .day,
                    value: -1,
                    to: startOfToday
                ) ?? startOfToday
                return DateInterval(start: startOfYesterday, end: startOfToday)
            }
        }
    }

    /// Words left over after recognised clauses are removed. Feeds the FTS query.
    var freeText: String = ""
    var kind: ClipboardItemKind?
    /// Exact, case-insensitive match against `items.sourceApp` or `items.bundleId`.
    var fromApp: String?
    var dateFilter: DateFilter?
    /// Pinboard name to resolve against the published pinboards. Unresolved
    /// names become free text instead of hiding every result.
    var pinboardName: String?
    /// Exact phrase forced into the FTS query via `text:"…"`.
    var phrase: String?
}

/// Parses the typed power-search syntax out of the search bar text.
///
/// Supported keys (case-insensitive): `kind:`, `from:`, `date:`, `pinboard:`,
/// `text:`. Values may be quoted to include spaces (`from:"Safari"`).
///
/// Fallback rules, chosen so typing is never silently discarded:
/// - Unrecognised `key:value` tokens are treated as free text.
/// - A recognised key with an unrecognised value (`kind:banana`,
///   `date:banana`) also stays in the free text.
/// - A recognised key with an empty value (`kind:`, `pinboard:""`) contributes
///   nothing; there is no filter and no free text.
/// - Repeating a key keeps the last occurrence.
enum SearchQueryParser {
    static func parse(_ raw: String) -> ParsedSearchQuery {
        var parsed = ParsedSearchQuery()
        var freeParts: [String] = []

        for token in tokenize(raw) {
            guard let colon = token.firstIndex(of: ":") else {
                appendFreeText(unquote(token), to: &freeParts)
                continue
            }

            let key = token[..<colon].lowercased()
            let value = unquote(String(token[token.index(after: colon)...]))

            switch key {
            case "kind":
                guard !value.isEmpty else { continue }
                if let kind = kind(from: value) {
                    parsed.kind = kind
                } else {
                    freeParts.append(token)
                }
            case "from":
                guard !value.isEmpty else { continue }
                parsed.fromApp = value
            case "date":
                guard !value.isEmpty else { continue }
                if let filter = dateFilter(from: value) {
                    parsed.dateFilter = filter
                } else {
                    freeParts.append(token)
                }
            case "pinboard":
                guard !value.isEmpty else { continue }
                parsed.pinboardName = value
            case "text":
                guard !value.isEmpty else { continue }
                parsed.phrase = value
            default:
                freeParts.append(token)
            }
        }

        parsed.freeText = freeParts.joined(separator: " ")
        return parsed
    }

    // MARK: - Tokens

    /// Splits on whitespace while keeping quoted spans together, so
    /// `text:"a b"` arrives as a single token.
    static func tokenize(_ raw: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false

        for character in raw {
            if character == "\"" {
                inQuotes.toggle()
                current.append(character)
            } else if character.isWhitespace, !inQuotes {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private static func unquote(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2, trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") else {
            return trimmed
        }
        return String(trimmed.dropFirst().dropLast())
    }

    private static func appendFreeText(_ value: String, to parts: inout [String]) {
        guard !value.isEmpty else { return }
        parts.append(value)
    }

    // MARK: - Values

    private static func kind(from value: String) -> ClipboardItemKind? {
        let lowercased = value.lowercased()
        if let kind = ClipboardItemKind(rawValue: lowercased) {
            return kind
        }
        return ClipboardItemKind.allCases.first { $0.displayName.lowercased() == lowercased }
    }

    private static func dateFilter(from value: String) -> ParsedSearchQuery.DateFilter? {
        let lowercased = value.lowercased()
        switch lowercased {
        case "today":
            return .today
        case "yesterday":
            return .yesterday
        default:
            break
        }

        if lowercased.hasSuffix("h"), let hours = Int(lowercased.dropLast()), hours > 0 {
            return .lastHours(hours)
        }
        if lowercased.hasSuffix("d"), let days = Int(lowercased.dropLast()), days > 0 {
            return .lastHours(days * 24)
        }
        return nil
    }
}

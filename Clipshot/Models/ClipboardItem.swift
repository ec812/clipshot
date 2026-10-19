import Foundation
import GRDB

enum ClipboardItemKind: String, Codable, CaseIterable, DatabaseValueConvertible, Sendable {
    case text
    case url
    case rtf
    case image
    case file
    case color

    var displayName: String {
        switch self {
        case .text: return "Text"
        case .url: return "Link"
        case .rtf: return "Rich Text"
        case .image: return "Image"
        case .file: return "File"
        case .color: return "Color"
        }
    }

    var systemImage: String {
        switch self {
        case .text: return "text.alignleft"
        case .url: return "link"
        case .rtf: return "doc.richtext"
        case .image: return "photo"
        case .file: return "doc"
        case .color: return "paintpalette"
        }
    }
}

struct ClipboardItem: Identifiable, Equatable, Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    static let databaseTableName = "items"

    var id: Int64?
    var kind: ClipboardItemKind
    var text: String?
    var title: String?
    var dataPath: String?
    var sourceApp: String?
    var bundleId: String?
    var createdAt: Date
    var isPinned: Bool
    var shortUrl: String?
    var hash: String
    var pinboardId: Int64?
    var isSnippet: Bool

    init(
        id: Int64? = nil,
        kind: ClipboardItemKind,
        text: String?,
        title: String? = nil,
        dataPath: String? = nil,
        sourceApp: String? = nil,
        bundleId: String? = nil,
        createdAt: Date = Date(),
        isPinned: Bool = false,
        shortUrl: String? = nil,
        hash: String,
        pinboardId: Int64? = nil,
        isSnippet: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.title = title
        self.dataPath = dataPath
        self.sourceApp = sourceApp
        self.bundleId = bundleId
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.shortUrl = shortUrl
        self.hash = hash
        self.pinboardId = pinboardId
        self.isSnippet = isSnippet
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// The plain value used when pasting. Short links are applied by the
    /// caller when "prefer short links" is enabled.
    var pasteText: String? {
        text
    }

    var displayText: String {
        text ?? title ?? kind.displayName
    }

    var previewText: String {
        guard let text else {
            return title ?? kind.displayName
        }
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.count > 320 {
            return String(collapsed.prefix(320)) + "…"
        }
        return collapsed
    }

    var url: URL? {
        guard kind == .url, let text else { return nil }
        return URL(string: text)
    }

    var hasShortLink: Bool {
        guard let shortUrl else { return false }
        return !shortUrl.isEmpty
    }
}

struct Pinboard: Identifiable, Equatable, Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    static let databaseTableName = "pinboards"

    var id: Int64?
    var name: String
    var colorHex: String
    var createdAt: Date

    init(id: Int64? = nil, name: String, colorHex: String = "#FF9F0A", createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

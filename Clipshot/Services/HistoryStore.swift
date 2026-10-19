import Foundation
import GRDB

struct InsertOutcome {
    let item: ClipboardItem
    let wasInserted: Bool
}

final class HistoryStore: ShortLinkCaching, @unchecked Sendable {
    let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try Self.migrator.migrate(dbQueue)
    }

    convenience init(path: String) throws {
        try self.init(dbQueue: DatabaseQueue(path: path))
    }

    static func inMemory() throws -> HistoryStore {
        try HistoryStore(dbQueue: DatabaseQueue())
    }

    static func defaultDatabaseURL() throws -> URL {
        let fileManager = FileManager.default
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("Clipshot", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("clipshot.sqlite")
    }

    // MARK: - Migrations

    static let migrator: DatabaseMigrator = {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "pinboards") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("name", .text).notNull()
                table.column("colorHex", .text).notNull()
                table.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "items") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("kind", .text).notNull()
                table.column("text", .text)
                table.column("title", .text)
                table.column("dataPath", .text)
                table.column("sourceApp", .text)
                table.column("bundleId", .text)
                table.column("createdAt", .datetime).notNull().indexed()
                table.column("isPinned", .boolean).notNull().defaults(to: false)
                table.column("shortUrl", .text)
                table.column("hash", .text).notNull().unique()
                table.column("pinboardId", .integer).references("pinboards", onDelete: .setNull)
                table.column("isSnippet", .boolean).notNull().defaults(to: false)
            }

            try db.create(table: "short_links") { table in
                table.primaryKey("id", .text)
                table.column("shortUrl", .text).notNull()
                table.column("destinationUrl", .text).notNull()
                table.column("slug", .text).notNull()
                table.column("domain", .text).notNull()
                table.column("title", .text)
                table.column("clickCount", .integer)
                table.column("createdAt", .datetime).notNull().indexed()
                table.column("backendId", .text).notNull()
                table.column("tags", .text).notNull().defaults(to: "[]")
            }

            try db.create(table: "shorten_rules") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("name", .text).notNull()
                table.column("isEnabled", .boolean).notNull().defaults(to: true)
                table.column("urlPattern", .text).notNull().defaults(to: "*")
                table.column("sourceAppPattern", .text)
                table.column("domain", .text)
                table.column("slugTemplate", .text)
                table.column("autoCopy", .boolean).notNull().defaults(to: true)
                table.column("priority", .integer).notNull().defaults(to: 0)
                table.column("createdAt", .datetime).notNull()
            }

            try db.execute(sql: """
                CREATE VIRTUAL TABLE items_fts USING fts5(
                    text,
                    title,
                    content='items',
                    content_rowid='id',
                    tokenize='unicode61'
                )
                """)

            try db.execute(sql: """
                CREATE TRIGGER items_ai AFTER INSERT ON items BEGIN
                    INSERT INTO items_fts(rowid, text, title) VALUES (new.id, new.text, new.title);
                END
                """)

            try db.execute(sql: """
                CREATE TRIGGER items_ad AFTER DELETE ON items BEGIN
                    INSERT INTO items_fts(items_fts, rowid, text, title)
                    VALUES ('delete', old.id, old.text, old.title);
                END
                """)

            try db.execute(sql: """
                CREATE TRIGGER items_au AFTER UPDATE ON items BEGIN
                    INSERT INTO items_fts(items_fts, rowid, text, title)
                    VALUES ('delete', old.id, old.text, old.title);
                    INSERT INTO items_fts(rowid, text, title) VALUES (new.id, new.text, new.title);
                END
                """)
        }

        migrator.registerMigration("v2-bitly-backend") { db in
            // Drop cached links created by the previous shortening provider.
            try db.execute(sql: "DELETE FROM short_links WHERE backendId <> 'bitly'")
        }

        return migrator
    }()

    // MARK: - Items

    @discardableResult
    func insert(
        kind: ClipboardItemKind,
        text: String?,
        title: String? = nil,
        dataPath: String? = nil,
        sourceApp: String? = nil,
        bundleId: String? = nil,
        hash: String,
        isSnippet: Bool = false,
        now: Date = Date()
    ) throws -> InsertOutcome {
        try dbQueue.write { db in
            if var existing = try ClipboardItem.filter(Column("hash") == hash).fetchOne(db) {
                existing.kind = kind
                existing.text = text
                existing.title = title ?? existing.title
                existing.dataPath = dataPath ?? existing.dataPath
                existing.sourceApp = sourceApp ?? existing.sourceApp
                existing.bundleId = bundleId ?? existing.bundleId
                existing.createdAt = now
                try existing.update(db)
                return InsertOutcome(item: existing, wasInserted: false)
            }

            var item = ClipboardItem(
                kind: kind,
                text: text,
                title: title,
                dataPath: dataPath,
                sourceApp: sourceApp,
                bundleId: bundleId,
                createdAt: now,
                hash: hash,
                isSnippet: isSnippet
            )
            try item.insert(db)
            return InsertOutcome(item: item, wasInserted: true)
        }
    }

    func recent(limit: Int = 300) throws -> [ClipboardItem] {
        try dbQueue.read { db in
            try ClipboardItem
                .order(Column("isPinned").desc, Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func search(
        _ rawQuery: String,
        kind: ClipboardItemKind? = nil,
        bundleId: String? = nil,
        limit: Int = 300
    ) throws -> [ClipboardItem] {
        let ftsQuery = FTSQuery.make(from: rawQuery)
        guard !ftsQuery.isEmpty else {
            var request = ClipboardItem
                .order(Column("isPinned").desc, Column("createdAt").desc)
            if let kind {
                request = request.filter(Column("kind") == kind.rawValue)
            }
            if let bundleId {
                request = request.filter(Column("bundleId") == bundleId)
            }
            return try dbQueue.read { db in
                try request.limit(limit).fetchAll(db)
            }
        }

        var sql = """
            SELECT items.* FROM items
            JOIN items_fts ON items_fts.rowid = items.id
            WHERE items_fts MATCH ?
            """
        var arguments: StatementArguments = [ftsQuery]

        if let kind {
            sql += " AND items.kind = ?"
            _ = arguments.append(contentsOf: [kind.rawValue])
        }
        if let bundleId {
            sql += " AND items.bundleId = ?"
            _ = arguments.append(contentsOf: [bundleId])
        }
        sql += " ORDER BY items.isPinned DESC, items_fts.rank, items.createdAt DESC LIMIT ?"
        _ = arguments.append(contentsOf: [limit])

        return try dbQueue.read { db in
            try ClipboardItem.fetchAll(db, sql: sql, arguments: arguments)
        }
    }

    func item(id: Int64) throws -> ClipboardItem? {
        try dbQueue.read { db in
            try ClipboardItem.fetchOne(db, key: id)
        }
    }

    func setPinned(_ pinned: Bool, for itemID: Int64) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE items SET isPinned = ? WHERE id = ?",
                arguments: [pinned, itemID]
            )
        }
    }

    func updateText(_ text: String, title: String?, for itemID: Int64) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE items SET text = ?, title = ?, kind = ? WHERE id = ?",
                arguments: [text, title, ClipboardItemKind.text.rawValue, itemID]
            )
        }
    }

    func rename(_ title: String, for itemID: Int64) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE items SET title = ? WHERE id = ?",
                arguments: [title, itemID]
            )
        }
    }

    func setShortURL(_ shortURL: String, for itemID: Int64) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE items SET shortUrl = ? WHERE id = ?",
                arguments: [shortURL, itemID]
            )
        }
    }

    func deleteItem(id: Int64) throws {
        _ = try dbQueue.write { db in
            try ClipboardItem.deleteOne(db, key: id)
        }
    }

    @discardableResult
    func purgeItems(olderThan cutoff: Date) throws -> Int {
        try dbQueue.write { db in
            try ClipboardItem
                .filter(Column("isPinned") == false)
                .filter(Column("pinboardId") == nil)
                .filter(Column("createdAt") < cutoff)
                .deleteAll(db)
        }
    }

    /// Applies retention. A value <= 0 means "keep forever" (Paste's default).
    @discardableResult
    func applyRetention(days: Int, now: Date = Date()) throws -> Int {
        guard days > 0 else { return 0 }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        return try purgeItems(olderThan: cutoff)
    }

    func itemCount() throws -> Int {
        try dbQueue.read { db in
            try ClipboardItem.fetchCount(db)
        }
    }

    func distinctSources(limit: Int = 30) throws -> [(bundleId: String, sourceApp: String)] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT bundleId, sourceApp, MAX(createdAt) AS latest
                    FROM items
                    WHERE bundleId IS NOT NULL
                    GROUP BY bundleId
                    ORDER BY latest DESC
                    LIMIT ?
                    """,
                arguments: [limit]
            )
            return rows.compactMap { row in
                guard let bundleId: String = row["bundleId"] else { return nil }
                return (bundleId, (row["sourceApp"] as String?) ?? bundleId)
            }
        }
    }

    // MARK: - Pinboards

    @discardableResult
    func createPinboard(name: String, colorHex: String, now: Date = Date()) throws -> Pinboard {
        var pinboard = Pinboard(name: name, colorHex: colorHex, createdAt: now)
        try dbQueue.write { db in
            try pinboard.insert(db)
        }
        return pinboard
    }

    func pinboards() throws -> [Pinboard] {
        try dbQueue.read { db in
            try Pinboard.order(Column("createdAt")).fetchAll(db)
        }
    }

    func renamePinboard(id: Int64, name: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE pinboards SET name = ? WHERE id = ?", arguments: [name, id])
        }
    }

    func deletePinboard(id: Int64) throws {
        try dbQueue.write { db in
            _ = try Pinboard.deleteOne(db, key: id)
        }
    }

    func addItem(_ itemID: Int64, toPinboard pinboardID: Int64) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE items SET pinboardId = ?, isPinned = 1 WHERE id = ?",
                arguments: [pinboardID, itemID]
            )
        }
    }

    func removeItemFromPinboard(_ itemID: Int64) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE items SET pinboardId = NULL, isPinned = 0 WHERE id = ?",
                arguments: [itemID]
            )
        }
    }

    func items(inPinboard pinboardID: Int64, limit: Int = 300) throws -> [ClipboardItem] {
        try dbQueue.read { db in
            try ClipboardItem
                .filter(Column("pinboardId") == pinboardID)
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Short link cache

    func saveShortLink(_ link: ShortLink) throws {
        try dbQueue.write { db in
            try link.save(db)
        }
    }

    func cachedShortLinks(limit: Int = 50) throws -> [ShortLink] {
        try dbQueue.read { db in
            try ShortLink
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func shortLink(withShortURL shortURL: String) throws -> ShortLink? {
        try dbQueue.read { db in
            try ShortLink.filter(Column("shortUrl") == shortURL).fetchOne(db)
        }
    }

    func deleteShortLink(id: String) throws {
        try dbQueue.write { db in
            _ = try ShortLink.deleteOne(db, key: id)
        }
    }

    func updateShortLinkClickCount(id: String, clickCount: Int) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE short_links SET clickCount = ? WHERE id = ?",
                arguments: [clickCount, id]
            )
        }
    }

    // MARK: - Rules

    @discardableResult
    func saveShortenRule(_ rule: ShortenRule) throws -> ShortenRule {
        var mutable = rule
        try dbQueue.write { db in
            if mutable.id == nil {
                try mutable.insert(db)
            } else {
                try mutable.update(db)
            }
        }
        return mutable
    }

    func shortenRules() throws -> [ShortenRule] {
        try dbQueue.read { db in
            try ShortenRule
                .order(Column("priority"), Column("createdAt"))
                .fetchAll(db)
        }
    }

    func enabledShortenRules() throws -> [ShortenRule] {
        try dbQueue.read { db in
            try ShortenRule
                .filter(Column("isEnabled") == true)
                .order(Column("priority"), Column("createdAt"))
                .fetchAll(db)
        }
    }

    func deleteShortenRule(id: Int64) throws {
        try dbQueue.write { db in
            _ = try ShortenRule.deleteOne(db, key: id)
        }
    }
}

// MARK: - FTS query sanitizing

enum FTSQuery {
    /// Turns free-form input into a safe FTS5 MATCH expression.
    /// Every token is quoted and prefix-matched so `goo` finds `google.com`.
    static func make(from raw: String) -> String {
        let tokens = raw
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation || $0.isSymbol })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return "" }
        return tokens
            .map { token in
                let escaped = token.replacingOccurrences(of: "\"", with: "")
                return "\"\(escaped)\"*"
            }
            .joined(separator: " AND ")
    }
}

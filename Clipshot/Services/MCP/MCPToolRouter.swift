import Foundation

/// The six v1 MCP tools. Every read goes through `HistoryStore`; the only
/// writes are pinboard creation and pinboard membership.
struct MCPToolRouter {
    static let defaultPinboardColor = "#FF9F0A"

    let store: HistoryStore

    var tools: [MCPToolDefinition] {
        [
            MCPToolDefinition(
                name: "search_history",
                description: "Search clipboard history. Free text supports the same power-search tokens as the app: kind:, from:, date:, pinboard:, text:. A kind argument is applied as an additional filter and intersects with kind: in the query.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("Free text query; may embed kind:, from:, date:, pinboard: or text: tokens."),
                        ]),
                        "kind": .object([
                            "type": .string("string"),
                            "enum": .array(["text", "url", "rtf", "image", "file", "color"].map { .string($0) }),
                            "description": .string("Restrict results to one item kind."),
                        ]),
                        "limit": .object([
                            "type": .string("integer"),
                            "minimum": .number(1),
                            "maximum": .number(300),
                            "default": .number(50),
                        ]),
                    ]),
                    "required": .array([.string("query")]),
                ])
            ),
            MCPToolDefinition(
                name: "get_item",
                description: "Fetch one clipboard history item by id. Filesystem paths are never returned.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "id": .object([
                            "type": .string("integer"),
                            "description": .string("Item id from search_history."),
                        ]),
                    ]),
                    "required": .array([.string("id")]),
                ])
            ),
            MCPToolDefinition(
                name: "list_pinboards",
                description: "List pinboards with their item counts.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([:]),
                ])
            ),
            MCPToolDefinition(
                name: "get_pinboard_items",
                description: "List the items in a pinboard. The name match is case-insensitive and exact.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "name": .object([
                            "type": .string("string"),
                            "description": .string("Pinboard name."),
                        ]),
                    ]),
                    "required": .array([.string("name")]),
                ])
            ),
            MCPToolDefinition(
                name: "create_pinboard",
                description: "Create a pinboard.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "name": .object([
                            "type": .string("string"),
                            "description": .string("Pinboard name."),
                        ]),
                    ]),
                    "required": .array([.string("name")]),
                ])
            ),
            MCPToolDefinition(
                name: "add_item_to_pinboard",
                description: "Add an existing clipboard item to a pinboard. The pinboard may be a name or an id.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "item_id": .object([
                            "type": .string("integer"),
                            "description": .string("Item id from search_history."),
                        ]),
                        "pinboard": .object([
                            "type": .array([.string("string"), .string("integer")]),
                            "description": .string("Pinboard name or id."),
                        ]),
                    ]),
                    "required": .array([.string("item_id"), .string("pinboard")]),
                ])
            ),
        ]
    }

    func call(_ name: String, arguments: [String: JSONValue]) -> MCPToolOutcome {
        switch name {
        case "search_history":
            return searchHistory(arguments)
        case "get_item":
            return getItem(arguments)
        case "list_pinboards":
            return listPinboards()
        case "get_pinboard_items":
            return getPinboardItems(arguments)
        case "create_pinboard":
            return createPinboard(arguments)
        case "add_item_to_pinboard":
            return addItemToPinboard(arguments)
        default:
            return .invalidParams("Unknown tool: \(name)")
        }
    }

    // MARK: - Tools

    private func searchHistory(_ arguments: [String: JSONValue]) -> MCPToolOutcome {
        guard let query = arguments["query"]?.stringValue else {
            return .invalidParams("Invalid params: query must be a string")
        }

        var kindArgument: ClipboardItemKind?
        if let rawKind = arguments["kind"], rawKind != .null {
            guard let value = rawKind.stringValue else {
                return .invalidParams("Invalid params: kind must be a string")
            }
            guard let kind = ClipboardItemKind(rawValue: value.lowercased()) else {
                return .invalidParams(
                    "Invalid params: kind must be one of text, url, rtf, image, file, color"
                )
            }
            kindArgument = kind
        }

        var limit = 50
        if let rawLimit = arguments["limit"], rawLimit != .null {
            guard let value = rawLimit.int64Value else {
                return .invalidParams("Invalid params: limit must be an integer")
            }
            limit = Int(min(max(value, 1), 300))
        }

        let parsed = SearchQueryParser.parse(query)
        var freeText = parsed.freeText
        var pinboardID: Int64?

        do {
            let boards = try store.pinboards()
            if let name = parsed.pinboardName {
                if let board = boards.first(where: {
                    $0.name.compare(name, options: [.caseInsensitive]) == .orderedSame
                }) {
                    pinboardID = board.id
                } else {
                    freeText = [freeText, name]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                }
            }

            let kindConflict = kindArgument != nil
                && parsed.kind != nil
                && kindArgument != parsed.kind
            let effectiveKind = kindArgument ?? parsed.kind
            let interval = parsed.dateFilter?.interval(now: Date())

            let results: [ClipboardItem]
            if kindConflict {
                results = []
            } else {
                results = try store.search(
                    freeText,
                    kind: effectiveKind,
                    sourceAppOrBundleId: parsed.fromApp,
                    createdAtFrom: interval?.start,
                    createdAtTo: interval?.end,
                    phrase: parsed.phrase,
                    limit: limit
                )
            }

            let filtered = pinboardID == nil
                ? results
                : results.filter { $0.pinboardId == pinboardID }
            return .success(.object([
                "items": .array(filtered.map { itemJSON($0, pinboardNames: names(for: boards)) }),
                "count": .number(Double(filtered.count)),
            ]))
        } catch {
            return .failure("Search failed: \(error.localizedDescription)")
        }
    }

    private func getItem(_ arguments: [String: JSONValue]) -> MCPToolOutcome {
        guard let rawID = arguments["id"], let id = rawID.int64Value else {
            return .invalidParams("Invalid params: id must be an integer")
        }

        do {
            guard let item = try store.item(id: id) else {
                return .failure("Item not found: \(id)")
            }
            return .success(itemJSON(item, pinboardNames: names(for: try store.pinboards())))
        } catch {
            return .failure("Could not load item \(id): \(error.localizedDescription)")
        }
    }

    private func listPinboards() -> MCPToolOutcome {
        do {
            let boards = try store.pinboards()
            let payload = try boards.map { board -> JSONValue in
                guard let id = board.id else { return .null }
                let count = try store.items(inPinboard: id, limit: Int.max).count
                return .object([
                    "id": .number(Double(id)),
                    "name": .string(board.name),
                    "colorHex": .string(board.colorHex),
                    "itemCount": .number(Double(count)),
                ])
            }
            return .success(.object([
                "pinboards": .array(payload.filter { $0 != .null }),
                "count": .number(Double(payload.filter { $0 != .null }.count)),
            ]))
        } catch {
            return .failure("Could not list pinboards: \(error.localizedDescription)")
        }
    }

    private func getPinboardItems(_ arguments: [String: JSONValue]) -> MCPToolOutcome {
        guard let name = arguments["name"]?.stringValue else {
            return .invalidParams("Invalid params: name must be a string")
        }

        do {
            let boards = try store.pinboards()
            guard let board = boards.first(where: {
                $0.name.compare(name, options: [.caseInsensitive]) == .orderedSame
            }), let boardID = board.id else {
                return .failure("Pinboard not found: \(name)")
            }
            let items = try store.items(inPinboard: boardID, limit: 300)
            return .success(.object([
                "pinboard": .object([
                    "id": .number(Double(boardID)),
                    "name": .string(board.name),
                    "colorHex": .string(board.colorHex),
                ]),
                "items": .array(items.map { itemJSON($0, pinboardNames: names(for: boards)) }),
                "count": .number(Double(items.count)),
            ]))
        } catch {
            return .failure("Could not load pinboard \(name): \(error.localizedDescription)")
        }
    }

    private func createPinboard(_ arguments: [String: JSONValue]) -> MCPToolOutcome {
        guard let rawName = arguments["name"]?.stringValue else {
            return .invalidParams("Invalid params: name must be a string")
        }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return .failure("Pinboard name is required")
        }

        do {
            let board = try store.createPinboard(
                name: name,
                colorHex: Self.defaultPinboardColor
            )
            return .success(.object([
                "id": .number(Double(board.id ?? 0)),
                "name": .string(board.name),
                "colorHex": .string(board.colorHex),
                "itemCount": .number(0),
            ]))
        } catch {
            return .failure("Could not create pinboard: \(error.localizedDescription)")
        }
    }

    private func addItemToPinboard(_ arguments: [String: JSONValue]) -> MCPToolOutcome {
        guard let rawItemID = arguments["item_id"], let itemID = rawItemID.int64Value else {
            return .invalidParams("Invalid params: item_id must be an integer")
        }
        guard let rawPinboard = arguments["pinboard"], rawPinboard != .null else {
            return .invalidParams("Invalid params: pinboard is required")
        }

        do {
            guard try store.item(id: itemID) != nil else {
                return .failure("Item not found: \(itemID)")
            }

            let boards = try store.pinboards()
            let board: Pinboard?
            if case .number = rawPinboard, let boardID = rawPinboard.int64Value {
                board = boards.first { $0.id == boardID }
            } else if let value = rawPinboard.stringValue {
                board = boards.first(where: {
                    $0.name.compare(value, options: [.caseInsensitive]) == .orderedSame
                }) ?? boards.first { $0.id == Int64(value) }
            } else {
                return .invalidParams("Invalid params: pinboard must be a name or id")
            }

            guard let board, let boardID = board.id else {
                return .failure("Pinboard not found: \(rawPinboard.stringValue ?? "")")
            }

            try store.addItem(itemID, toPinboard: boardID)
            return .success(.object([
                "item_id": .number(Double(itemID)),
                "pinboard": .object([
                    "id": .number(Double(boardID)),
                    "name": .string(board.name),
                ]),
            ]))
        } catch {
            return .failure("Could not add item to pinboard: \(error.localizedDescription)")
        }
    }

    // MARK: - Serialization

    private func names(for boards: [Pinboard]) -> [Int64: String] {
        Dictionary(uniqueKeysWithValues: boards.compactMap { board in
            board.id.map { ($0, board.name) }
        })
    }

    /// Deliberately omits `dataPath`: the server must not leak filesystem paths.
    private func itemJSON(_ item: ClipboardItem, pinboardNames: [Int64: String]) -> JSONValue {
        var fields: [String: JSONValue] = [
            "id": .number(Double(item.id ?? 0)),
            "kind": .string(item.kind.rawValue),
            "createdAt": .string(Self.iso8601.string(from: item.createdAt)),
            "isPinned": .bool(item.isPinned),
            "isSnippet": .bool(item.isSnippet),
        ]

        if let text = item.text { fields["text"] = .string(text) }
        if let title = item.title { fields["title"] = .string(title) }
        if let ocrText = item.ocrText { fields["ocrText"] = .string(ocrText) }
        if let sourceApp = item.sourceApp { fields["sourceApp"] = .string(sourceApp) }
        if let bundleId = item.bundleId { fields["bundleId"] = .string(bundleId) }
        if let shortUrl = item.shortUrl { fields["shortUrl"] = .string(shortUrl) }
        if let pinboardID = item.pinboardId {
            fields["pinboardId"] = .number(Double(pinboardID))
            if let name = pinboardNames[pinboardID] {
                fields["pinboard"] = .string(name)
            }
        }

        return .object(fields)
    }

    private static let iso8601 = ISO8601DateFormatter()
}

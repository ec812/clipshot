import CoreFoundation
import Foundation

/// A JSON value with value semantics, used so the MCP protocol layer can be
/// exercised without `Any` casts or networking.
enum JSONValue: Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(any: Any) {
        switch any {
        case let dictionary as [String: Any]:
            self = .object(dictionary.mapValues(JSONValue.init(any:)))
        case let array as [Any]:
            self = .array(array.map(JSONValue.init(any:)))
        case let string as String:
            self = .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case is NSNull:
            self = .null
        default:
            self = .null
        }
    }

    var anyObject: Any {
        switch self {
        case .object(let dictionary):
            return dictionary.mapValues { $0.anyObject }
        case .array(let array):
            return array.map { $0.anyObject }
        case .string(let string):
            return string
        case .number(let number):
            return NSNumber(value: number)
        case .bool(let bool):
            return bool
        case .null:
            return NSNull()
        }
    }

    func data(sortedKeys: Bool = true) -> Data {
        var options: JSONSerialization.WritingOptions = [.fragmentsAllowed]
        if sortedKeys {
            options.insert(.sortedKeys)
        }
        return (try? JSONSerialization.data(withJSONObject: anyObject, options: options))
            ?? Data("null".utf8)
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var int64Value: Int64? {
        switch self {
        case .number(let value):
            guard value.rounded() == value,
                  value >= Double(Int64.min),
                  value <= Double(Int64.max)
            else { return nil }
            return Int64(value)
        case .string(let value):
            return Int64(value)
        default:
            return nil
        }
    }

    subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }
}

struct MCPToolDefinition: Equatable {
    let name: String
    let description: String
    let inputSchema: JSONValue

    var jsonValue: JSONValue {
        .object([
            "name": .string(name),
            "description": .string(description),
            "inputSchema": inputSchema,
        ])
    }
}

enum MCPToolOutcome: Equatable {
    /// The tool ran and produced a JSON payload for the text content block.
    case success(JSONValue)
    /// The tool ran but reported a recoverable, user-facing failure.
    case failure(String)
    /// The request was malformed (JSON-RPC -32602).
    case invalidParams(String)
}

struct MCPHTTPResult: Equatable {
    let statusCode: Int
    let body: Data?
}

/// Pure JSON-RPC 2.0 + MCP routing. No sockets, no database, no clock reads.
///
/// Batch arrays are rejected with `-32600` (Invalid Request): MCP removed
/// batching in protocol version 2025-03-26 and v1 does not need it.
struct MCPProtocol {
    static let serverName = "clipshot"
    static let defaultProtocolVersion = "2025-03-26"
    static let supportedProtocolVersions: Set<String> = [
        "2024-11-05",
        "2025-03-26",
        "2025-06-18",
    ]

    let serverVersion: String
    let tools: [MCPToolDefinition]
    let toolHandler: (String, [String: JSONValue]) -> MCPToolOutcome

    func handle(body: Data) -> MCPHTTPResult {
        guard !body.isEmpty else {
            return error(id: .null, code: -32700, message: "Parse error: empty request body")
        }
        guard let raw = try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed]) else {
            return error(id: .null, code: -32700, message: "Parse error")
        }
        if raw is [Any] {
            return error(
                id: .null,
                code: -32600,
                message: "Invalid Request: batch requests are not supported"
            )
        }
        guard let object = raw as? [String: Any] else {
            return error(id: .null, code: -32600, message: "Invalid Request")
        }
        return handle(message: JSONValue(any: object))
    }

    // MARK: - Dispatch

    private func handle(message: JSONValue) -> MCPHTTPResult {
        guard case .object(let fields) = message else {
            return error(id: .null, code: -32600, message: "Invalid Request")
        }
        guard fields["jsonrpc"]?.stringValue == "2.0" else {
            return error(id: .null, code: -32600, message: "Invalid Request: jsonrpc must be \"2.0\"")
        }
        guard let method = fields["method"]?.stringValue else {
            return error(id: .null, code: -32600, message: "Invalid Request: missing method")
        }

        // No `id` means a notification: JSON-RPC forbids sending a response.
        guard let id = fields["id"] else {
            return MCPHTTPResult(statusCode: 202, body: nil)
        }
        switch id {
        case .string, .number, .null:
            break
        default:
            return error(id: .null, code: -32600, message: "Invalid Request: invalid id")
        }

        let params: JSONValue?
        if let rawParams = fields["params"], rawParams != .null {
            guard rawParams.objectValue != nil else {
                return error(id: id, code: -32602, message: "Invalid params: params must be an object")
            }
            params = rawParams
        } else {
            params = nil
        }

        switch method {
        case "initialize":
            return initialize(id: id, params: params)
        case "notifications/initialized":
            return success(id: id, result: .object([:]))
        case "ping":
            return success(id: id, result: .object([:]))
        case "tools/list":
            return success(id: id, result: .object([
                "tools": .array(tools.map(\.jsonValue)),
            ]))
        case "tools/call":
            return call(id: id, params: params)
        default:
            return error(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private func initialize(id: JSONValue, params: JSONValue?) -> MCPHTTPResult {
        var requested: String?
        if let rawVersion = params?["protocolVersion"], rawVersion != .null {
            guard let version = rawVersion.stringValue else {
                return error(
                    id: id,
                    code: -32602,
                    message: "Invalid params: protocolVersion must be a string"
                )
            }
            requested = version
        }

        let version = requested.flatMap {
            Self.supportedProtocolVersions.contains($0) ? $0 : nil
        } ?? Self.defaultProtocolVersion

        return success(id: id, result: .object([
            "protocolVersion": .string(version),
            "capabilities": .object([
                "tools": .object(["listChanged": .bool(false)]),
            ]),
            "serverInfo": .object([
                "name": .string(Self.serverName),
                "version": .string(serverVersion),
            ]),
        ]))
    }

    private func call(id: JSONValue, params: JSONValue?) -> MCPHTTPResult {
        guard let params else {
            return error(id: id, code: -32602, message: "Invalid params: missing params")
        }
        guard let name = params["name"]?.stringValue else {
            return error(id: id, code: -32602, message: "Invalid params: name must be a string")
        }

        let arguments: [String: JSONValue]
        if let rawArguments = params["arguments"], rawArguments != .null {
            guard let object = rawArguments.objectValue else {
                return error(
                    id: id,
                    code: -32602,
                    message: "Invalid params: arguments must be an object"
                )
            }
            arguments = object
        } else {
            arguments = [:]
        }

        guard tools.contains(where: { $0.name == name }) else {
            return error(id: id, code: -32602, message: "Unknown tool: \(name)")
        }

        switch toolHandler(name, arguments) {
        case .success(let payload):
            let text = String(data: payload.data(), encoding: .utf8) ?? "null"
            return success(id: id, result: toolResult(text: text, isError: false))
        case .failure(let message):
            return success(id: id, result: toolResult(text: message, isError: true))
        case .invalidParams(let message):
            return error(id: id, code: -32602, message: message)
        }
    }

    // MARK: - Envelope

    private func toolResult(text: String, isError: Bool) -> JSONValue {
        .object([
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(text),
                ]),
            ]),
            "isError": .bool(isError),
        ])
    }

    private func success(id: JSONValue, result: JSONValue) -> MCPHTTPResult {
        MCPHTTPResult(statusCode: 200, body: JSONValue.object([
            "jsonrpc": .string("2.0"),
            "id": id,
            "result": result,
        ]).data())
    }

    private func error(id: JSONValue, code: Int, message: String) -> MCPHTTPResult {
        MCPHTTPResult(statusCode: 200, body: JSONValue.object([
            "jsonrpc": .string("2.0"),
            "id": id,
            "error": .object([
                "code": .number(Double(code)),
                "message": .string(message),
            ]),
        ]).data())
    }
}

import XCTest
@testable import Clipshot

final class MCPServerIntegrationTests: XCTestCase {
    private var store: HistoryStore!
    private var server: MCPServer!
    private var session: URLSession!
    private var port: UInt16!
    private let token = "integration-secret-token"

    override func setUp() async throws {
        try await super.setUp()

        store = try HistoryStore.inMemory()
        let router = MCPToolRouter(store: store)
        let handler = MCPProtocol(
            serverVersion: "test-1.0",
            tools: router.tools,
            toolHandler: { name, arguments in
                router.call(name, arguments: arguments)
            }
        )
        server = MCPServer(protocolHandler: handler)

        port = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            server.start(token: token, preferredPort: nil) { result in
                continuation.resume(with: result)
            }
        }
        XCTAssertNotEqual(port, 0)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        session = URLSession(configuration: configuration)
    }

    override func tearDown() async throws {
        session?.invalidateAndCancel()
        server?.stop()
        session = nil
        server = nil
        store = nil
        port = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func request(
        _ method: String,
        path: String = "/mcp",
        body: String? = nil,
        token: String? = nil
    ) async throws -> (status: Int, body: Data) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port!)\(path)")!)
        request.httpMethod = method
        if let body {
            request.httpBody = Data(body.utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        return (http.statusCode, data)
    }

    private func json(_ data: Data) throws -> JSONValue {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return JSONValue(any: object)
    }

    private func rpc(_ id: Int, _ method: String, params: JSONValue? = nil) -> String {
        var fields: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
        if let params {
            fields["params"] = params.anyObject
        }
        let data = try! JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private func toolCall(
        _ id: Int,
        _ name: String,
        _ arguments: [String: JSONValue] = [:]
    ) -> String {
        rpc(id, "tools/call", params: .object([
            "name": .string(name),
            "arguments": .object(arguments),
        ]))
    }

    private func toolPayload(_ data: Data) throws -> (payload: JSONValue, isError: Bool) {
        let envelope = try json(data)
        let text = try XCTUnwrap(
            envelope["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue
        )
        let isError = envelope["result"]?["isError"]?.boolValue ?? false
        return (try json(Data(text.utf8)), isError)
    }

    // MARK: - Authentication

    func testRequestsWithoutOrWithWrongTokenAreUnauthorized() async throws {
        let initialize = rpc(1, "initialize", params: .object([:]))

        let missing = try await request("POST", body: initialize)
        XCTAssertEqual(missing.status, 401)

        let wrong = try await request("POST", body: initialize, token: "wrong-token")
        XCTAssertEqual(wrong.status, 401)

        // The token check runs before JSON parsing: malformed bodies still get 401.
        let malformed = try await request("POST", body: "{not json at all")
        XCTAssertEqual(malformed.status, 401)
    }

    // MARK: - Happy paths

    func testAllSixToolsOverWireReturnRealStoreData() async throws {
        let inserted = try store.insert(
            kind: .text,
            text: "wire level clipboard text",
            sourceApp: "Notes",
            bundleId: "com.apple.Notes",
            hash: "wire-item"
        ).item
        let itemID = try XCTUnwrap(inserted.id)

        let initialize = try await request(
            "POST",
            body: rpc(1, "initialize", params: .object([
                "protocolVersion": .string("2025-03-26"),
                "capabilities": .object([:]),
            ])),
            token: token
        )
        XCTAssertEqual(initialize.status, 200)
        let initialized = try json(initialize.body)
        XCTAssertEqual(initialized["result"]?["protocolVersion"]?.stringValue, "2025-03-26")
        XCTAssertEqual(initialized["result"]?["capabilities"]?["tools"]?["listChanged"]?.boolValue, false)
        XCTAssertEqual(initialized["result"]?["serverInfo"]?["name"]?.stringValue, "clipshot")
        XCTAssertEqual(initialized["result"]?["serverInfo"]?["version"]?.stringValue, "test-1.0")

        let list = try await request("POST", body: rpc(2, "tools/list"), token: token)
        XCTAssertEqual(list.status, 200)
        let names = try json(list.body)["result"]?["tools"]?.arrayValue?
            .compactMap { $0["name"]?.stringValue }
        XCTAssertEqual(names, [
            "search_history",
            "get_item",
            "list_pinboards",
            "get_pinboard_items",
            "create_pinboard",
            "add_item_to_pinboard",
        ])

        let search = try await request(
            "POST",
            body: toolCall(3, "search_history", ["query": .string("wire level")]),
            token: token
        )
        XCTAssertEqual(search.status, 200)
        let searchPayload = try toolPayload(search.body)
        XCTAssertFalse(searchPayload.isError)
        XCTAssertEqual(searchPayload.payload["count"]?.int64Value, 1)
        let firstItem = try XCTUnwrap(searchPayload.payload["items"]?.arrayValue?.first)
        XCTAssertEqual(firstItem["id"]?.int64Value, itemID)
        XCTAssertEqual(firstItem["text"]?.stringValue, "wire level clipboard text")
        XCTAssertNil(firstItem["dataPath"])

        let get = try await request(
            "POST",
            body: toolCall(4, "get_item", ["id": .number(Double(itemID))]),
            token: token
        )
        let fetched = try toolPayload(get.body)
        XCTAssertFalse(fetched.isError)
        XCTAssertEqual(fetched.payload["id"]?.int64Value, itemID)
        XCTAssertEqual(fetched.payload["sourceApp"]?.stringValue, "Notes")
        XCTAssertNil(fetched.payload["dataPath"])

        let emptyBoards = try await request(
            "POST",
            body: toolCall(5, "list_pinboards"),
            token: token
        )
        let emptyPayload = try toolPayload(emptyBoards.body)
        XCTAssertEqual(emptyPayload.payload["count"]?.int64Value, 0)

        let created = try await request(
            "POST",
            body: toolCall(6, "create_pinboard", ["name": .string("Wire Board")]),
            token: token
        )
        let createdPayload = try toolPayload(created.body)
        XCTAssertFalse(createdPayload.isError)
        XCTAssertEqual(createdPayload.payload["name"]?.stringValue, "Wire Board")
        XCTAssertEqual(createdPayload.payload["colorHex"]?.stringValue, "#FF9F0A")

        let added = try await request(
            "POST",
            body: toolCall(7, "add_item_to_pinboard", [
                "item_id": .number(Double(itemID)),
                "pinboard": .string("wire board"),
            ]),
            token: token
        )
        let addedPayload = try toolPayload(added.body)
        XCTAssertFalse(addedPayload.isError)
        XCTAssertEqual(addedPayload.payload["pinboard"]?["name"]?.stringValue, "Wire Board")

        let members = try await request(
            "POST",
            body: toolCall(8, "get_pinboard_items", ["name": .string("WIRE BOARD")]),
            token: token
        )
        let membersPayload = try toolPayload(members.body)
        XCTAssertFalse(membersPayload.isError)
        XCTAssertEqual(membersPayload.payload["count"]?.int64Value, 1)
        XCTAssertEqual(
            membersPayload.payload["items"]?.arrayValue?.first?["id"]?.int64Value,
            itemID
        )
        XCTAssertEqual(
            membersPayload.payload["items"]?.arrayValue?.first?["pinboard"]?.stringValue,
            "Wire Board"
        )

        let counted = try await request(
            "POST",
            body: toolCall(9, "list_pinboards"),
            token: token
        )
        let countedPayload = try toolPayload(counted.body)
        XCTAssertEqual(
            countedPayload.payload["pinboards"]?.arrayValue?.first?["itemCount"]?.int64Value,
            1
        )
    }

    // MARK: - Transport semantics

    func testHTTPRoutingStatusCodes() async throws {
        let get = try await request("GET", token: token)
        XCTAssertEqual(get.status, 405)

        let delete = try await request("DELETE", token: token)
        XCTAssertEqual(delete.status, 405)

        let put = try await request("PUT", body: "{}", token: token)
        XCTAssertEqual(put.status, 405)

        let options = try await request("OPTIONS", token: token)
        XCTAssertEqual(options.status, 404)

        let unknown = try await request("POST", path: "/other", body: "{}", token: token)
        XCTAssertEqual(unknown.status, 404)
    }

    func testJSONRPCErrorsOverWire() async throws {
        let malformed = try await request("POST", body: "{oops", token: token)
        XCTAssertEqual(malformed.status, 200)
        XCTAssertEqual(try json(malformed.body)["error"]?["code"]?.int64Value, -32700)

        let unknownMethod = try await request(
            "POST",
            body: rpc(2, "resources/list"),
            token: token
        )
        XCTAssertEqual(try json(unknownMethod.body)["error"]?["code"]?.int64Value, -32601)

        let unknownTool = try await request(
            "POST",
            body: toolCall(3, "delete_everything"),
            token: token
        )
        XCTAssertEqual(try json(unknownTool.body)["error"]?["code"]?.int64Value, -32602)

        let batch = try await request(
            "POST",
            body: #"[{"jsonrpc":"2.0","id":1,"method":"ping"}]"#,
            token: token
        )
        XCTAssertEqual(try json(batch.body)["error"]?["code"]?.int64Value, -32600)
    }

    func testNotificationReturnsAcceptedWithEmptyBody() async throws {
        let notification = try await request(
            "POST",
            body: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            token: token
        )
        XCTAssertEqual(notification.status, 202)
        XCTAssertTrue(notification.body.isEmpty)
    }

    func testPingEchoesID() async throws {
        let ping = try await request("POST", body: rpc(77, "ping"), token: token)
        XCTAssertEqual(ping.status, 200)
        let payload = try json(ping.body)
        XCTAssertEqual(payload["id"]?.int64Value, 77)
        XCTAssertEqual(payload["result"]?.objectValue?.isEmpty, true)
    }
}

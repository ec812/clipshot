import XCTest
@testable import Clipshot

final class MCPProtocolTests: XCTestCase {
    private static let defaultTools = [
        MCPToolDefinition(
            name: "alpha",
            description: "Alpha tool",
            inputSchema: .object(["type": .string("object")])
        ),
        MCPToolDefinition(
            name: "beta",
            description: "Beta tool",
            inputSchema: .object(["type": .string("object")])
        ),
    ]

    private struct DecodedResponse {
        let status: Int
        let body: Data?
        let json: JSONValue?
    }

    private func makeProtocol(
        handler: @escaping (String, [String: JSONValue]) -> MCPToolOutcome = { _, _ in
            .success(.object(["ok": .bool(true)]))
        }
    ) -> MCPProtocol {
        MCPProtocol(serverVersion: "1.2.3", tools: Self.defaultTools, toolHandler: handler)
    }

    private func respond(_ body: String, using protocolHandler: MCPProtocol? = nil) -> DecodedResponse {
        let response = (protocolHandler ?? makeProtocol()).handle(body: Data(body.utf8))
        let json = response.body.flatMap { data -> JSONValue? in
            guard let object = try? JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed]
            ) else { return nil }
            return JSONValue(any: object)
        }
        return DecodedResponse(status: response.statusCode, body: response.body, json: json)
    }

    private func errorCode(_ response: DecodedResponse) -> Int64? {
        response.json?["error"]?["code"]?.int64Value
    }

    private func toolText(_ response: DecodedResponse) -> String? {
        response.json?["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue
    }

    // MARK: - initialize

    func testInitializeEchoesSupportedProtocolVersion() {
        let response = respond(
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}"#
        )

        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.json?["jsonrpc"]?.stringValue, "2.0")
        XCTAssertEqual(response.json?["id"]?.int64Value, 1)
        XCTAssertEqual(response.json?["result"]?["protocolVersion"]?.stringValue, "2025-03-26")
        XCTAssertEqual(response.json?["result"]?["capabilities"]?["tools"]?["listChanged"]?.boolValue, false)
        XCTAssertEqual(response.json?["result"]?["serverInfo"]?["name"]?.stringValue, "clipshot")
        XCTAssertEqual(response.json?["result"]?["serverInfo"]?["version"]?.stringValue, "1.2.3")
    }

    func testInitializeFallsBackForUnsupportedOrMissingVersion() {
        let unsupported = respond(
            #"{"jsonrpc":"2.0","id":"a","method":"initialize","params":{"protocolVersion":"1999-01-01"}}"#
        )
        XCTAssertEqual(
            unsupported.json?["result"]?["protocolVersion"]?.stringValue,
            MCPProtocol.defaultProtocolVersion
        )

        let missing = respond(#"{"jsonrpc":"2.0","id":"a","method":"initialize"}"#)
        XCTAssertEqual(
            missing.json?["result"]?["protocolVersion"]?.stringValue,
            MCPProtocol.defaultProtocolVersion
        )
    }

    // MARK: - Methods

    func testPingReturnsEmptyResult() {
        let response = respond(#"{"jsonrpc":"2.0","id":7,"method":"ping"}"#)

        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.json?["result"]?.objectValue?.isEmpty, true)
        XCTAssertEqual(response.json?["id"]?.int64Value, 7)
    }

    func testToolsListReturnsDefinitions() {
        let response = respond(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)

        XCTAssertEqual(response.status, 200)
        let tools = response.json?["result"]?["tools"]?.arrayValue
        XCTAssertEqual(tools?.count, 2)
        XCTAssertEqual(tools?.first?["name"]?.stringValue, "alpha")
        XCTAssertEqual(tools?.first?["inputSchema"]?["type"]?.stringValue, "object")
    }

    func testNotificationWithoutIDReturnsAcceptedAndEmptyBody() {
        let response = respond(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)

        XCTAssertEqual(response.status, 202)
        XCTAssertNil(response.body)
        XCTAssertNil(response.json)
    }

    func testUnknownNotificationWithoutIDReturnsAccepted() {
        let response = respond(#"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{}}"#)

        XCTAssertEqual(response.status, 202)
        XCTAssertNil(response.body)
    }

    // MARK: - tools/call

    func testToolCallSuccessReturnsJSONContent() throws {
        let response = respond(
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"alpha","arguments":{"value":5}}}"#
        )

        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.json?["result"]?["isError"]?.boolValue, false)
        let text = try XCTUnwrap(toolText(response))
        let payload = JSONValue(any: try JSONSerialization.jsonObject(
            with: Data(text.utf8),
            options: [.fragmentsAllowed]
        ))
        XCTAssertEqual(payload["ok"]?.boolValue, true)
    }

    func testToolCallForwardsArgumentsToHandler() {
        var received: [String: JSONValue] = [:]
        let protocolHandler = makeProtocol { _, arguments in
            received = arguments
            return .success(.object([:]))
        }
        _ = respond(
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"alpha","arguments":{"query":"hello","limit":5}}}"#,
            using: protocolHandler
        )

        XCTAssertEqual(received["query"]?.stringValue, "hello")
        XCTAssertEqual(received["limit"]?.int64Value, 5)
    }

    func testToolCallFailureReturnsIsErrorTrue() {
        let protocolHandler = makeProtocol { _, _ in .failure("Pinboard not found: Design") }
        let response = respond(
            #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"alpha"}}"#,
            using: protocolHandler
        )

        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.json?["result"]?["isError"]?.boolValue, true)
        XCTAssertEqual(toolText(response), "Pinboard not found: Design")
        XCTAssertNil(response.json?["error"])
    }

    func testToolCallInvalidParamsFromRouterBecomesJSONRPCError() {
        let protocolHandler = makeProtocol { _, _ in .invalidParams("limit must be an integer") }
        let response = respond(
            #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"alpha"}}"#,
            using: protocolHandler
        )

        XCTAssertEqual(errorCode(response), -32602)
        XCTAssertEqual(response.json?["error"]?["message"]?.stringValue, "limit must be an integer")
    }

    func testToolCallMissingArgumentsDefaultsToEmptyObject() {
        var received: [String: JSONValue]?
        let protocolHandler = makeProtocol { _, arguments in
            received = arguments
            return .success(.object([:]))
        }
        _ = respond(
            #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"alpha"}}"#,
            using: protocolHandler
        )

        XCTAssertEqual(received?.isEmpty, true)
    }

    // MARK: - Table-driven error responses

    func testJSONRPCErrorTable() {
        let cases: [(name: String, body: String, code: Int64?)] = [
            ("parse error", #"{"jsonrpc":"2.0","id":1,"method":"# , -32700),
            ("empty body", "", -32700),
            ("top-level string", #""hello""#, -32600),
            ("top-level number", "42", -32600),
            ("batch array", #"[{"jsonrpc":"2.0","id":1,"method":"ping"}]"#, -32600),
            ("missing jsonrpc", #"{"id":1,"method":"ping"}"#, -32600),
            ("wrong jsonrpc", #"{"jsonrpc":"1.0","id":1,"method":"ping"}"#, -32600),
            ("unquoted version", #"{"jsonrpc":2.0,"id":1,"method":"ping"}"#, -32600),
            ("missing method", #"{"jsonrpc":"2.0","id":1}"#, -32600),
            ("method wrong type", #"{"jsonrpc":"2.0","id":1,"method":5}"#, -32600),
            ("id wrong type", #"{"jsonrpc":"2.0","id":{},"method":"ping"}"#, -32600),
            ("unknown method", #"{"jsonrpc":"2.0","id":1,"method":"resources/list"}"#, -32601),
            ("params wrong type", #"{"jsonrpc":"2.0","id":1,"method":"ping","params":[]}"#, -32602),
            ("initialize params wrong type", #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":"x"}"#, -32602),
            ("initialize non-string version", #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":5}}"#, -32602),
            ("tools/call missing params", #"{"jsonrpc":"2.0","id":1,"method":"tools/call"}"#, -32602),
            ("tools/call params string", #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":"alpha"}"#, -32602),
            ("tools/call missing name", #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{}}"#, -32602),
            ("tools/call name wrong type", #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":9}}"#, -32602),
            ("tools/call arguments wrong type", #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"alpha","arguments":[]}}"#, -32602),
            ("unknown tool", #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"gamma"}}"#, -32602),
        ]

        for testCase in cases {
            let response = respond(testCase.body)
            XCTAssertEqual(
                errorCode(response),
                testCase.code,
                "\(testCase.name): expected \(testCase.code ?? -1), got \(String(describing: errorCode(response)))"
            )
            XCTAssertEqual(response.status, 200, testCase.name)
        }
    }

    func testErrorResponsesUseNullIDWhenIDIsUnavailable() {
        let parseError = respond("{bad json")
        XCTAssertTrue(parseError.json?["id"] == .null)
        XCTAssertEqual(parseError.json?["jsonrpc"]?.stringValue, "2.0")

        let invalidRequest = respond(#"{"jsonrpc":"2.0","method":5,"id":1}"#)
        XCTAssertTrue(invalidRequest.json?["id"] == .null)
    }

    func testResponseEchoesStringAndNumericIDs() {
        let stringID = respond(#"{"jsonrpc":"2.0","id":"request-1","method":"ping"}"#)
        XCTAssertEqual(stringID.json?["id"]?.stringValue, "request-1")

        let numericID = respond(#"{"jsonrpc":"2.0","id":42,"method":"ping"}"#)
        XCTAssertEqual(numericID.json?["id"]?.int64Value, 42)

        let nullID = respond(#"{"jsonrpc":"2.0","id":null,"method":"ping"}"#)
        XCTAssertTrue(nullID.json?["id"] == .null)
        XCTAssertNotNil(nullID.json?["result"])
    }
}

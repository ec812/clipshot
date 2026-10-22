import Foundation
import Network

/// Loopback-only HTTP transport for the MCP protocol layer.
///
/// The listener is bound to 127.0.0.1 (never 0.0.0.0), tries a stable default
/// port first so clients can be configured once, and falls back to an ephemeral
/// port when that port is taken. Every request must carry
/// `Authorization: Bearer <token>` before any JSON parsing happens.
final class MCPServer: @unchecked Sendable {
    static let defaultPort: UInt16 = 8890
    static let path = "/mcp"

    enum StartError: LocalizedError {
        case listenerFailed(String)

        var errorDescription: String? {
            switch self {
            case .listenerFailed(let message):
                return "MCP server could not start: \(message)"
            }
        }
    }

    struct HTTPRequest {
        let method: String
        let target: String
        let headers: [String: String]
        let body: Data
    }

    enum ParseResult {
        case incomplete
        case invalid
        case complete(HTTPRequest)
    }

    private static let headerTerminator = Data("\r\n\r\n".utf8)
    private static let maximumRequestBytes = 1_048_576

    private let queue = DispatchQueue(label: "com.ernest.clipshot.mcp")
    private let protocolHandler: MCPProtocol
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var token = ""
    private var startCompletion: ((Result<UInt16, Error>) -> Void)?
    private var attemptedPreferredPort = false
    private var isReady = false

    init(protocolHandler: MCPProtocol) {
        self.protocolHandler = protocolHandler
    }

    func start(
        token: String,
        preferredPort: UInt16? = MCPServer.defaultPort,
        completion: @escaping (Result<UInt16, Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.listener == nil else {
                let port = self.listener?.port?.rawValue
                completion(port.map { .success($0) } ?? .failure(StartError.listenerFailed("Already starting")))
                return
            }
            self.token = token
            self.startCompletion = completion
            self.attemptedPreferredPort = preferredPort != nil
            self.isReady = false
            self.startListener(port: preferredPort)
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.startCompletion = nil
            self.isReady = false
            self.listener?.stateUpdateHandler = nil
            self.listener?.newConnectionHandler = nil
            self.listener?.cancel()
            self.listener = nil
            for connection in self.connections.values {
                connection.cancel()
            }
            self.connections.removeAll()
        }
    }

    // MARK: - Listener lifecycle

    private func startListener(port: UInt16?) {
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(
                host: NWEndpoint.Host("127.0.0.1"),
                port: port.flatMap(NWEndpoint.Port.init(rawValue:)) ?? .any
            )
            let listener = try NWListener(using: parameters)
            self.listener = listener

            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self, let listener, self.listener === listener else { return }
                switch state {
                case .ready:
                    self.isReady = true
                    self.finish(.success(listener.port?.rawValue ?? 0))
                case .waiting(let error):
                    if !self.isReady { self.handleListenFailure(error) }
                case .failed(let error):
                    if !self.isReady { self.handleListenFailure(error) }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        } catch {
            handleListenFailure(error)
        }
    }

    private func handleListenFailure(_ error: Error) {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil

        if attemptedPreferredPort {
            attemptedPreferredPort = false
            startListener(port: nil)
            return
        }
        finish(.failure(StartError.listenerFailed(error.localizedDescription)))
    }

    private func finish(_ result: Result<UInt16, Error>) {
        guard let completion = startCompletion else { return }
        startCompletion = nil
        DispatchQueue.main.async {
            completion(result)
        }
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        connections[ObjectIdentifier(connection)] = connection
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            var buffer = buffer
            if let data {
                buffer.append(data)
            }
            if buffer.count > Self.maximumRequestBytes {
                self.send(.init(statusCode: 413, body: Self.jsonBody(["error": "request too large"])), to: connection)
                return
            }

            switch Self.parseRequest(buffer) {
            case .complete(let request):
                self.handle(request, on: connection)
            case .invalid:
                self.send(.init(statusCode: 400, body: Self.jsonBody(["error": "bad request"])), to: connection)
            case .incomplete:
                if isComplete || error != nil {
                    self.send(.init(statusCode: 400, body: Self.jsonBody(["error": "bad request"])), to: connection)
                } else {
                    self.receive(on: connection, buffer: buffer)
                }
            }
        }
    }

    private func handle(_ request: HTTPRequest, on connection: NWConnection) {
        let path = request.target
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? request.target

        guard path == Self.path else {
            send(.init(statusCode: 404, body: Self.jsonBody(["error": "not found"])), to: connection)
            return
        }
        if request.method == "OPTIONS" {
            send(.init(statusCode: 404, body: Self.jsonBody(["error": "not found"])), to: connection)
            return
        }
        guard request.method == "POST" else {
            send(.init(statusCode: 405, body: Self.jsonBody(["error": "method not allowed"])), to: connection)
            return
        }
        guard isAuthorized(request) else {
            send(.init(statusCode: 401, body: Self.jsonBody(["error": "unauthorized"])), to: connection)
            return
        }

        send(protocolHandler.handle(body: request.body), to: connection)
    }

    private func isAuthorized(_ request: HTTPRequest) -> Bool {
        guard let header = request.headers["authorization"] else { return false }
        guard header.count >= 7 else { return false }
        let scheme = header.prefix(7)
        guard scheme.lowercased() == "bearer " else { return false }
        return Self.constantTimeEquals(String(header.dropFirst(7)), token)
    }

    private func send(_ response: MCPHTTPResult, to connection: NWConnection) {
        let body = response.body ?? Data()
        var head = "HTTP/1.1 \(response.statusCode) \(Self.reason(for: response.statusCode))\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n"
        head += "\r\n"

        var payload = Data(head.utf8)
        payload.append(body)

        connection.send(content: payload, completion: .contentProcessed { [weak self] _ in
            guard let self else {
                connection.cancel()
                return
            }
            self.connections.removeValue(forKey: ObjectIdentifier(connection))
            connection.cancel()
        })
    }

    // MARK: - HTTP parsing

    static func parseRequest(_ data: Data) -> ParseResult {
        guard let headerRange = data.range(of: headerTerminator) else {
            return data.count > 65_536 ? .invalid : .incomplete
        }
        guard let headerText = String(data: Data(data[..<headerRange.lowerBound]), encoding: .utf8) else {
            return .invalid
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return .invalid }
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1.") else { return .invalid }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return .invalid }
            if let existing = headers[name] {
                headers[name] = existing + ", " + value
            } else {
                headers[name] = value
            }
        }

        guard headers["transfer-encoding"] == nil else { return .invalid }

        let contentLength: Int
        if let rawLength = headers["content-length"] {
            guard let parsed = Int(rawLength), parsed >= 0, parsed <= maximumRequestBytes else {
                return .invalid
            }
            contentLength = parsed
        } else {
            contentLength = 0
        }

        let bodyStart = headerRange.upperBound
        guard data.count - bodyStart >= contentLength else { return .incomplete }
        let body = Data(data[bodyStart..<(bodyStart + contentLength)])

        return .complete(HTTPRequest(
            method: parts[0].uppercased(),
            target: parts[1],
            headers: headers,
            body: body
        ))
    }

    // MARK: - Helpers

    private static func jsonBody(_ fields: [String: String]) -> Data {
        JSONValue.object(fields.mapValues { .string($0) }).data()
    }

    private static func constantTimeEquals(_ left: String, _ right: String) -> Bool {
        let leftBytes = Array(left.utf8)
        let rightBytes = Array(right.utf8)
        guard leftBytes.count == rightBytes.count else { return false }
        var difference: UInt8 = 0
        for index in leftBytes.indices {
            difference |= leftBytes[index] ^ rightBytes[index]
        }
        return difference == 0
    }

    private static func reason(for statusCode: Int) -> String {
        switch statusCode {
        case 200: return "OK"
        case 202: return "Accepted"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Payload Too Large"
        default: return "OK"
        }
    }
}

import Combine
import Foundation
@preconcurrency import Network

@MainActor
final class LocalControlServer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var statusLine = "Local control endpoint not started"
    @Published private(set) var endpointURL = URL(string: "http://127.0.0.1:17391")!
    @Published private(set) var tokenPreview = "No token"

    private weak var store: WorkspaceStore?
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "AgentSwarmManagement.LocalControlServer")
    private var bearerToken = ""

    func attach(store: WorkspaceStore, token: String, port: UInt16) {
        self.store = store
        self.bearerToken = token
        self.tokenPreview = Self.preview(token)
        self.endpointURL = URL(string: "http://127.0.0.1:\(port)")!
        startIfNeeded(port: port)
    }

    func startIfNeeded(port: UInt16) {
        guard !isRunning else { return }

        do {
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                statusLine = "Invalid local control port"
                return
            }

            let listener = try NWListener(using: .tcp, on: nwPort)
            listener.parameters.allowLocalEndpointReuse = true
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.accept(connection)
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.updateState(state)
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            isRunning = false
            statusLine = "Could not start local control endpoint: \(error.localizedDescription)"
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        statusLine = "Local control endpoint stopped"
    }

    func endpointConfiguration() -> [String: String] {
        [
            "url": "\(endpointURL.absoluteString)/v1/agent-events",
            "authorization": "Bearer \(bearerToken)",
            "status": "\(endpointURL.absoluteString)/v1/status"
        ]
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func updateState(_ state: NWListener.State) {
        switch state {
        case .ready:
            isRunning = true
            statusLine = "Local endpoint ready: \(endpointURL.absoluteString)"
        case .failed(let error):
            isRunning = false
            statusLine = "Local endpoint failed: \(error.localizedDescription)"
        case .cancelled:
            isRunning = false
            statusLine = "Local endpoint stopped"
        default:
            break
        }
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }

            if let error {
                Task { @MainActor in
                    self.statusLine = "Local endpoint read failed: \(error.localizedDescription)"
                }
                connection.cancel()
                return
            }

            if let request = HTTPRequest(data: nextBuffer) {
                Task { @MainActor in
                    let response = self.handle(request)
                    self.send(response, on: connection)
                }
                return
            }

            if isComplete {
                Task { @MainActor in
                    self.send(.badRequest("Incomplete HTTP request"), on: connection)
                }
                return
            }

            Task { @MainActor in
                self.receive(on: connection, buffer: nextBuffer)
            }
        }
    }

    private func handle(_ request: HTTPRequest) -> HTTPResponse {
        if request.method == "GET", request.path == "/health" {
            return .json(["ok": true, "service": "AgentSwarmManagement"])
        }

        guard isAuthorized(request) else {
            return .unauthorized()
        }

        switch (request.method, request.path) {
        case ("GET", "/v1/status"):
            return statusResponse()
        case ("POST", "/v1/agent-events"):
            return recordAgentEvent(request)
        default:
            return .notFound()
        }
    }

    private func statusResponse() -> HTTPResponse {
        guard let store else {
            return .json(["ok": false, "error": "store not attached"], status: 503)
        }

        return .json([
            "ok": true,
            "endpoint": endpointURL.absoluteString,
            "activeProjects": store.activeProjectCount,
            "runningAgents": store.runningAgentCount,
            "openFollowUps": store.openFollowUpCount,
            "blockedTasks": store.blockedTaskCount,
            "pendingNotionOperations": store.pendingOperationCount
        ])
    }

    private func recordAgentEvent(_ request: HTTPRequest) -> HTTPResponse {
        guard let store else {
            return .json(["ok": false, "error": "store not attached"], status: 503)
        }

        do {
            let event = try JSONDecoder().decode(AgentEventRequest.self, from: request.body)
            guard !event.operationId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .badRequest("operationId is required")
            }
            guard !event.projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .badRequest("projectName is required")
            }

            if store.hasCompletedOperation(event.operationId) {
                return .json(["ok": true, "deduped": true])
            }

            store.recordMeaningfulAgentEvent(event)
            statusLine = "Last hook update: \(event.projectName)"
            return .json(["ok": true, "operationId": event.operationId])
        } catch {
            return .badRequest(error.localizedDescription)
        }
    }

    private func isAuthorized(_ request: HTTPRequest) -> Bool {
        let header = request.headers["authorization"] ?? ""
        return header == "Bearer \(bearerToken)"
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func preview(_ token: String) -> String {
        guard token.count > 10 else { return "Saved" }
        return "\(token.prefix(6))...\(token.suffix(4))"
    }
}

private struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data

    init?(data: Data) {
        let crlfSeparator = Data("\r\n\r\n".utf8)
        let lfSeparator = Data("\n\n".utf8)
        let separatorRange: Range<Data.Index>
        let separatorLength: Int

        if let range = data.range(of: crlfSeparator) {
            separatorRange = range
            separatorLength = crlfSeparator.count
        } else if let range = data.range(of: lfSeparator) {
            separatorRange = range
            separatorLength = lfSeparator.count
        } else {
            return nil
        }

        let headerData = data[..<separatorRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return nil
        }

        let lines = headerText.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        guard let requestLine = lines.first else { return nil }
        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            headers[parts[0].lowercased()] = parts[1].trimmingCharacters(in: .whitespaces)
        }

        let bodyStart = separatorRange.lowerBound + separatorLength
        let body = data[bodyStart...]
        let expectedLength = headers["content-length"].flatMap(Int.init) ?? 0
        guard body.count >= expectedLength else {
            return nil
        }

        self.method = requestParts[0]
        self.path = URLComponents(string: requestParts[1])?.path ?? requestParts[1]
        self.headers = headers
        self.body = Data(body.prefix(expectedLength))
    }
}

private struct HTTPResponse {
    var status: Int
    var reason: String
    var body: Data
    var contentType: String

    var data: Data {
        var response = Data()
        response.append("HTTP/1.1 \(status) \(reason)\r\n".data(using: .utf8)!)
        response.append("Content-Type: \(contentType)\r\n".data(using: .utf8)!)
        response.append("Content-Length: \(body.count)\r\n".data(using: .utf8)!)
        response.append("Connection: close\r\n\r\n".data(using: .utf8)!)
        response.append(body)
        return response
    }

    static func json(_ object: [String: Any], status: Int = 200) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]))
            ?? Data("{}".utf8)
        return HTTPResponse(status: status, reason: reasonPhrase(for: status), body: data, contentType: "application/json")
    }

    static func badRequest(_ message: String) -> HTTPResponse {
        json(["ok": false, "error": message], status: 400)
    }

    static func unauthorized() -> HTTPResponse {
        json(["ok": false, "error": "Authorization: Bearer token is required"], status: 401)
    }

    static func notFound() -> HTTPResponse {
        json(["ok": false, "error": "Not found"], status: 404)
    }

    private static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 503: "Service Unavailable"
        default: "OK"
        }
    }
}

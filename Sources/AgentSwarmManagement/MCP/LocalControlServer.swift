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
        // The app attaches once with an ephemeral launch token and again after
        // loading the durable token from disk. The listener may exist before
        // Network.framework has delivered its .ready state, so guard on the
        // listener itself instead of the published readiness flag.
        guard listener == nil else { return }

        do {
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                statusLine = "Invalid local control port"
                AppLogger.error("endpoint.invalid_port", details: ["port": "\(port)"])
                return
            }

            let listener = try NWListener(using: .tcp, on: nwPort)
            listener.parameters.allowLocalEndpointReuse = true
            let queue = queue
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection, queue: queue)
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.updateState(state)
                }
            }
            listener.start(queue: queue)
            self.listener = listener
            isRunning = true
            statusLine = "Local endpoint starting: \(endpointURL.absoluteString)"
            AppLogger.info("endpoint.starting", details: ["url": endpointURL.absoluteString])
        } catch {
            isRunning = false
            statusLine = "Could not start local control endpoint: \(error.localizedDescription)"
            AppLogger.error("endpoint.start_failed", error: error, details: ["url": endpointURL.absoluteString])
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        statusLine = "Local control endpoint stopped"
        AppLogger.info("endpoint.stopped")
    }

    func endpointConfiguration() -> [String: String] {
        [
            "setup": "\(endpointURL.absoluteString)/v1/setup",
            "mcp": "\(endpointURL.absoluteString)/mcp",
            "registerAgent": "\(endpointURL.absoluteString)/v1/agents/register",
            "events": "\(endpointURL.absoluteString)/v1/agent-events",
            "authorization": "Bearer \(bearerToken)",
            "diagnostics": "\(endpointURL.absoluteString)/v1/diagnostics",
            "status": "\(endpointURL.absoluteString)/v1/status",
            "skillVersion": AgentSwarmContract.skillVersion
        ]
    }

    nonisolated private func accept(_ connection: NWConnection, queue: DispatchQueue) {
        AppLogger.info("endpoint.connection_accepted")
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func updateState(_ state: NWListener.State) {
        switch state {
        case .ready:
            isRunning = true
            statusLine = "Local endpoint ready: \(endpointURL.absoluteString)"
            AppLogger.info("endpoint.ready", details: ["url": endpointURL.absoluteString])
        case .failed(let error):
            isRunning = false
            statusLine = "Local endpoint failed: \(error.localizedDescription)"
            AppLogger.error("endpoint.failed", error: error)
        case .cancelled:
            isRunning = false
            statusLine = "Local endpoint stopped"
            AppLogger.info("endpoint.cancelled")
        default:
            break
        }
    }

    nonisolated private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }

            if let error {
                Task { @MainActor in
                    self.statusLine = "Local endpoint read failed: \(error.localizedDescription)"
                    AppLogger.error("endpoint.read_failed", error: error)
                }
                connection.cancel()
                return
            }

            if let request = HTTPRequest(data: nextBuffer) {
                if request.method == "GET", request.path == "/health" {
                    AppLogger.info("endpoint.health")
                    self.send(.json(["ok": true, "service": "AgentSwarmManagement"]), on: connection)
                    return
                }

                Task { @MainActor in
                    let response = self.handle(request)
                    self.send(response, on: connection)
                }
                return
            }

            if isComplete {
                Task { @MainActor in
                    AppLogger.warning("endpoint.incomplete_request")
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

        guard isAllowedOrigin(request) else {
            AppLogger.warning(
                "endpoint.origin_rejected",
                details: ["method": request.method, "path": request.path, "origin": request.headers["origin"] ?? ""]
            )
            return .json(["ok": false, "error": "Origin is not allowed for the local control endpoint"], status: 403)
        }

        guard isAuthorized(request) else {
            AppLogger.warning("endpoint.unauthorized", details: ["method": request.method, "path": request.path])
            return .unauthorized()
        }

        switch (request.method, request.path) {
        case ("POST", "/mcp"):
            return handleMCP(request)
        case ("GET", "/mcp"):
            return .methodNotAllowed("MCP Streamable HTTP is served by POST /mcp in this build.")
        case ("GET", "/v1/setup"):
            return setupResponse()
        case ("GET", "/v1/status"):
            return statusResponse()
        case ("GET", "/v1/diagnostics"):
            return diagnosticsResponse()
        case ("GET", _) where request.path.hasPrefix("/v1/skill-packages/"):
            return skillPackageResponse(request)
        case ("POST", "/v1/skills/check"):
            return skillCheckResponse(request)
        case ("POST", "/v1/agents/register"):
            return registerAgent(request)
        case ("POST", "/v1/agent-events"):
            return recordAgentEvent(request)
        default:
            AppLogger.warning("endpoint.not_found", details: ["method": request.method, "path": request.path])
            return .notFound()
        }
    }

    private func setupResponse() -> HTTPResponse {
        .json(AgentSwarmContract.setupPayload(baseURL: endpointURL))
    }

    private func statusResponse() -> HTTPResponse {
        guard let store else {
            AppLogger.error("endpoint.status_store_missing")
            return .json(["ok": false, "error": "store not attached"], status: 503)
        }

        return .json([
            "ok": true,
            "endpoint": endpointURL.absoluteString,
            "apiVersion": AgentSwarmContract.apiVersion,
            "skillVersion": AgentSwarmContract.skillVersion,
            "activeProjects": store.activeProjectCount,
            "runningAgents": store.runningAgentCount,
            "openFollowUps": store.openFollowUpCount,
            "blockedTasks": store.blockedTaskCount,
            "pendingNotionOperations": store.pendingOperationCount
        ])
    }

    private func diagnosticsResponse() -> HTTPResponse {
        guard let store else {
            AppLogger.error("endpoint.diagnostics_store_missing")
            return .json(["ok": false, "error": "store not attached"], status: 503)
        }

        let agents = store.agents.map { agent in
            [
                "id": agent.id.uuidString,
                "name": agent.name,
                "harness": agent.harness,
                "status": agent.status.rawValue,
                "projectCount": agent.projectIds.count,
                "lastUpdate": ISO8601DateFormatter().string(from: agent.lastUpdate),
                "harnessAgentId": agent.harnessAgentId ?? "",
                "harnessVersion": agent.harnessVersion ?? "",
                "skillVersion": agent.skillVersion ?? "",
                "sourceMachine": agent.sourceMachine ?? "",
                "lastHealthSummary": agent.lastHealthSummary ?? ""
            ] as [String: Any]
        }

        return .json([
            "ok": true,
            "endpoint": endpointURL.absoluteString,
            "serverRunning": listener != nil,
            "statusLine": statusLine,
            "apiVersion": AgentSwarmContract.apiVersion,
            "skillVersion": AgentSwarmContract.skillVersion,
            "notionConfigured": store.settings.hasCoreNotionDataSources,
            "pendingNotionOperations": store.pendingOperationCount,
            "lastNotionError": store.syncMetadata.lastNotionError ?? "",
            "agents": agents
        ])
    }

    private func registerAgent(_ request: HTTPRequest) -> HTTPResponse {
        guard let store else {
            AppLogger.error("endpoint.register_store_missing")
            return .json(["ok": false, "error": "store not attached"], status: 503)
        }

        do {
            let registration = try JSONDecoder().decode(AgentRegistrationRequest.self, from: request.body)
            let agent = store.registerAgent(registration)
            statusLine = "Registered \(agent.name) via \(agent.harness)"
            AppLogger.info(
                "endpoint.agent_registered",
                details: [
                    "agentId": agent.id.uuidString,
                    "agentName": agent.name,
                    "harness": agent.harness,
                    "sourceMachine": agent.sourceMachine ?? ""
                ]
            )
            return .json([
                "ok": true,
                "agentId": agent.id.uuidString,
                "agentName": agent.name,
                "harness": agent.harness,
                "skillVersion": AgentSwarmContract.skillVersion
            ])
        } catch {
            AppLogger.error("endpoint.agent_register_bad_request", error: error)
            return .badRequest(error.localizedDescription)
        }
    }

    private func skillPackageResponse(_ request: HTTPRequest) -> HTTPResponse {
        let slug = request.path
            .replacingOccurrences(of: "/v1/skill-packages/", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard let family = HarnessFamily.match(slug) else {
            AppLogger.warning("endpoint.skill_package_unknown_harness", details: ["harness": slug])
            return .badRequest("Unknown harness: \(slug)")
        }

        AppLogger.info("endpoint.skill_package_served", details: ["harness": family.slug])
        return .encodable(AgentSwarmContract.skillPackage(for: family, baseURL: endpointURL))
    }

    private func skillCheckResponse(_ request: HTTPRequest) -> HTTPResponse {
        do {
            let check = try JSONDecoder().decode(SkillCheckRequest.self, from: request.body)
            guard let family = HarnessFamily.match(check.harness) else {
                AppLogger.warning("endpoint.skill_check_unknown_harness", details: ["harness": check.harness])
                return .badRequest("Unknown harness: \(check.harness)")
            }

            let expected = AgentSwarmContract.skillPackage(for: family, baseURL: endpointURL)
                .files
                .first { $0.relativePath == "SKILL.md" }?
                .sha256 ?? ""
            let installedVersion = check.installedVersion ?? ""
            let installedHash = check.installedHash ?? ""
            let isCurrent = installedVersion == AgentSwarmContract.skillVersion
                && (installedHash.isEmpty || installedHash == expected)

            AppLogger.info(
                "endpoint.skill_check_completed",
                details: [
                    "harness": family.slug,
                    "installedVersion": installedVersion,
                    "isCurrent": "\(isCurrent)",
                    "path": check.path ?? ""
                ]
            )
            return .json([
                "ok": true,
                "harness": family.slug,
                "currentVersion": AgentSwarmContract.skillVersion,
                "expectedHash": expected,
                "installedVersion": installedVersion,
                "installedHash": installedHash,
                "isCurrent": isCurrent,
                "action": isCurrent ? "none" : "reinstall"
            ])
        } catch {
            AppLogger.error("endpoint.skill_check_bad_request", error: error)
            return .badRequest(error.localizedDescription)
        }
    }

    private func recordAgentEvent(_ request: HTTPRequest) -> HTTPResponse {
        guard let store else {
            AppLogger.error("endpoint.agent_event_store_missing")
            return .json(["ok": false, "error": "store not attached"], status: 503)
        }

        do {
            let event = try JSONDecoder().decode(AgentEventRequest.self, from: request.body)
            guard !event.operationId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                AppLogger.warning("endpoint.agent_event_missing_operation_id")
                return .badRequest("operationId is required")
            }
            guard !event.projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                AppLogger.warning("endpoint.agent_event_missing_project_name", details: ["operationId": event.operationId])
                return .badRequest("projectName is required")
            }

            if store.hasCompletedOperation(event.operationId) {
                AppLogger.info("endpoint.agent_event_deduped", details: ["operationId": event.operationId])
                return .json(["ok": true, "deduped": true])
            }

            store.recordMeaningfulAgentEvent(event)
            statusLine = "Last hook update: \(event.projectName)"
            AppLogger.info(
                "endpoint.agent_event_recorded",
                details: [
                    "operationId": event.operationId,
                    "projectName": event.projectName,
                    "agentName": event.agentName ?? "",
                    "harness": event.harness ?? "",
                    "sourceMachine": event.sourceMachine ?? ""
                ]
            )
            return .json(["ok": true, "operationId": event.operationId])
        } catch {
            AppLogger.error("endpoint.agent_event_bad_request", error: error)
            return .badRequest(error.localizedDescription)
        }
    }

    private func isAuthorized(_ request: HTTPRequest) -> Bool {
        let header = request.headers["authorization"] ?? ""
        return header == "Bearer \(bearerToken)"
    }

    private func isAllowedOrigin(_ request: HTTPRequest) -> Bool {
        guard let origin = request.headers["origin"], !origin.isEmpty else {
            return true
        }

        return origin == "null"
            || origin.hasPrefix("http://127.0.0.1")
            || origin.hasPrefix("http://localhost")
    }

    private func handleMCP(_ request: HTTPRequest) -> HTTPResponse {
        guard let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
              let method = object["method"] as? String else {
            AppLogger.warning("mcp.bad_json")
            return .badRequest("MCP requests must be JSON-RPC objects")
        }

        let id = object["id"] ?? NSNull()
        AppLogger.info("mcp.request", details: ["method": method])
        switch method {
        case "initialize":
            return mcpResult(id: id, result: [
                "protocolVersion": AgentSwarmContract.protocolVersion,
                "capabilities": [
                    "tools": ["listChanged": true],
                    "resources": ["listChanged": true],
                    "prompts": ["listChanged": true]
                ],
                "serverInfo": [
                    "name": "agent-swarm-management",
                    "title": "Agent Swarm Management",
                    "version": AgentSwarmContract.skillVersion
                ],
                "instructions": "Use tools/list, then call agent_swarm_get_setup_instructions, agent_swarm_register, agent_swarm_report_event, and agent_swarm_diagnostics."
            ])
        case "notifications/initialized":
            return .json(["ok": true], status: 202)
        case "tools/list":
            return mcpResult(id: id, result: ["tools": mcpTools()])
        case "tools/call":
            return handleMCPToolCall(id: id, params: object["params"] as? [String: Any])
        case "resources/list":
            return mcpResult(id: id, result: ["resources": mcpResources()])
        case "resources/read":
            return handleMCPResourceRead(id: id, params: object["params"] as? [String: Any])
        case "prompts/list":
            return mcpResult(id: id, result: ["prompts": mcpPrompts()])
        case "prompts/get":
            return handleMCPPromptGet(id: id, params: object["params"] as? [String: Any])
        default:
            AppLogger.warning("mcp.unknown_method", details: ["method": method])
            return mcpError(id: id, code: -32601, message: "Unknown MCP method: \(method)")
        }
    }

    private func handleMCPToolCall(id: Any, params: [String: Any]?) -> HTTPResponse {
        guard let name = params?["name"] as? String else {
            AppLogger.warning("mcp.tool_missing_name")
            return mcpError(id: id, code: -32602, message: "tools/call requires params.name")
        }

        let arguments = params?["arguments"] as? [String: Any] ?? [:]
        AppLogger.info("mcp.tool_call", details: ["name": name])
        switch name {
        case "agent_swarm_get_setup_instructions":
            return mcpTextResult(id: id, text: jsonString(AgentSwarmContract.setupPayload(baseURL: endpointURL)))
        case "agent_swarm_register":
            do {
                guard let store else {
                    AppLogger.error("mcp.register_store_missing")
                    return mcpError(id: id, code: -32000, message: "store not attached")
                }
                let registration = try decode(AgentRegistrationRequest.self, fromJSONObject: arguments)
                let agent = store.registerAgent(registration)
                AppLogger.info(
                    "mcp.agent_registered",
                    details: ["agentId": agent.id.uuidString, "agentName": agent.name, "harness": agent.harness]
                )
                return mcpTextResult(id: id, text: "Registered \(agent.name) as \(agent.harness).")
            } catch {
                AppLogger.error("mcp.agent_register_failed", error: error)
                return mcpError(id: id, code: -32602, message: error.localizedDescription)
            }
        case "agent_swarm_report_event":
            do {
                guard let store else {
                    AppLogger.error("mcp.report_event_store_missing")
                    return mcpError(id: id, code: -32000, message: "store not attached")
                }
                let event = try decode(AgentEventRequest.self, fromJSONObject: arguments)
                if !store.hasCompletedOperation(event.operationId) {
                    store.recordMeaningfulAgentEvent(event)
                    AppLogger.info(
                        "mcp.agent_event_recorded",
                        details: ["operationId": event.operationId, "projectName": event.projectName]
                    )
                } else {
                    AppLogger.info("mcp.agent_event_deduped", details: ["operationId": event.operationId])
                }
                return mcpTextResult(id: id, text: "Recorded event \(event.operationId).")
            } catch {
                AppLogger.error("mcp.report_event_failed", error: error)
                return mcpError(id: id, code: -32602, message: error.localizedDescription)
            }
        case "agent_swarm_diagnostics":
            return mcpTextResult(id: id, text: jsonString(diagnosticsPayload()))
        case "agent_swarm_get_skill_package":
            let harness = (arguments["harness"] as? String) ?? "generic"
            guard let family = HarnessFamily.match(harness) else {
                AppLogger.warning("mcp.skill_package_unknown_harness", details: ["harness": harness])
                return mcpError(id: id, code: -32602, message: "Unknown harness: \(harness)")
            }
            return mcpTextResult(id: id, text: jsonString(packageDictionary(for: family)))
        case "agent_swarm_check_skill":
            do {
                let check = try decode(SkillCheckRequest.self, fromJSONObject: arguments)
                guard let family = HarnessFamily.match(check.harness) else {
                    AppLogger.warning("mcp.skill_check_unknown_harness", details: ["harness": check.harness])
                    return mcpError(id: id, code: -32602, message: "Unknown harness: \(check.harness)")
                }
                let expected = AgentSwarmContract.skillPackage(for: family, baseURL: endpointURL)
                    .files
                    .first { $0.relativePath == "SKILL.md" }?
                    .sha256 ?? ""
                let installedVersion = check.installedVersion ?? ""
                let installedHash = check.installedHash ?? ""
                let isCurrent = installedVersion == AgentSwarmContract.skillVersion
                    && (installedHash.isEmpty || installedHash == expected)
                return mcpTextResult(id: id, text: jsonString([
                    "ok": true,
                    "harness": family.slug,
                    "currentVersion": AgentSwarmContract.skillVersion,
                    "expectedHash": expected,
                    "isCurrent": isCurrent,
                    "action": isCurrent ? "none" : "reinstall"
                ]))
            } catch {
                AppLogger.error("mcp.skill_check_failed", error: error)
                return mcpError(id: id, code: -32602, message: error.localizedDescription)
            }
        default:
            AppLogger.warning("mcp.unknown_tool", details: ["name": name])
            return mcpError(id: id, code: -32601, message: "Unknown tool: \(name)")
        }
    }

    private func handleMCPResourceRead(id: Any, params: [String: Any]?) -> HTTPResponse {
        guard let uri = params?["uri"] as? String else {
            AppLogger.warning("mcp.resource_missing_uri")
            return mcpError(id: id, code: -32602, message: "resources/read requires params.uri")
        }

        AppLogger.info("mcp.resource_read", details: ["uri": uri])
        let text: String
        switch uri {
        case "agent-swarm://setup":
            text = jsonString(AgentSwarmContract.setupPayload(baseURL: endpointURL))
        case "agent-swarm://schemas/agent-registration":
            text = jsonString(AgentSwarmContract.setupPayload(baseURL: endpointURL)["registrationSchema"] as? [String: Any] ?? [:])
        case "agent-swarm://schemas/agent-event":
            text = jsonString(eventSchema())
        case "agent-swarm://skill/openclaw":
            text = AgentSwarmContract.skillInstructions(for: .openClaw, baseURL: endpointURL)
        case "agent-swarm://skill/claude-code":
            text = AgentSwarmContract.skillInstructions(for: .claudeCode, baseURL: endpointURL)
        case "agent-swarm://skill/codex":
            text = AgentSwarmContract.skillInstructions(for: .codex, baseURL: endpointURL)
        default:
            AppLogger.warning("mcp.unknown_resource", details: ["uri": uri])
            return mcpError(id: id, code: -32602, message: "Unknown resource: \(uri)")
        }

        return mcpResult(id: id, result: [
            "contents": [
                [
                    "uri": uri,
                    "mimeType": uri.contains("schemas") || uri == "agent-swarm://setup" ? "application/json" : "text/markdown",
                    "text": text
                ]
            ]
        ])
    }

    private func handleMCPPromptGet(id: Any, params: [String: Any]?) -> HTTPResponse {
        let name = params?["name"] as? String ?? ""
        AppLogger.info("mcp.prompt_get", details: ["name": name])
        let text: String
        switch name {
        case "agent_swarm_setup":
            text = "Read agent-swarm://setup, install the matching skill package for your harness, then register this agent before reporting work."
        case "agent_swarm_report_status":
            text = "Report only meaningful project/task/follow-up/artifact changes. Avoid heartbeat spam. Include stable operationId, project, agentName, harness, sourceMachine, and sourceTurnId when available."
        default:
            AppLogger.warning("mcp.unknown_prompt", details: ["name": name])
            return mcpError(id: id, code: -32602, message: "Unknown prompt: \(name)")
        }

        return mcpResult(id: id, result: [
            "description": name,
            "messages": [
                [
                    "role": "user",
                    "content": ["type": "text", "text": text]
                ]
            ]
        ])
    }

    private func diagnosticsPayload() -> [String: Any] {
        guard let store else {
            return ["ok": false, "error": "store not attached"]
        }

        return [
            "ok": true,
            "endpoint": endpointURL.absoluteString,
            "serverRunning": isRunning,
            "statusLine": statusLine,
            "activeProjects": store.activeProjectCount,
            "runningAgents": store.runningAgentCount,
            "pendingNotionOperations": store.pendingOperationCount,
            "skillVersion": AgentSwarmContract.skillVersion
        ]
    }

    private func mcpTools() -> [[String: Any]] {
        [
            [
                "name": "agent_swarm_get_setup_instructions",
                "title": "Get Agent Swarm setup instructions",
                "description": "Return the current endpoint contract, supported harnesses, skill version, and install instructions.",
                "inputSchema": ["type": "object", "properties": [:]]
            ],
            [
                "name": "agent_swarm_register",
                "title": "Register this agent",
                "description": "Register or refresh the current agent/harness identity without assigning it to a project.",
                "inputSchema": [
                    "type": "object",
                    "required": ["agentName", "harness"],
                    "properties": [
                        "agentName": ["type": "string"],
                        "harness": ["type": "string"],
                        "harnessAgentId": ["type": "string"],
                        "harnessVersion": ["type": "string"],
                        "skillVersion": ["type": "string"],
                        "sourceMachine": ["type": "string"],
                        "capabilities": ["type": "array", "items": ["type": "string"]],
                        "status": ["type": "string"],
                        "summary": ["type": "string"]
                    ]
                ]
            ],
            [
                "name": "agent_swarm_report_event",
                "title": "Report meaningful agent work",
                "description": "Create or update projects, tasks, follow-ups, and agent status from real work.",
                "inputSchema": [
                    "type": "object",
                    "required": ["operationId", "projectName"],
                    "properties": [
                        "operationId": ["type": "string"],
                        "projectName": ["type": "string"],
                        "agentName": ["type": "string"],
                        "harness": ["type": "string"],
                        "taskTitle": ["type": "string"],
                        "taskStatus": ["type": "string"],
                        "followUpQuestion": ["type": "string"],
                        "summary": ["type": "string"],
                        "sourceTurnId": ["type": "string"],
                        "sourceMachine": ["type": "string"]
                    ]
                ]
            ],
            [
                "name": "agent_swarm_diagnostics",
                "title": "Diagnose Agent Swarm connectivity",
                "description": "Return local endpoint health, pending sync, and high-level app status.",
                "inputSchema": ["type": "object", "properties": [:]]
            ],
            [
                "name": "agent_swarm_get_skill_package",
                "title": "Get skill package",
                "description": "Return the installable skill package for OpenClaw, Claude Code, Codex, or generic harnesses.",
                "inputSchema": [
                    "type": "object",
                    "required": ["harness"],
                    "properties": ["harness": ["type": "string"]]
                ]
            ],
            [
                "name": "agent_swarm_check_skill",
                "title": "Check installed skill",
                "description": "Compare an installed skill version/hash with the app's current package.",
                "inputSchema": [
                    "type": "object",
                    "required": ["harness"],
                    "properties": [
                        "harness": ["type": "string"],
                        "installedVersion": ["type": "string"],
                        "installedHash": ["type": "string"],
                        "path": ["type": "string"]
                    ]
                ]
            ]
        ]
    }

    private func mcpResources() -> [[String: Any]] {
        [
            ["uri": "agent-swarm://setup", "name": "Setup contract", "mimeType": "application/json"],
            ["uri": "agent-swarm://schemas/agent-registration", "name": "Agent registration schema", "mimeType": "application/json"],
            ["uri": "agent-swarm://schemas/agent-event", "name": "Agent event schema", "mimeType": "application/json"],
            ["uri": "agent-swarm://skill/openclaw", "name": "OpenClaw skill", "mimeType": "text/markdown"],
            ["uri": "agent-swarm://skill/claude-code", "name": "Claude Code skill", "mimeType": "text/markdown"],
            ["uri": "agent-swarm://skill/codex", "name": "Codex skill", "mimeType": "text/markdown"]
        ]
    }

    private func mcpPrompts() -> [[String: Any]] {
        [
            [
                "name": "agent_swarm_setup",
                "title": "Set up this harness",
                "description": "Guide the current harness through Agent Swarm setup and registration."
            ],
            [
                "name": "agent_swarm_report_status",
                "title": "Report meaningful status",
                "description": "Guide an agent to send a concise meaningful Agent Swarm update."
            ]
        ]
    }

    private func eventSchema() -> [String: Any] {
        [
            "operationId": "stable idempotency key for this event",
            "projectName": "project name to create or update",
            "agentName": "optional reporting agent name",
            "harness": "optional harness name",
            "taskTitle": "optional task title",
            "taskStatus": "healthy | needsAttention | blocked | done",
            "followUpQuestion": "optional question/decision for the human",
            "summary": "short meaningful update",
            "sourceTurnId": "optional source turn/chat/message id",
            "sourceMachine": "optional machine name"
        ]
    }

    private func packageDictionary(for family: HarnessFamily) -> [String: Any] {
        let package = AgentSwarmContract.skillPackage(for: family, baseURL: endpointURL)
        let data = (try? JSONEncoder().encode(package)) ?? Data("{}".utf8)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func mcpResult(id: Any, result: [String: Any]) -> HTTPResponse {
        .json(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func mcpTextResult(id: Any, text: String) -> HTTPResponse {
        mcpResult(id: id, result: ["content": [["type": "text", "text": text]], "isError": false])
    }

    private func mcpError(id: Any, code: Int, message: String) -> HTTPResponse {
        .json([
            "jsonrpc": "2.0",
            "id": id,
            "error": ["code": code, "message": message]
        ])
    }

    private func jsonString(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]))
            ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func decode<T: Decodable>(_ type: T.Type, fromJSONObject object: [String: Any]) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(T.self, from: data)
    }

    nonisolated private func send(_ response: HTTPResponse, on connection: NWConnection) {
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

    static func methodNotAllowed(_ message: String) -> HTTPResponse {
        json(["ok": false, "error": message], status: 405)
    }

    static func encodable<T: Encodable>(_ value: T, status: Int = 200) -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = (try? encoder.encode(value)) ?? Data("{}".utf8)
        return HTTPResponse(status: status, reason: reasonPhrase(for: status), body: data, contentType: "application/json")
    }

    private static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: "OK"
        case 202: "Accepted"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 503: "Service Unavailable"
        default: "OK"
        }
    }
}

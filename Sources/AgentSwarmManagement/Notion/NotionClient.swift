import Foundation

struct NotionClientConfiguration: Sendable {
    var apiToken: String
    var notionVersion: String
}

struct NotionWorkspaceSnapshot: Sendable {
    var fetchedAt: Date
    var projects: [SwarmProject]
    var agents: [SwarmAgent]
    var tasks: [SwarmTask]
    var followUps: [FollowUp]
}

struct NotionSchema: Codable, Equatable, Sendable {
    var rootPageId: String
    var projectsDataSourceId: String
    var agentsDataSourceId: String
    var tasksDataSourceId: String
    var followUpsDataSourceId: String
    var artifactsDataSourceId: String
}

enum NotionAPIError: LocalizedError {
    case missingToken
    case missingDataSource(String)
    case malformedURL
    case invalidResponse
    case rateLimited(seconds: TimeInterval)
    case requestFailed(status: Int, message: String)
    case malformedPayload(String)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            "Add a Notion API token before syncing."
        case .missingDataSource(let name):
            "Configure the \(name) Notion data source before syncing."
        case .malformedURL:
            "The Notion API URL could not be built."
        case .invalidResponse:
            "Notion returned an invalid HTTP response."
        case .rateLimited(let seconds):
            "Notion rate limited the connection. Retry after \(Int(seconds)) seconds."
        case .requestFailed(let status, let message):
            "Notion request failed with HTTP \(status): \(message)"
        case .malformedPayload(let context):
            "Notion returned a payload this app could not parse: \(context)"
        }
    }
}

actor NotionClient {
    private let configuration: NotionClientConfiguration
    private let session: URLSession
    private let isoFormatter = ISO8601DateFormatter()

    init(configuration: NotionClientConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func createSchema(rootPage: String) async throws -> NotionSchema {
        let rootPageId = Self.normalizedNotionId(from: rootPage)

        let projects = try await createDatabase(
            parentPageId: rootPageId,
            title: "Projects",
            properties: commonProperties(plus: [
                "Summary": ["rich_text": [:]],
                "Active Agent IDs": ["rich_text": [:]],
                "Open Task Count": ["number": ["format": "number"]],
                "Follow-up Count": ["number": ["format": "number"]],
                "Last Meaningful Change": ["date": [:]]
            ])
        )

        let agents = try await createDatabase(
            parentPageId: rootPageId,
            title: "Agents",
            properties: commonProperties(plus: [
                "Harness": ["rich_text": [:]],
                "Project IDs": ["rich_text": [:]],
                "Last Update": ["date": [:]]
            ])
        )

        let tasks = try await createDatabase(
            parentPageId: rootPageId,
            title: "Tasks",
            properties: commonProperties(plus: [
                "Project ID": ["rich_text": [:]],
                "Agent IDs": ["rich_text": [:]],
                "Parent Task ID": ["rich_text": [:]],
                "Source Turn ID": ["rich_text": [:]]
            ])
        )

        let followUps = try await createDatabase(
            parentPageId: rootPageId,
            title: "Follow-ups",
            properties: commonProperties(plus: [
                "Project ID": ["rich_text": [:]],
                "Agent ID": ["rich_text": [:]],
                "Question": ["rich_text": [:]],
                "Created At": ["date": [:]],
                "Source Turn ID": ["rich_text": [:]]
            ])
        )

        let artifacts = try await createDatabase(
            parentPageId: rootPageId,
            title: "Artifacts",
            properties: commonProperties(plus: [
                "Project ID": ["rich_text": [:]],
                "Kind": ["rich_text": [:]],
                "URL": ["url": [:]],
                "Created At": ["date": [:]]
            ])
        )

        return NotionSchema(
            rootPageId: rootPageId,
            projectsDataSourceId: projects,
            agentsDataSourceId: agents,
            tasksDataSourceId: tasks,
            followUpsDataSourceId: followUps,
            artifactsDataSourceId: artifacts
        )
    }

    func fetchWorkspaceSnapshot(settings: AppSettings) async throws -> NotionWorkspaceSnapshot {
        guard settings.hasAnyNotionDataSource else {
            throw NotionAPIError.missingDataSource("workspace")
        }

        async let projects = queryProjects(dataSourceId: settings.projectsDataSourceId)
        async let agents = queryAgents(dataSourceId: settings.agentsDataSourceId)
        async let tasks = queryTasks(dataSourceId: settings.tasksDataSourceId)
        async let followUps = queryFollowUps(dataSourceId: settings.followUpsDataSourceId)

        return try await NotionWorkspaceSnapshot(
            fetchedAt: .now,
            projects: projects,
            agents: agents,
            tasks: tasks,
            followUps: followUps
        )
    }

    func upsertProject(_ project: SwarmProject, settings: AppSettings) async throws -> String {
        try await upsertPage(
            existingPageId: project.sourcePageId,
            dataSourceId: settings.projectsDataSourceId,
            dataSourceName: "Projects",
            properties: projectProperties(project, settings: settings)
        )
    }

    func upsertAgent(_ agent: SwarmAgent, settings: AppSettings) async throws -> String {
        try await upsertPage(
            existingPageId: agent.sourcePageId,
            dataSourceId: settings.agentsDataSourceId,
            dataSourceName: "Agents",
            properties: agentProperties(agent, settings: settings)
        )
    }

    func upsertTask(_ task: SwarmTask, settings: AppSettings) async throws -> String {
        try await upsertPage(
            existingPageId: task.sourcePageId,
            dataSourceId: settings.tasksDataSourceId,
            dataSourceName: "Tasks",
            properties: taskProperties(task, settings: settings)
        )
    }

    func upsertFollowUp(_ followUp: FollowUp, settings: AppSettings) async throws -> String {
        try await upsertPage(
            existingPageId: followUp.sourcePageId,
            dataSourceId: settings.followUpsDataSourceId,
            dataSourceName: "Follow-ups",
            properties: followUpProperties(followUp, settings: settings)
        )
    }

    func trashPage(_ pageId: String) async throws {
        _ = try await requestJSONObject(
            path: "/v1/pages/\(Self.normalizedNotionId(from: pageId))",
            method: "PATCH",
            body: ["in_trash": true]
        )
    }

    private func queryProjects(dataSourceId: String) async throws -> [SwarmProject] {
        guard !dataSourceId.isEmpty else { return [] }
        return try await queryAllPages(dataSourceId: dataSourceId).map { page in
            let properties = page.properties
            return SwarmProject(
                id: localId(from: page, properties: properties),
                name: title(properties, "Name"),
                summary: richText(properties, "Summary"),
                status: SwarmStatus(apiValue: selectName(properties, "Status")),
                activeAgentIds: uuidList(richText(properties, "Active Agent IDs")),
                openTaskCount: Int(number(properties, "Open Task Count") ?? 0),
                followUpCount: Int(number(properties, "Follow-up Count") ?? 0),
                lastMeaningfulChange: date(properties, "Last Meaningful Change") ?? page.lastEditedTime ?? .now,
                sourcePageId: page.id,
                lastUpdatedBy: richText(properties, "Last Updated By").emptyToNil
            )
        }
    }

    private func queryAgents(dataSourceId: String) async throws -> [SwarmAgent] {
        guard !dataSourceId.isEmpty else { return [] }
        return try await queryAllPages(dataSourceId: dataSourceId).map { page in
            let properties = page.properties
            return SwarmAgent(
                id: localId(from: page, properties: properties),
                name: title(properties, "Name"),
                harness: richText(properties, "Harness"),
                status: SwarmStatus(apiValue: selectName(properties, "Status")),
                projectIds: uuidList(richText(properties, "Project IDs")),
                lastUpdate: date(properties, "Last Update") ?? page.lastEditedTime ?? .now,
                sourcePageId: page.id,
                lastUpdatedBy: richText(properties, "Last Updated By").emptyToNil
            )
        }
    }

    private func queryTasks(dataSourceId: String) async throws -> [SwarmTask] {
        guard !dataSourceId.isEmpty else { return [] }
        return try await queryAllPages(dataSourceId: dataSourceId).compactMap { page in
            let properties = page.properties
            guard let projectId = UUID(uuidString: richText(properties, "Project ID")) else {
                return nil
            }

            return SwarmTask(
                id: localId(from: page, properties: properties),
                projectId: projectId,
                title: title(properties, "Name"),
                status: SwarmStatus(apiValue: selectName(properties, "Status")),
                assignedAgentIds: uuidList(richText(properties, "Agent IDs")),
                parentTaskId: UUID(uuidString: richText(properties, "Parent Task ID")),
                sourcePageId: page.id,
                sourceTurnId: richText(properties, "Source Turn ID").emptyToNil,
                lastUpdatedBy: richText(properties, "Last Updated By").emptyToNil
            )
        }
    }

    private func queryFollowUps(dataSourceId: String) async throws -> [FollowUp] {
        guard !dataSourceId.isEmpty else { return [] }
        return try await queryAllPages(dataSourceId: dataSourceId).compactMap { page in
            let properties = page.properties
            guard let projectId = UUID(uuidString: richText(properties, "Project ID")) else {
                return nil
            }
            let questionText = richText(properties, "Question")
            let fallbackTitle = title(properties, "Name")
            let question = questionText.emptyToNil ?? fallbackTitle

            return FollowUp(
                id: localId(from: page, properties: properties),
                projectId: projectId,
                agentId: UUID(uuidString: richText(properties, "Agent ID")),
                question: question,
                status: SwarmStatus(apiValue: selectName(properties, "Status")),
                createdAt: date(properties, "Created At") ?? page.lastEditedTime ?? .now,
                sourceTurnId: richText(properties, "Source Turn ID").emptyToNil,
                sourcePageId: page.id,
                lastUpdatedBy: richText(properties, "Last Updated By").emptyToNil
            )
        }
    }

    private func queryAllPages(dataSourceId: String) async throws -> [NotionPagePayload] {
        var pages: [NotionPagePayload] = []
        var cursor: String?

        repeat {
            var body: [String: Any] = ["page_size": 100]
            if let cursor {
                body["start_cursor"] = cursor
            }

            let response = try await requestJSONObject(
                path: "/v1/data_sources/\(Self.normalizedNotionId(from: dataSourceId))/query",
                method: "POST",
                body: body
            )

            guard let results = response["results"] as? [[String: Any]] else {
                throw NotionAPIError.malformedPayload("missing query results")
            }

            pages.append(contentsOf: results.compactMap(NotionPagePayload.init(raw:)))
            cursor = response["next_cursor"] as? String
        } while cursor != nil

        return pages
    }

    private func upsertPage(
        existingPageId: String?,
        dataSourceId: String,
        dataSourceName: String,
        properties: [String: Any]
    ) async throws -> String {
        guard !dataSourceId.isEmpty else {
            throw NotionAPIError.missingDataSource(dataSourceName)
        }

        if let existingPageId, !existingPageId.isEmpty {
            let response = try await requestJSONObject(
                path: "/v1/pages/\(Self.normalizedNotionId(from: existingPageId))",
                method: "PATCH",
                body: ["properties": properties]
            )
            return try pageId(from: response)
        }

        let response = try await requestJSONObject(
            path: "/v1/pages",
            method: "POST",
            body: [
                "parent": ["data_source_id": Self.normalizedNotionId(from: dataSourceId)],
                "properties": properties
            ]
        )
        return try pageId(from: response)
    }

    private func createDatabase(parentPageId: String, title: String, properties: [String: Any]) async throws -> String {
        let response = try await requestJSONObject(
            path: "/v1/databases",
            method: "POST",
            body: [
                "parent": [
                    "type": "page_id",
                    "page_id": parentPageId
                ],
                "title": [
                    [
                        "type": "text",
                        "text": ["content": title]
                    ]
                ],
                "initial_data_source": [
                    "title": [
                        [
                            "type": "text",
                            "text": ["content": title]
                        ]
                    ],
                    "properties": properties
                ]
            ]
        )

        if
            let dataSources = response["data_sources"] as? [[String: Any]],
            let firstId = dataSources.first?["id"] as? String
        {
            return firstId
        }

        return try pageId(from: response)
    }

    private func requestJSONObject(path: String, method: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        guard !configuration.apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NotionAPIError.missingToken
        }

        guard let url = URL(string: "https://api.notion.com\(path)") else {
            throw NotionAPIError.malformedURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(configuration.apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.notionVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        }

        AppLogger.info("notion.request_started", details: ["method": method, "path": path])
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            AppLogger.error("notion.invalid_response", details: ["method": method, "path": path])
            throw NotionAPIError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap(TimeInterval.init) ?? 1
            AppLogger.warning(
                "notion.request_rate_limited",
                details: ["method": method, "path": path, "retryAfterSeconds": "\(retryAfter)"]
            )
            throw NotionAPIError.rateLimited(seconds: retryAfter)
        }

        let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = payload?["message"] as? String ?? String(data: data, encoding: .utf8) ?? "No response body"
            AppLogger.error(
                "notion.request_failed",
                details: [
                    "method": method,
                    "path": path,
                    "status": "\(httpResponse.statusCode)",
                    "message": message
                ]
            )
            throw NotionAPIError.requestFailed(status: httpResponse.statusCode, message: message)
        }

        guard let payload else {
            AppLogger.error("notion.malformed_payload", details: ["method": method, "path": path])
            throw NotionAPIError.malformedPayload("expected JSON object")
        }

        AppLogger.info(
            "notion.request_finished",
            details: ["method": method, "path": path, "status": "\(httpResponse.statusCode)"]
        )
        return payload
    }

    private func commonProperties(plus properties: [String: Any]) -> [String: Any] {
        var schema: [String: Any] = [
            "Name": ["title": [:]],
            "Status": [
                "select": [
                    "options": SwarmStatus.allCases.map { ["name": $0.title] }
                ]
            ],
            "Local ID": ["rich_text": [:]],
            "Last Updated By": ["rich_text": [:]],
            "Parent Link": ["url": [:]]
        ]

        for (key, value) in properties {
            schema[key] = value
        }
        return schema
    }

    private func projectProperties(_ project: SwarmProject, settings: AppSettings) -> [String: Any] {
        commonPageProperties(
            name: project.name,
            localId: project.id,
            status: project.status,
            lastUpdatedBy: project.lastUpdatedBy,
            settings: settings,
            plus: [
                "Summary": richTextProperty(project.summary),
                "Active Agent IDs": richTextProperty(uuidList(project.activeAgentIds)),
                "Open Task Count": ["number": project.openTaskCount],
                "Follow-up Count": ["number": project.followUpCount],
                "Last Meaningful Change": dateProperty(project.lastMeaningfulChange)
            ]
        )
    }

    private func agentProperties(_ agent: SwarmAgent, settings: AppSettings) -> [String: Any] {
        commonPageProperties(
            name: agent.name,
            localId: agent.id,
            status: agent.status,
            lastUpdatedBy: agent.lastUpdatedBy,
            settings: settings,
            plus: [
                "Harness": richTextProperty(agent.harness),
                "Project IDs": richTextProperty(uuidList(agent.projectIds)),
                "Last Update": dateProperty(agent.lastUpdate)
            ]
        )
    }

    private func taskProperties(_ task: SwarmTask, settings: AppSettings) -> [String: Any] {
        commonPageProperties(
            name: task.title,
            localId: task.id,
            status: task.status,
            lastUpdatedBy: task.lastUpdatedBy,
            settings: settings,
            plus: [
                "Project ID": richTextProperty(task.projectId.uuidString),
                "Agent IDs": richTextProperty(uuidList(task.assignedAgentIds)),
                "Parent Task ID": richTextProperty(task.parentTaskId?.uuidString ?? ""),
                "Source Turn ID": richTextProperty(task.sourceTurnId ?? "")
            ]
        )
    }

    private func followUpProperties(_ followUp: FollowUp, settings: AppSettings) -> [String: Any] {
        commonPageProperties(
            name: followUp.question,
            localId: followUp.id,
            status: followUp.status,
            lastUpdatedBy: followUp.lastUpdatedBy,
            settings: settings,
            plus: [
                "Project ID": richTextProperty(followUp.projectId.uuidString),
                "Agent ID": richTextProperty(followUp.agentId?.uuidString ?? ""),
                "Question": richTextProperty(followUp.question),
                "Created At": dateProperty(followUp.createdAt),
                "Source Turn ID": richTextProperty(followUp.sourceTurnId ?? "")
            ]
        )
    }

    private func commonPageProperties(
        name: String,
        localId: UUID,
        status: SwarmStatus,
        lastUpdatedBy: String?,
        settings: AppSettings,
        plus properties: [String: Any]
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "Name": titleProperty(name),
            "Status": ["select": ["name": status.title]],
            "Local ID": richTextProperty(localId.uuidString),
            "Last Updated By": richTextProperty(lastUpdatedBy ?? ""),
            "Parent Link": ["url": parentPageURL(settings.notionRootPage)]
        ]

        for (key, value) in properties {
            payload[key] = value
        }
        return payload
    }

    private func titleProperty(_ value: String) -> [String: Any] {
        [
            "title": [
                [
                    "type": "text",
                    "text": ["content": value.notionLimited]
                ]
            ]
        ]
    }

    private func richTextProperty(_ value: String) -> [String: Any] {
        guard !value.isEmpty else {
            return ["rich_text": []]
        }

        return [
            "rich_text": [
                [
                    "type": "text",
                    "text": ["content": value.notionLimited]
                ]
            ]
        ]
    }

    private func dateProperty(_ value: Date) -> [String: Any] {
        ["date": ["start": isoFormatter.string(from: value)]]
    }

    private func pageId(from response: [String: Any]) throws -> String {
        guard let id = response["id"] as? String else {
            throw NotionAPIError.malformedPayload("missing page id")
        }
        return id
    }

    nonisolated private func localId(from page: NotionPagePayload, properties: [String: Any]) -> UUID {
        UUID(uuidString: richText(properties, "Local ID"))
            ?? UUID(uuidString: Self.dashedUUIDString(from: page.id))
            ?? UUID()
    }

    nonisolated private func title(_ properties: [String: Any], _ name: String) -> String {
        guard let property = properties[name] as? [String: Any] else { return "" }
        if let title = property["title"] as? [[String: Any]] {
            return title.compactMap { $0["plain_text"] as? String }.joined()
        }
        return richText(properties, name)
    }

    nonisolated private func richText(_ properties: [String: Any], _ name: String) -> String {
        guard
            let property = properties[name] as? [String: Any],
            let richText = property["rich_text"] as? [[String: Any]]
        else {
            return ""
        }
        return richText.compactMap { $0["plain_text"] as? String }.joined()
    }

    nonisolated private func selectName(_ properties: [String: Any], _ name: String) -> String? {
        guard
            let property = properties[name] as? [String: Any],
            let select = property["select"] as? [String: Any]
        else {
            return nil
        }
        return select["name"] as? String
    }

    nonisolated private func number(_ properties: [String: Any], _ name: String) -> Double? {
        guard let property = properties[name] as? [String: Any] else { return nil }
        if let value = property["number"] as? Double {
            return value
        }
        if let value = property["number"] as? Int {
            return Double(value)
        }
        return nil
    }

    nonisolated private func date(_ properties: [String: Any], _ name: String) -> Date? {
        guard
            let property = properties[name] as? [String: Any],
            let date = property["date"] as? [String: Any],
            let start = date["start"] as? String
        else {
            return nil
        }
        return ISO8601DateFormatter().date(from: start)
    }

    private func uuidList(_ ids: [UUID]) -> String {
        ids.map(\.uuidString).joined(separator: ",")
    }

    nonisolated private func uuidList(_ value: String) -> [UUID] {
        value
            .split(separator: ",")
            .compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private func parentPageURL(_ rootPage: String) -> String? {
        guard !rootPage.isEmpty else { return nil }
        if rootPage.hasPrefix("https://") {
            return rootPage
        }
        return "https://www.notion.so/\(Self.normalizedNotionId(from: rootPage).replacingOccurrences(of: "-", with: ""))"
    }

    static func normalizedNotionId(from value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lastPathComponent = URL(string: trimmed)?.lastPathComponent, trimmed.hasPrefix("http") else {
            return dashedUUIDString(from: trimmed)
        }

        let candidate = lastPathComponent.split(separator: "-").last.map(String.init) ?? lastPathComponent
        return dashedUUIDString(from: candidate)
    }

    static func dashedUUIDString(from value: String) -> String {
        let hex = value.filter { $0.isHexDigit }
        guard hex.count >= 32 else { return value }
        let prefix = String(hex.prefix(32))
        return [
            String(prefix.prefix(8)),
            String(prefix.dropFirst(8).prefix(4)),
            String(prefix.dropFirst(12).prefix(4)),
            String(prefix.dropFirst(16).prefix(4)),
            String(prefix.dropFirst(20).prefix(12))
        ].joined(separator: "-")
    }
}

private struct NotionPagePayload {
    var id: String
    var lastEditedTime: Date?
    var properties: [String: Any]

    init?(raw: [String: Any]) {
        guard
            let id = raw["id"] as? String,
            let properties = raw["properties"] as? [String: Any]
        else {
            return nil
        }

        self.id = id
        self.properties = properties

        if let lastEdited = raw["last_edited_time"] as? String {
            self.lastEditedTime = ISO8601DateFormatter().date(from: lastEdited)
        }
    }
}

private extension String {
    var notionLimited: String {
        String(prefix(2_000))
    }

    var emptyToNil: String? {
        isEmpty ? nil : self
    }
}

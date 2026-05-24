import Foundation

enum SwarmRecordKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case project
    case agent
    case task
    case followUp
    case artifact

    var id: String { rawValue }
}

enum SwarmMutationKind: String, Codable, Sendable {
    case upsert
    case delete
}

struct AppSettings: Codable, Equatable, Sendable {
    var notionVersion: String
    var notionRootPage: String
    var projectsDataSourceId: String
    var agentsDataSourceId: String
    var tasksDataSourceId: String
    var followUpsDataSourceId: String
    var artifactsDataSourceId: String
    var localServerPort: UInt16
    var offlineWritesEnabled: Bool
    var writesPaused: Bool

    static let currentNotionVersion = "2026-03-11"

    static var defaults: AppSettings {
        AppSettings(
            notionVersion: currentNotionVersion,
            notionRootPage: "",
            projectsDataSourceId: "",
            agentsDataSourceId: "",
            tasksDataSourceId: "",
            followUpsDataSourceId: "",
            artifactsDataSourceId: "",
            localServerPort: 17391,
            offlineWritesEnabled: false,
            writesPaused: false
        )
    }

    var hasAnyNotionDataSource: Bool {
        !projectsDataSourceId.isEmpty
            || !agentsDataSourceId.isEmpty
            || !tasksDataSourceId.isEmpty
            || !followUpsDataSourceId.isEmpty
            || !artifactsDataSourceId.isEmpty
    }

    var hasCoreNotionDataSources: Bool {
        !projectsDataSourceId.isEmpty
            && !agentsDataSourceId.isEmpty
            && !tasksDataSourceId.isEmpty
            && !followUpsDataSourceId.isEmpty
    }
}

struct PendingSyncOperation: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var kind: SwarmRecordKind
    var mutation: SwarmMutationKind
    var localRecordId: UUID
    var notionPageId: String?
    var createdAt: Date
    var updatedAt: Date
    var attemptCount: Int
    var lastError: String?

    init(
        id: String,
        kind: SwarmRecordKind,
        mutation: SwarmMutationKind,
        localRecordId: UUID,
        notionPageId: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        attemptCount: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.mutation = mutation
        self.localRecordId = localRecordId
        self.notionPageId = notionPageId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.attemptCount = attemptCount
        self.lastError = lastError
    }
}

struct SyncMetadata: Codable, Equatable, Sendable {
    var lastPullAt: Date?
    var lastPushAt: Date?
    var lastNotionError: String?
    var lastControlEventAt: Date?
    var completedOperationIds: [String]

    static var empty: SyncMetadata {
        SyncMetadata(
            lastPullAt: nil,
            lastPushAt: nil,
            lastNotionError: nil,
            lastControlEventAt: nil,
            completedOperationIds: []
        )
    }
}

struct AgentEventRequest: Codable, Sendable {
    var operationId: String
    var projectName: String
    var agentName: String?
    var harness: String?
    var taskTitle: String?
    var taskStatus: SwarmStatus?
    var followUpQuestion: String?
    var summary: String?
    var sourceTurnId: String?
    var sourceMachine: String?

    var actorDescription: String {
        [sourceMachine, harness, agentName]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: " / ")
    }

    enum CodingKeys: String, CodingKey {
        case operationId
        case projectName
        case agentName
        case harness
        case taskTitle
        case taskStatus
        case followUpQuestion
        case summary
        case sourceTurnId
        case sourceMachine
    }

    init(
        operationId: String,
        projectName: String,
        agentName: String? = nil,
        harness: String? = nil,
        taskTitle: String? = nil,
        taskStatus: SwarmStatus? = nil,
        followUpQuestion: String? = nil,
        summary: String? = nil,
        sourceTurnId: String? = nil,
        sourceMachine: String? = nil
    ) {
        self.operationId = operationId
        self.projectName = projectName
        self.agentName = agentName
        self.harness = harness
        self.taskTitle = taskTitle
        self.taskStatus = taskStatus
        self.followUpQuestion = followUpQuestion
        self.summary = summary
        self.sourceTurnId = sourceTurnId
        self.sourceMachine = sourceMachine
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        operationId = try container.decode(String.self, forKey: .operationId)
        projectName = try container.decode(String.self, forKey: .projectName)
        agentName = try container.decodeIfPresent(String.self, forKey: .agentName)
        harness = try container.decodeIfPresent(String.self, forKey: .harness)
        taskTitle = try container.decodeIfPresent(String.self, forKey: .taskTitle)

        if let rawStatus = try container.decodeIfPresent(String.self, forKey: .taskStatus) {
            taskStatus = SwarmStatus(rawValue: rawStatus) ?? SwarmStatus(apiValue: rawStatus)
        } else {
            taskStatus = nil
        }

        followUpQuestion = try container.decodeIfPresent(String.self, forKey: .followUpQuestion)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        sourceTurnId = try container.decodeIfPresent(String.self, forKey: .sourceTurnId)
        sourceMachine = try container.decodeIfPresent(String.self, forKey: .sourceMachine)
    }
}

struct AgentRegistrationRequest: Codable, Sendable {
    var operationId: String?
    var agentName: String
    var harness: String
    var harnessAgentId: String?
    var harnessVersion: String?
    var skillVersion: String?
    var sourceMachine: String?
    var capabilities: [String]
    var status: SwarmStatus
    var summary: String?

    var actorDescription: String {
        [sourceMachine, harness, agentName]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: " / ")
    }

    enum CodingKeys: String, CodingKey {
        case operationId
        case agentName
        case harness
        case harnessAgentId
        case harnessVersion
        case skillVersion
        case sourceMachine
        case capabilities
        case status
        case summary
    }

    init(
        operationId: String? = nil,
        agentName: String,
        harness: String,
        harnessAgentId: String? = nil,
        harnessVersion: String? = nil,
        skillVersion: String? = nil,
        sourceMachine: String? = nil,
        capabilities: [String] = [],
        status: SwarmStatus = .healthy,
        summary: String? = nil
    ) {
        self.operationId = operationId
        self.agentName = agentName
        self.harness = harness
        self.harnessAgentId = harnessAgentId
        self.harnessVersion = harnessVersion
        self.skillVersion = skillVersion
        self.sourceMachine = sourceMachine
        self.capabilities = capabilities
        self.status = status
        self.summary = summary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        operationId = try container.decodeIfPresent(String.self, forKey: .operationId)
        agentName = try container.decode(String.self, forKey: .agentName)
        harness = try container.decode(String.self, forKey: .harness)
        harnessAgentId = try container.decodeIfPresent(String.self, forKey: .harnessAgentId)
        harnessVersion = try container.decodeIfPresent(String.self, forKey: .harnessVersion)
        skillVersion = try container.decodeIfPresent(String.self, forKey: .skillVersion)
        sourceMachine = try container.decodeIfPresent(String.self, forKey: .sourceMachine)
        capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities) ?? []
        summary = try container.decodeIfPresent(String.self, forKey: .summary)

        if let rawStatus = try container.decodeIfPresent(String.self, forKey: .status) {
            status = SwarmStatus(rawValue: rawStatus) ?? SwarmStatus(apiValue: rawStatus)
        } else {
            status = .healthy
        }
    }
}

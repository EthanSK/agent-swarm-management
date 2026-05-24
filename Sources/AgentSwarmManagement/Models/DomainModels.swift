import Foundation

enum SwarmStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case healthy
    case needsAttention
    case blocked
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .healthy: "Healthy"
        case .needsAttention: "Needs attention"
        case .blocked: "Blocked"
        case .done: "Done"
        }
    }

    var systemImage: String {
        switch self {
        case .healthy: "checkmark.circle"
        case .needsAttention: "exclamationmark.triangle"
        case .blocked: "xmark.octagon"
        case .done: "checkmark.seal"
        }
    }

    init(apiValue: String?) {
        let normalized = (apiValue ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "healthy", "running", "active", "open":
            self = .healthy
        case "needsattention", "needs attention", "attention", "waiting", "pending":
            self = .needsAttention
        case "blocked", "failed", "error":
            self = .blocked
        case "done", "complete", "completed", "closed":
            self = .done
        default:
            self = .needsAttention
        }
    }
}

struct SwarmProject: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var summary: String
    var status: SwarmStatus
    var activeAgentIds: [UUID]
    var openTaskCount: Int
    var followUpCount: Int
    var lastMeaningfulChange: Date
    var sourcePageId: String? = nil
    var lastUpdatedBy: String? = nil
}

struct SwarmAgent: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var harness: String
    var status: SwarmStatus
    var projectIds: [UUID]
    var lastUpdate: Date
    var harnessAgentId: String? = nil
    var harnessVersion: String? = nil
    var skillVersion: String? = nil
    var sourceMachine: String? = nil
    var lastHealthSummary: String? = nil
    var sourcePageId: String? = nil
    var lastUpdatedBy: String? = nil
}

struct SwarmTask: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var projectId: UUID
    var title: String
    var status: SwarmStatus
    var assignedAgentIds: [UUID]
    var parentTaskId: UUID?
    var sourcePageId: String?
    var sourceTurnId: String? = nil
    var lastUpdatedBy: String? = nil
}

struct FollowUp: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var projectId: UUID
    var agentId: UUID?
    var question: String
    var status: SwarmStatus
    var createdAt: Date
    var sourceTurnId: String?
    var sourcePageId: String? = nil
    var lastUpdatedBy: String? = nil
}

struct Artifact: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var projectId: UUID
    var title: String
    var url: URL?
    var kind: String
    var createdAt: Date
    var sourcePageId: String? = nil
    var lastUpdatedBy: String? = nil
}

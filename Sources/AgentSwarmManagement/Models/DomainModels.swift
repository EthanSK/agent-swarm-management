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
}

struct SwarmAgent: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var harness: String
    var status: SwarmStatus
    var projectIds: [UUID]
    var lastUpdate: Date
}

struct SwarmTask: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var projectId: UUID
    var title: String
    var status: SwarmStatus
    var assignedAgentIds: [UUID]
    var parentTaskId: UUID?
    var sourcePageId: String?
}

struct FollowUp: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var projectId: UUID
    var agentId: UUID?
    var question: String
    var status: SwarmStatus
    var createdAt: Date
    var sourceTurnId: String?
}

struct Artifact: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var projectId: UUID
    var title: String
    var url: URL?
    var kind: String
    var createdAt: Date
}


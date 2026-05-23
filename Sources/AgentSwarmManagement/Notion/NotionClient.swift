import Foundation

struct NotionClientConfiguration: Sendable {
    var tokenStorageDescription: String
    var notionVersion: String
}

struct NotionWorkspaceSnapshot: Sendable {
    var fetchedAt: Date
    var projects: [SwarmProject]
    var agents: [SwarmAgent]
    var tasks: [SwarmTask]
    var followUps: [FollowUp]
}

actor NotionClient {
    private let configuration: NotionClientConfiguration

    init(configuration: NotionClientConfiguration) {
        self.configuration = configuration
    }

    func fetchWorkspaceSnapshot() async throws -> NotionWorkspaceSnapshot {
        // Phase 2 will perform the actual Notion API pull here. This remains a
        // typed seam now so the UI, sync queue, and hook server can compile
        // against the same domain model before credentials exist.
        _ = configuration
        return NotionWorkspaceSnapshot(
            fetchedAt: .now,
            projects: [],
            agents: [],
            tasks: [],
            followUps: []
        )
    }
}


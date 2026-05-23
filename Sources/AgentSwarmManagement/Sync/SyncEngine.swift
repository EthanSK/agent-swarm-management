import Foundation

enum SyncIntent: Sendable {
    case upsertProject(SwarmProject)
    case upsertAgent(SwarmAgent)
    case upsertTask(SwarmTask)
    case upsertFollowUp(FollowUp)
}

struct SyncReport: Sendable {
    var appliedCount: Int
    var blockedCount: Int
    var lastError: String?
}

actor SyncEngine {
    private var queue: [SyncIntent] = []

    func enqueue(_ intent: SyncIntent) {
        // Agent hooks can be chatty. Queueing first gives us one place to
        // coalesce duplicate turn updates and respect Notion rate limits.
        queue.append(intent)
    }

    func drain(using client: NotionClient) async -> SyncReport {
        // Phase 2 will apply intents through NotionClient with Retry-After
        // handling. For the scaffold, keep the method side-effect free.
        _ = client
        let applied = queue.count
        queue.removeAll()
        return SyncReport(appliedCount: applied, blockedCount: 0, lastError: nil)
    }
}


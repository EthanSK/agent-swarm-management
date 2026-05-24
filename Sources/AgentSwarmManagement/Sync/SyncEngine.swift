import Foundation

struct SyncReport: Sendable {
    var appliedCount: Int
    var blockedCount: Int
    var lastError: String?
}

actor SyncEngine {
    private var nextAllowedRequestAt: Date = .distantPast
    private let minimumRequestSpacing: TimeInterval

    init(minimumRequestSpacing: TimeInterval = 1.0) {
        self.minimumRequestSpacing = minimumRequestSpacing
    }

    func apply(
        operation: PendingSyncOperation,
        state: WorkspaceState,
        settings: AppSettings,
        client: NotionClient
    ) async throws -> String? {
        try await waitForNotionSlot()

        do {
            return try await applyWithoutRetry(
                operation: operation,
                state: state,
                settings: settings,
                client: client
            )
        } catch NotionAPIError.rateLimited(let seconds) {
            // The Notion API provides Retry-After on 429. Persisting the failure
            // to the outbox lets the UI show the blocked operation instead of
            // silently spinning or losing the user/agent update.
            nextAllowedRequestAt = Date().addingTimeInterval(seconds)
            throw NotionAPIError.rateLimited(seconds: seconds)
        }
    }

    private func applyWithoutRetry(
        operation: PendingSyncOperation,
        state: WorkspaceState,
        settings: AppSettings,
        client: NotionClient
    ) async throws -> String? {
        switch operation.mutation {
        case .delete:
            if let pageId = operation.notionPageId {
                try await client.trashPage(pageId)
            }
            return nil
        case .upsert:
            switch operation.kind {
            case .project:
                guard let project = state.projects.first(where: { $0.id == operation.localRecordId }) else { return nil }
                return try await client.upsertProject(project, settings: settings)
            case .agent:
                guard let agent = state.agents.first(where: { $0.id == operation.localRecordId }) else { return nil }
                return try await client.upsertAgent(agent, settings: settings)
            case .task:
                guard let task = state.tasks.first(where: { $0.id == operation.localRecordId }) else { return nil }
                return try await client.upsertTask(task, settings: settings)
            case .followUp:
                guard let followUp = state.followUps.first(where: { $0.id == operation.localRecordId }) else { return nil }
                return try await client.upsertFollowUp(followUp, settings: settings)
            case .artifact:
                // Artifacts are part of the data model now, but the first real
                // Notion write path focuses on projects, agents, tasks, and
                // follow-ups because those are the app's operational core.
                return nil
            }
        }
    }

    private func waitForNotionSlot() async throws {
        let now = Date()
        if nextAllowedRequestAt > now {
            let delay = nextAllowedRequestAt.timeIntervalSince(now)
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        nextAllowedRequestAt = Date().addingTimeInterval(minimumRequestSpacing)
    }
}


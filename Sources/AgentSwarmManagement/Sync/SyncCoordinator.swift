import Combine
import Foundation

@MainActor
final class SyncCoordinator: ObservableObject {
    @Published private(set) var isWorking = false
    @Published private(set) var statusLine = "Notion sync not configured"
    @Published private(set) var lastError: String?
    @Published private(set) var notionCredentialStatus = "Not connected"

    private let tokenStore: KeychainTokenStore
    private let syncEngine: SyncEngine

    init(tokenStore: KeychainTokenStore = KeychainTokenStore(), syncEngine: SyncEngine = SyncEngine()) {
        self.tokenStore = tokenStore
        self.syncEngine = syncEngine
    }

    func saveNotionToken(_ token: String) {
        do {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                try tokenStore.delete(.notionAPI)
                statusLine = "Notion token removed"
                notionCredentialStatus = "Not connected"
            } else {
                try tokenStore.save(trimmed, account: .notionAPI)
                statusLine = "Notion token saved in Keychain"
                notionCredentialStatus = "Saved in Keychain"
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            statusLine = "Could not update Notion token"
        }
    }

    func createWorkspaceSchema(in store: WorkspaceStore) async {
        guard !store.settings.notionRootPage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusLine = "Add the Agent Swarm Management parent page first"
            return
        }

        await run("Creating Notion data sources") {
            let client = try notionClient(settings: store.settings)
            let schema = try await client.createSchema(rootPage: store.settings.notionRootPage)
            store.recordSchema(schema)
            statusLine = "Created Notion data sources under the parent page"
        }
    }

    func pullNow(into store: WorkspaceStore) async {
        await run("Pulling from Notion") {
            let client = try notionClient(settings: store.settings)
            let snapshot = try await client.fetchWorkspaceSnapshot(settings: store.settings)
            store.applyRemoteSnapshot(snapshot)
            statusLine = "Pulled \(snapshot.projects.count) projects, \(snapshot.agents.count) agents, \(snapshot.tasks.count) tasks, and \(snapshot.followUps.count) follow-ups"
        }
    }

    func pushPending(from store: WorkspaceStore) async {
        guard !store.settings.writesPaused else {
            statusLine = "Notion writes are paused"
            return
        }

        await run("Pushing pending Notion writes") {
            let client = try notionClient(settings: store.settings)
            var applied = 0
            var blocked = 0

            for operation in store.pendingOperations {
                do {
                    let state = store.syncSnapshot()
                    let pageId = try await syncEngine.apply(
                        operation: operation,
                        state: state,
                        settings: store.settings,
                        client: client
                    )
                    store.confirmSync(operation: operation, notionPageId: pageId)
                    applied += 1
                } catch {
                    store.markSyncFailed(operation: operation, error: error.localizedDescription)
                    blocked += 1

                    // Stop after the first blocked operation so ordering stays
                    // predictable and Notion's Retry-After window is respected.
                    break
                }
            }

            if blocked == 0 {
                statusLine = "Pushed \(applied) pending Notion operation\(applied == 1 ? "" : "s")"
            } else {
                statusLine = "Pushed \(applied); blocked \(blocked) pending operation"
            }
        }
    }

    private func run(_ label: String, operation: () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        statusLine = label
        lastError = nil

        do {
            try await operation()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            statusLine = error.localizedDescription
        }

        isWorking = false
    }

    private func notionClient(settings: AppSettings) throws -> NotionClient {
        guard let token = try tokenStore.read(.notionAPI), !token.isEmpty else {
            notionCredentialStatus = "Not connected"
            throw NotionAPIError.missingToken
        }
        notionCredentialStatus = "Saved in Keychain"

        return NotionClient(
            configuration: NotionClientConfiguration(
                apiToken: token,
                notionVersion: settings.notionVersion
            )
        )
    }
}

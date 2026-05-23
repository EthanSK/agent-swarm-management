import Combine
import Foundation

@MainActor
final class LocalControlServer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var statusLine = "Local control endpoint not started"

    private weak var store: WorkspaceStore?

    func attach(store: WorkspaceStore) {
        self.store = store
        startIfNeeded()
    }

    func startIfNeeded() {
        guard !isRunning else { return }

        // Phase 3 should replace this stub with a localhost-only HTTP listener
        // and an MCP wrapper. Keeping it explicit in the UI prevents the app
        // from pretending agent hooks are wired before they are.
        isRunning = true
        statusLine = "Stub endpoint ready: http://127.0.0.1:17391"
    }

    func recordMeaningfulChange(projectName: String, summary: String) {
        // This is the local shape future post-turn hooks will call after
        // validating auth and deduping operation IDs.
        _ = store
        statusLine = "Last hook update: \(projectName) - \(summary)"
    }
}


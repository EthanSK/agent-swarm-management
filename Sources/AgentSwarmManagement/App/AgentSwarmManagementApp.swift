import SwiftUI

@main
struct AgentSwarmManagementApp: App {
    @StateObject private var store = WorkspaceStore.sample()
    @StateObject private var controlServer = LocalControlServer()
    @StateObject private var syncCoordinator = SyncCoordinator()

    private let tokenStore = KeychainTokenStore()

    var body: some Scene {
        WindowGroup("Agent Swarm Management") {
            RootView(store: store)
                .task {
                    await store.bootstrap()
                    startLocalControlServer()
                }
        }

        MenuBarExtra("Agent Swarm", systemImage: "circle.hexagongrid") {
            MenuBarView(store: store, controlServer: controlServer)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store, controlServer: controlServer, syncCoordinator: syncCoordinator)
        }
    }

    private func startLocalControlServer() {
        do {
            let token = try tokenStore.ensureLocalControlToken()
            controlServer.attach(store: store, token: token, port: store.settings.localServerPort)
        } catch {
            controlServer.stop()
        }
    }
}

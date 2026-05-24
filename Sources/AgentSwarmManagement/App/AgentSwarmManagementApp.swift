import SwiftUI

@main
struct AgentSwarmManagementApp: App {
    @StateObject private var store: WorkspaceStore
    @StateObject private var controlServer: LocalControlServer
    @StateObject private var syncCoordinator: SyncCoordinator
    @StateObject private var appUpdater: AppUpdater

    private let tokenStore: KeychainTokenStore

    init() {
        let store = WorkspaceStore.sample()
        let controlServer = LocalControlServer()
        let tokenStore = KeychainTokenStore()

        _store = StateObject(wrappedValue: store)
        _controlServer = StateObject(wrappedValue: controlServer)
        _syncCoordinator = StateObject(wrappedValue: SyncCoordinator())
        _appUpdater = StateObject(wrappedValue: AppUpdater())
        self.tokenStore = tokenStore

        let launchToken = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        controlServer.attach(store: store, token: launchToken, port: AppSettings.defaults.localServerPort)

        // Start the cache and localhost endpoint at application launch, not
        // only when a SwiftUI view task happens to run. Packaged apps can be
        // launched headlessly by hooks or login items, and agents still need
        // the endpoint in that state.
        Task { @MainActor in
            await store.bootstrap()
            let durableToken = (try? tokenStore.ensureLocalControlToken()) ?? launchToken
            controlServer.attach(store: store, token: durableToken, port: store.settings.localServerPort)
        }
    }

    var body: some Scene {
        WindowGroup("Agent Swarm Management") {
            RootView(store: store)
        }

        MenuBarExtra("Agent Swarm", systemImage: "circle.hexagongrid") {
            MenuBarView(store: store, controlServer: controlServer)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                store: store,
                controlServer: controlServer,
                syncCoordinator: syncCoordinator,
                appUpdater: appUpdater
            )
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    appUpdater.checkForUpdates()
                }
                .disabled(!appUpdater.canCheckForUpdates)
            }
        }
    }

    private func startLocalControlServer() {
        let token = (try? tokenStore.ensureLocalControlToken())
            ?? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        controlServer.attach(store: store, token: token, port: store.settings.localServerPort)
    }
}

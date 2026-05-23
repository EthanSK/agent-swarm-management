import SwiftUI

@main
struct AgentSwarmManagementApp: App {
    @StateObject private var store = WorkspaceStore.sample()
    @StateObject private var controlServer = LocalControlServer()

    var body: some Scene {
        WindowGroup("Agent Swarm Management") {
            RootView(store: store)
                .task {
                    // The app starts with sample data while Notion sync is being wired.
                    // Keeping bootstrap explicit makes it easier for post-turn hooks to
                    // attach later without hiding network work in view initializers.
                    controlServer.attach(store: store)
                    await store.bootstrap()
                }
        }

        MenuBarExtra("Agent Swarm", systemImage: "circle.hexagongrid") {
            MenuBarView(store: store, controlServer: controlServer)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store, controlServer: controlServer)
        }
    }
}


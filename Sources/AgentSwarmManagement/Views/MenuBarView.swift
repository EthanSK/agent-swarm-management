import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var controlServer: LocalControlServer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Agent Swarm Management")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Label("Projects", systemImage: "folder")
                    Text("\(store.activeProjectCount)")
                }
                GridRow {
                    Label("Agents", systemImage: "person.2")
                    Text("\(store.runningAgentCount)")
                }
                GridRow {
                    Label("Follow-ups", systemImage: "questionmark.bubble")
                    Text("\(store.openFollowUpCount)")
                }
                GridRow {
                    Label("Blocked", systemImage: "xmark.octagon")
                    Text("\(store.blockedTaskCount)")
                }
            }

            Divider()

            Label(controlServer.statusLine, systemImage: controlServer.isRunning ? "network" : "wifi.slash")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let error = store.lastPersistenceError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(width: 320)
    }
}

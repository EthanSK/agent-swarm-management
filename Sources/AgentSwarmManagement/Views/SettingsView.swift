import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var controlServer: LocalControlServer

    var body: some View {
        Form {
            Section("Notion") {
                Text("Notion auth will use Keychain-backed local tokens for dev and a brokered OAuth flow for public distribution.")
                    .foregroundStyle(.secondary)
            }

            Section("Agent control surface") {
                Text(controlServer.statusLine)
                Text("Phase 3 will replace the stub with a localhost HTTP endpoint and MCP wrapper.")
                    .foregroundStyle(.secondary)
            }

            Section("Local cache") {
                Text(store.persistenceURL.path)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)

                if let error = store.lastPersistenceError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                } else {
                    Label("Saved locally as JSON", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(width: 560)
    }
}

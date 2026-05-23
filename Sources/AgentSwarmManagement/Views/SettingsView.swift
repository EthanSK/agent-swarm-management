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
        }
        .padding()
        .frame(width: 560)
    }
}


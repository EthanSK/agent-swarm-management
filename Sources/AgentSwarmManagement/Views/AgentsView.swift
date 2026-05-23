import SwiftUI

struct AgentsView: View {
    @ObservedObject var store: WorkspaceStore

    var body: some View {
        List(store.agents) { agent in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(agent.name)
                        .font(.headline)
                    Spacer()
                    StatusBadge(status: agent.status)
                }

                Text(agent.harness)
                    .foregroundStyle(.secondary)

                Label("\(agent.projectIds.count) active projects", systemImage: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
        .navigationTitle("Agents")
    }
}


import SwiftUI

struct AgentsView: View {
    @ObservedObject var store: WorkspaceStore
    @State private var isCreatingAgent = false
    @State private var editingAgent: SwarmAgent?

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
            .contentShape(Rectangle())
            .contextMenu {
                Button {
                    editingAgent = agent
                } label: {
                    Label("Edit Agent", systemImage: "pencil")
                }

                Divider()

                Button(role: .destructive) {
                    store.deleteAgent(agent)
                } label: {
                    Label("Delete Agent", systemImage: "trash")
                }
            }
            .onTapGesture(count: 2) {
                editingAgent = agent
            }
        }
        .navigationTitle("Agents")
        .overlay {
            if store.agents.isEmpty {
                ContentUnavailableView("No agents", systemImage: "person.2.badge.plus", description: Text("Add Codex, Claude Code, OpenClaw, or any other worker you want to track."))
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    isCreatingAgent = true
                } label: {
                    Label("New Agent", systemImage: "plus")
                }
                .help("New Agent")
            }
        }
        .sheet(isPresented: $isCreatingAgent) {
            AgentEditorView(projects: store.projects) { agent in
                store.upsertAgent(agent)
            }
        }
        .sheet(item: $editingAgent) { agent in
            AgentEditorView(agent: agent, projects: store.projects) { updatedAgent in
                store.upsertAgent(updatedAgent)
            }
        }
    }
}

import SwiftUI

struct FollowUpsView: View {
    @ObservedObject var store: WorkspaceStore
    @State private var isCreatingFollowUp = false
    @State private var editingFollowUp: FollowUp?

    var body: some View {
        List(store.followUps) { followUp in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(followUp.question)
                        .font(.headline)
                    Spacer()
                    StatusBadge(status: followUp.status)
                }

                Text(contextLine(for: followUp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .contextMenu {
                Button {
                    editingFollowUp = followUp
                } label: {
                    Label("Edit Follow-up", systemImage: "pencil")
                }

                Menu("Set Status") {
                    ForEach(SwarmStatus.allCases) { status in
                        Button(status.title) {
                            store.setFollowUpStatus(followUp, status: status)
                        }
                    }
                }

                Divider()

                Button(role: .destructive) {
                    store.deleteFollowUp(followUp)
                } label: {
                    Label("Delete Follow-up", systemImage: "trash")
                }
            }
            .onTapGesture(count: 2) {
                editingFollowUp = followUp
            }
        }
        .navigationTitle("Follow-ups")
        .overlay {
            if store.followUps.isEmpty {
                ContentUnavailableView("No follow-ups", systemImage: "questionmark.bubble", description: Text("Questions, approvals, and decisions waiting on Ethan will appear here."))
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    isCreatingFollowUp = true
                } label: {
                    Label("New Follow-up", systemImage: "plus")
                }
                .help("New Follow-up")
            }
        }
        .sheet(isPresented: $isCreatingFollowUp) {
            FollowUpEditorView(projects: store.projects, agents: store.agents) { followUp in
                store.upsertFollowUp(followUp)
            }
        }
        .sheet(item: $editingFollowUp) { followUp in
            FollowUpEditorView(followUp: followUp, projects: store.projects, agents: store.agents) { updatedFollowUp in
                store.upsertFollowUp(updatedFollowUp)
            }
        }
    }

    private func contextLine(for followUp: FollowUp) -> String {
        let project = store.projectName(for: followUp.projectId)
        let agent = followUp.agentId.map { store.agentName(for: $0) } ?? "No agent"

        return "\(project) / \(agent)"
    }
}

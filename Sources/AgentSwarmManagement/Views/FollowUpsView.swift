import SwiftUI

struct FollowUpsView: View {
    @ObservedObject var store: WorkspaceStore

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
        }
        .navigationTitle("Follow-ups")
    }

    private func contextLine(for followUp: FollowUp) -> String {
        let project = store.projects.first { $0.id == followUp.projectId }?.name ?? "Unknown project"
        let agent = followUp.agentId.flatMap { id in
            store.agents.first { $0.id == id }?.name
        } ?? "No agent"

        return "\(project) / \(agent)"
    }
}


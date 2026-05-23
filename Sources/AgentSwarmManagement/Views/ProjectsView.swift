import SwiftUI

struct ProjectsView: View {
    @ObservedObject var store: WorkspaceStore

    var body: some View {
        List(store.projects) { project in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(project.name)
                        .font(.headline)
                    Spacer()
                    StatusBadge(status: project.status)
                }

                Text(project.summary)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    Label("\(store.agents(for: project).count) agents", systemImage: "person.2")
                    Label("\(project.openTaskCount) open tasks", systemImage: "checklist")
                    Label("\(project.followUpCount) follow-ups", systemImage: "questionmark.bubble")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
        .navigationTitle("Projects")
    }
}


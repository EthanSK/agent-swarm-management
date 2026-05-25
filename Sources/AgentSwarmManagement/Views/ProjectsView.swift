import SwiftUI

struct ProjectsView: View {
    @ObservedObject var store: WorkspaceStore

    var body: some View {
        // Projects are created by reported agent work rather than a primary manual
        // form, which keeps the app centered on agent-state collection.
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
                    Label(project.lastMeaningfulChange.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .navigationTitle("Projects")
        .overlay {
            if store.projects.isEmpty {
                ContentUnavailableView(
                    "No projects yet",
                    systemImage: "folder.badge.gearshape",
                    description: Text("Projects appear when registered agents report real work.")
                )
            }
        }
    }
}

import SwiftUI

struct TasksView: View {
    @ObservedObject var store: WorkspaceStore

    var body: some View {
        List(store.tasks) { task in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(task.title)
                        .font(.headline)
                    Spacer()
                    StatusBadge(status: task.status)
                }

                Text(projectName(for: task))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
        .navigationTitle("Tasks")
    }

    private func projectName(for task: SwarmTask) -> String {
        store.projects.first { $0.id == task.projectId }?.name ?? "Unknown project"
    }
}


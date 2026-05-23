import SwiftUI

struct TasksView: View {
    @ObservedObject var store: WorkspaceStore
    @State private var isCreatingTask = false
    @State private var editingTask: SwarmTask?

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
            .contentShape(Rectangle())
            .contextMenu {
                Button {
                    editingTask = task
                } label: {
                    Label("Edit Task", systemImage: "pencil")
                }

                Menu("Set Status") {
                    ForEach(SwarmStatus.allCases) { status in
                        Button(status.title) {
                            store.setTaskStatus(task, status: status)
                        }
                    }
                }

                Divider()

                Button(role: .destructive) {
                    store.deleteTask(task)
                } label: {
                    Label("Delete Task", systemImage: "trash")
                }
            }
            .onTapGesture(count: 2) {
                editingTask = task
            }
        }
        .navigationTitle("Tasks")
        .overlay {
            if store.tasks.isEmpty {
                ContentUnavailableView("No tasks", systemImage: "checklist", description: Text("Create tasks manually now; agent hooks can write into the same model later."))
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    isCreatingTask = true
                } label: {
                    Label("New Task", systemImage: "plus")
                }
                .help("New Task")
            }
        }
        .sheet(isPresented: $isCreatingTask) {
            TaskEditorView(projects: store.projects, agents: store.agents) { task in
                store.upsertTask(task)
            }
        }
        .sheet(item: $editingTask) { task in
            TaskEditorView(task: task, projects: store.projects, agents: store.agents) { updatedTask in
                store.upsertTask(updatedTask)
            }
        }
    }

    private func projectName(for task: SwarmTask) -> String {
        store.projectName(for: task.projectId)
    }
}

import SwiftUI

struct ProjectsView: View {
    @ObservedObject var store: WorkspaceStore
    @State private var isCreatingProject = false
    @State private var editingProject: SwarmProject?

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
                    Label(project.lastMeaningfulChange.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .contextMenu {
                Button {
                    editingProject = project
                } label: {
                    Label("Edit Project", systemImage: "pencil")
                }

                Divider()

                Button(role: .destructive) {
                    store.deleteProject(project)
                } label: {
                    Label("Delete Project", systemImage: "trash")
                }
            }
            .onTapGesture(count: 2) {
                editingProject = project
            }
        }
        .navigationTitle("Projects")
        .overlay {
            if store.projects.isEmpty {
                ContentUnavailableView("No projects", systemImage: "folder.badge.plus", description: Text("Create the first swarm project to begin tracking agents, tasks, and follow-ups."))
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    isCreatingProject = true
                } label: {
                    Label("New Project", systemImage: "plus")
                }
                .help("New Project")
            }
        }
        .sheet(isPresented: $isCreatingProject) {
            ProjectEditorView(agents: store.agents) { project in
                store.upsertProject(project)
            }
        }
        .sheet(item: $editingProject) { project in
            ProjectEditorView(project: project, agents: store.agents) { updatedProject in
                store.upsertProject(updatedProject)
            }
        }
    }
}

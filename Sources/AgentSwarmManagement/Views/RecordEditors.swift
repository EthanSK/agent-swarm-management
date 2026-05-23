import SwiftUI

struct ProjectEditorView: View {
    @Environment(\.dismiss) private var dismiss

    private let project: SwarmProject?
    private let agents: [SwarmAgent]
    private let onSave: (SwarmProject) -> Void

    @State private var name: String
    @State private var summary: String
    @State private var status: SwarmStatus
    @State private var activeAgentIds: [UUID]

    init(project: SwarmProject? = nil, agents: [SwarmAgent], onSave: @escaping (SwarmProject) -> Void) {
        self.project = project
        self.agents = agents
        self.onSave = onSave
        _name = State(initialValue: project?.name ?? "")
        _summary = State(initialValue: project?.summary ?? "")
        _status = State(initialValue: project?.status ?? .healthy)
        _activeAgentIds = State(initialValue: project?.activeAgentIds ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Project") {
                    TextField("Name", text: $name)
                    TextField("Summary", text: $summary, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                    StatusPicker(selection: $status)
                }

                Section("Active agents") {
                    if agents.isEmpty {
                        Text("Add an agent before linking project ownership.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(agents) { agent in
                            Toggle(agent.name, isOn: selectionBinding(for: agent.id, in: $activeAgentIds))
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(project == nil ? "New Project" : "Edit Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
        .frame(width: 540, height: 460)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        var next = project ?? SwarmProject(
            id: UUID(),
            name: "",
            summary: "",
            status: .healthy,
            activeAgentIds: [],
            openTaskCount: 0,
            followUpCount: 0,
            lastMeaningfulChange: .now
        )

        next.name = trimmedName
        next.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        next.status = status
        next.activeAgentIds = activeAgentIds
        next.lastMeaningfulChange = .now
        onSave(next)
        dismiss()
    }
}

struct AgentEditorView: View {
    @Environment(\.dismiss) private var dismiss

    private let agent: SwarmAgent?
    private let projects: [SwarmProject]
    private let onSave: (SwarmAgent) -> Void

    @State private var name: String
    @State private var harness: String
    @State private var status: SwarmStatus
    @State private var projectIds: [UUID]

    init(agent: SwarmAgent? = nil, projects: [SwarmProject], onSave: @escaping (SwarmAgent) -> Void) {
        self.agent = agent
        self.projects = projects
        self.onSave = onSave
        _name = State(initialValue: agent?.name ?? "")
        _harness = State(initialValue: agent?.harness ?? "")
        _status = State(initialValue: agent?.status ?? .healthy)
        _projectIds = State(initialValue: agent?.projectIds ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Agent") {
                    TextField("Name", text: $name)
                    TextField("Harness", text: $harness)
                    StatusPicker(selection: $status)
                }

                Section("Projects") {
                    if projects.isEmpty {
                        Text("Create a project before assigning this agent.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(projects) { project in
                            Toggle(project.name, isOn: selectionBinding(for: project.id, in: $projectIds))
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(agent == nil ? "New Agent" : "Edit Agent")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
        .frame(width: 520, height: 420)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        var next = agent ?? SwarmAgent(
            id: UUID(),
            name: "",
            harness: "",
            status: .healthy,
            projectIds: [],
            lastUpdate: .now
        )

        next.name = trimmedName
        next.harness = harness.trimmingCharacters(in: .whitespacesAndNewlines)
        next.status = status
        next.projectIds = projectIds
        next.lastUpdate = .now
        onSave(next)
        dismiss()
    }
}

struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss

    private let task: SwarmTask?
    private let projects: [SwarmProject]
    private let agents: [SwarmAgent]
    private let onSave: (SwarmTask) -> Void

    @State private var title: String
    @State private var status: SwarmStatus
    @State private var projectId: UUID?
    @State private var assignedAgentIds: [UUID]
    @State private var sourcePageId: String

    init(
        task: SwarmTask? = nil,
        projects: [SwarmProject],
        agents: [SwarmAgent],
        onSave: @escaping (SwarmTask) -> Void
    ) {
        self.task = task
        self.projects = projects
        self.agents = agents
        self.onSave = onSave
        _title = State(initialValue: task?.title ?? "")
        _status = State(initialValue: task?.status ?? .healthy)
        _projectId = State(initialValue: task?.projectId ?? projects.first?.id)
        _assignedAgentIds = State(initialValue: task?.assignedAgentIds ?? [])
        _sourcePageId = State(initialValue: task?.sourcePageId ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Title", text: $title, axis: .vertical)
                        .lineLimit(2, reservesSpace: true)
                    StatusPicker(selection: $status)
                    ProjectPicker(projects: projects, selection: $projectId)
                    TextField("Notion page ID", text: $sourcePageId)
                }

                Section("Assigned agents") {
                    if agents.isEmpty {
                        Text("No agents exist yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(agents) { agent in
                            Toggle(agent.name, isOn: selectionBinding(for: agent.id, in: $assignedAgentIds))
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(task == nil ? "New Task" : "Edit Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmedTitle.isEmpty || projectId == nil)
                }
            }
        }
        .frame(width: 560, height: 500)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard let projectId else { return }

        var next = task ?? SwarmTask(
            id: UUID(),
            projectId: projectId,
            title: "",
            status: .healthy,
            assignedAgentIds: [],
            parentTaskId: nil,
            sourcePageId: nil
        )

        next.projectId = projectId
        next.title = trimmedTitle
        next.status = status
        next.assignedAgentIds = assignedAgentIds
        let trimmedSource = sourcePageId.trimmingCharacters(in: .whitespacesAndNewlines)
        next.sourcePageId = trimmedSource.isEmpty ? nil : trimmedSource
        onSave(next)
        dismiss()
    }
}

struct FollowUpEditorView: View {
    @Environment(\.dismiss) private var dismiss

    private let followUp: FollowUp?
    private let projects: [SwarmProject]
    private let agents: [SwarmAgent]
    private let onSave: (FollowUp) -> Void

    @State private var question: String
    @State private var status: SwarmStatus
    @State private var projectId: UUID?
    @State private var agentId: UUID?
    @State private var sourceTurnId: String

    init(
        followUp: FollowUp? = nil,
        projects: [SwarmProject],
        agents: [SwarmAgent],
        onSave: @escaping (FollowUp) -> Void
    ) {
        self.followUp = followUp
        self.projects = projects
        self.agents = agents
        self.onSave = onSave
        _question = State(initialValue: followUp?.question ?? "")
        _status = State(initialValue: followUp?.status ?? .needsAttention)
        _projectId = State(initialValue: followUp?.projectId ?? projects.first?.id)
        _agentId = State(initialValue: followUp?.agentId)
        _sourceTurnId = State(initialValue: followUp?.sourceTurnId ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Follow-up") {
                    TextField("Question or decision", text: $question, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                    StatusPicker(selection: $status)
                    ProjectPicker(projects: projects, selection: $projectId)
                    AgentPicker(agents: agents, selection: $agentId)
                    TextField("Source turn ID", text: $sourceTurnId)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(followUp == nil ? "New Follow-up" : "Edit Follow-up")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmedQuestion.isEmpty || projectId == nil)
                }
            }
        }
        .frame(width: 560, height: 430)
    }

    private var trimmedQuestion: String {
        question.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard let projectId else { return }

        var next = followUp ?? FollowUp(
            id: UUID(),
            projectId: projectId,
            agentId: nil,
            question: "",
            status: .needsAttention,
            createdAt: .now,
            sourceTurnId: nil
        )

        next.projectId = projectId
        next.agentId = agentId
        next.question = trimmedQuestion
        next.status = status
        let trimmedSource = sourceTurnId.trimmingCharacters(in: .whitespacesAndNewlines)
        next.sourceTurnId = trimmedSource.isEmpty ? nil : trimmedSource
        onSave(next)
        dismiss()
    }
}

struct StatusPicker: View {
    @Binding var selection: SwarmStatus

    var body: some View {
        Picker("Status", selection: $selection) {
            ForEach(SwarmStatus.allCases) { status in
                Label(status.title, systemImage: status.systemImage)
                    .tag(status)
            }
        }
    }
}

private struct ProjectPicker: View {
    let projects: [SwarmProject]
    @Binding var selection: UUID?

    var body: some View {
        Picker("Project", selection: $selection) {
            if projects.isEmpty {
                Text("No projects").tag(Optional<UUID>.none)
            } else {
                ForEach(projects) { project in
                    Text(project.name).tag(Optional(project.id))
                }
            }
        }
    }
}

private struct AgentPicker: View {
    let agents: [SwarmAgent]
    @Binding var selection: UUID?

    var body: some View {
        Picker("Agent", selection: $selection) {
            Text("No agent").tag(Optional<UUID>.none)
            ForEach(agents) { agent in
                Text(agent.name).tag(Optional(agent.id))
            }
        }
    }
}

private func selectionBinding(for id: UUID, in selection: Binding<[UUID]>) -> Binding<Bool> {
    Binding {
        selection.wrappedValue.contains(id)
    } set: { isSelected in
        if isSelected {
            if !selection.wrappedValue.contains(id) {
                selection.wrappedValue.append(id)
            }
        } else {
            selection.wrappedValue.removeAll { $0 == id }
        }
    }
}

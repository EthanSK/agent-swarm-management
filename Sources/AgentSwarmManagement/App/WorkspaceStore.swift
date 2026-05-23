import Combine
import Foundation

struct WorkspaceState: Codable, Sendable {
    var projects: [SwarmProject]
    var agents: [SwarmAgent]
    var tasks: [SwarmTask]
    var followUps: [FollowUp]
    var artifacts: [Artifact]
}

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var projects: [SwarmProject]
    @Published var agents: [SwarmAgent]
    @Published var tasks: [SwarmTask]
    @Published var followUps: [FollowUp]
    @Published var artifacts: [Artifact]
    @Published private(set) var persistenceURL: URL
    @Published private(set) var lastPersistenceError: String?

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        projects: [SwarmProject] = [],
        agents: [SwarmAgent] = [],
        tasks: [SwarmTask] = [],
        followUps: [FollowUp] = [],
        artifacts: [Artifact] = [],
        persistenceURL: URL = WorkspaceStore.defaultPersistenceURL()
    ) {
        self.projects = projects
        self.agents = agents
        self.tasks = tasks
        self.followUps = followUps
        self.artifacts = artifacts
        self.persistenceURL = persistenceURL

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func bootstrap() async {
        do {
            if FileManager.default.fileExists(atPath: persistenceURL.path) {
                let data = try Data(contentsOf: persistenceURL)
                apply(try decoder.decode(WorkspaceState.self, from: data))
            } else {
                // The first launch starts with the recovered Agent Swarm project,
                // then persists it so later UI edits are local-first and durable.
                recomputeProjectCounters()
                try persist()
            }
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = error.localizedDescription
        }
    }

    var activeProjectCount: Int {
        projects.filter { $0.status != .done }.count
    }

    var runningAgentCount: Int {
        agents.filter { $0.status == .healthy || $0.status == .needsAttention }.count
    }

    var openFollowUpCount: Int {
        followUps.filter { $0.status != .done }.count
    }

    var blockedTaskCount: Int {
        tasks.filter { $0.status == .blocked }.count
    }

    func agents(for project: SwarmProject) -> [SwarmAgent] {
        agents.filter { project.activeAgentIds.contains($0.id) }
    }

    func tasks(for project: SwarmProject) -> [SwarmTask] {
        tasks.filter { $0.projectId == project.id }
    }

    func projectName(for id: UUID) -> String {
        projects.first { $0.id == id }?.name ?? "Unknown project"
    }

    func agentName(for id: UUID) -> String {
        agents.first { $0.id == id }?.name ?? "Unknown agent"
    }

    func openTaskCount(for projectId: UUID) -> Int {
        tasks.filter { $0.projectId == projectId && $0.status != .done }.count
    }

    func openFollowUpCount(for projectId: UUID) -> Int {
        followUps.filter { $0.projectId == projectId && $0.status != .done }.count
    }

    func upsertProject(_ project: SwarmProject) {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        } else {
            projects.append(project)
        }

        syncProjectAgentEdges(projectId: project.id, selectedAgentIds: project.activeAgentIds)
        recomputeProjectCounters()
        save()
    }

    func deleteProject(_ project: SwarmProject) {
        projects.removeAll { $0.id == project.id }
        tasks.removeAll { $0.projectId == project.id }
        followUps.removeAll { $0.projectId == project.id }
        artifacts.removeAll { $0.projectId == project.id }

        for index in agents.indices {
            agents[index].projectIds.removeAll { $0 == project.id }
        }

        save()
    }

    func upsertAgent(_ agent: SwarmAgent) {
        if let index = agents.firstIndex(where: { $0.id == agent.id }) {
            agents[index] = agent
        } else {
            agents.append(agent)
        }

        syncAgentProjectEdges(agentId: agent.id, selectedProjectIds: agent.projectIds)
        recomputeProjectCounters()
        save()
    }

    func deleteAgent(_ agent: SwarmAgent) {
        agents.removeAll { $0.id == agent.id }

        for index in projects.indices {
            projects[index].activeAgentIds.removeAll { $0 == agent.id }
        }

        for index in tasks.indices {
            tasks[index].assignedAgentIds.removeAll { $0 == agent.id }
        }

        for index in followUps.indices where followUps[index].agentId == agent.id {
            followUps[index].agentId = nil
        }

        recomputeProjectCounters()
        save()
    }

    func upsertTask(_ task: SwarmTask) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }

        touch(projectId: task.projectId)
        attachAgents(task.assignedAgentIds, toProjectId: task.projectId)
        recomputeProjectCounters()
        save()
    }

    func deleteTask(_ task: SwarmTask) {
        tasks.removeAll { $0.id == task.id }
        touch(projectId: task.projectId)
        recomputeProjectCounters()
        save()
    }

    func setTaskStatus(_ task: SwarmTask, status: SwarmStatus) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].status = status
        touch(projectId: task.projectId)
        recomputeProjectCounters()
        save()
    }

    func upsertFollowUp(_ followUp: FollowUp) {
        if let index = followUps.firstIndex(where: { $0.id == followUp.id }) {
            followUps[index] = followUp
        } else {
            followUps.append(followUp)
        }

        touch(projectId: followUp.projectId)
        if let agentId = followUp.agentId {
            attachAgents([agentId], toProjectId: followUp.projectId)
        }
        recomputeProjectCounters()
        save()
    }

    func deleteFollowUp(_ followUp: FollowUp) {
        followUps.removeAll { $0.id == followUp.id }
        touch(projectId: followUp.projectId)
        recomputeProjectCounters()
        save()
    }

    func setFollowUpStatus(_ followUp: FollowUp, status: SwarmStatus) {
        guard let index = followUps.firstIndex(where: { $0.id == followUp.id }) else { return }
        followUps[index].status = status
        touch(projectId: followUp.projectId)
        recomputeProjectCounters()
        save()
    }

    func save() {
        do {
            try persist()
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = error.localizedDescription
        }
    }

    private func apply(_ state: WorkspaceState) {
        projects = state.projects
        agents = state.agents
        tasks = state.tasks
        followUps = state.followUps
        artifacts = state.artifacts
        recomputeProjectCounters()
    }

    private func persist() throws {
        let directory = persistenceURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try encoder.encode(snapshot())
        try data.write(to: persistenceURL, options: [.atomic])
    }

    private func snapshot() -> WorkspaceState {
        WorkspaceState(
            projects: projects,
            agents: agents,
            tasks: tasks,
            followUps: followUps,
            artifacts: artifacts
        )
    }

    private func recomputeProjectCounters() {
        for index in projects.indices {
            let projectId = projects[index].id
            projects[index].openTaskCount = openTaskCount(for: projectId)
            projects[index].followUpCount = openFollowUpCount(for: projectId)
        }
    }

    private func touch(projectId: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == projectId }) else { return }
        projects[index].lastMeaningfulChange = .now
    }

    private func attachAgents(_ agentIds: [UUID], toProjectId projectId: UUID) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectId }) else { return }

        for agentId in agentIds {
            if !projects[projectIndex].activeAgentIds.contains(agentId) {
                projects[projectIndex].activeAgentIds.append(agentId)
            }

            guard let agentIndex = agents.firstIndex(where: { $0.id == agentId }) else { continue }
            if !agents[agentIndex].projectIds.contains(projectId) {
                agents[agentIndex].projectIds.append(projectId)
            }
        }
    }

    private func syncProjectAgentEdges(projectId: UUID, selectedAgentIds: [UUID]) {
        for index in agents.indices {
            if selectedAgentIds.contains(agents[index].id) {
                if !agents[index].projectIds.contains(projectId) {
                    agents[index].projectIds.append(projectId)
                }
            } else {
                agents[index].projectIds.removeAll { $0 == projectId }
            }
        }
    }

    private func syncAgentProjectEdges(agentId: UUID, selectedProjectIds: [UUID]) {
        for index in projects.indices {
            if selectedProjectIds.contains(projects[index].id) {
                if !projects[index].activeAgentIds.contains(agentId) {
                    projects[index].activeAgentIds.append(agentId)
                }
            } else {
                projects[index].activeAgentIds.removeAll { $0 == agentId }
            }
        }
    }

    static func sample() -> WorkspaceStore {
        let projectId = UUID()
        let codexId = UUID()
        let claudeId = UUID()

        let project = SwarmProject(
            id: projectId,
            name: "Agent Swarm Management",
            summary: "Native Mac command center for projects, agents, tasks, follow-ups, and proof.",
            status: .needsAttention,
            activeAgentIds: [codexId, claudeId],
            openTaskCount: 1,
            followUpCount: 1,
            lastMeaningfulChange: .now
        )

        let codex = SwarmAgent(
            id: codexId,
            name: "OpenClaw Codex",
            harness: "OpenClaw / Telegram",
            status: .needsAttention,
            projectIds: [projectId],
            lastUpdate: .now
        )

        let claude = SwarmAgent(
            id: claudeId,
            name: "Claude Code",
            harness: "Agent Bridge",
            status: .healthy,
            projectIds: [projectId],
            lastUpdate: .now
        )

        let task = SwarmTask(
            id: UUID(),
            projectId: projectId,
            title: "Create architecture plan and SwiftUI scaffold",
            status: .needsAttention,
            assignedAgentIds: [codexId],
            parentTaskId: nil,
            sourcePageId: "3491af42-82dd-80c0-9b4a-fff3d5af3b2f"
        )

        let followUp = FollowUp(
            id: UUID(),
            projectId: projectId,
            agentId: codexId,
            question: "Confirm whether v1 should stay list/detail only before adding a Notion board view.",
            status: .needsAttention,
            createdAt: .now,
            sourceTurnId: "telegram:3584"
        )

        return WorkspaceStore(
            projects: [project],
            agents: [codex, claude],
            tasks: [task],
            followUps: [followUp],
            artifacts: []
        )
    }

    static func defaultPersistenceURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory

        return base
            .appendingPathComponent("AgentSwarmManagement", isDirectory: true)
            .appendingPathComponent("workspace.json")
    }
}

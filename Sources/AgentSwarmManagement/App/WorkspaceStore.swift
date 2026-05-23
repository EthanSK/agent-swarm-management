import Combine
import Foundation

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var projects: [SwarmProject]
    @Published var agents: [SwarmAgent]
    @Published var tasks: [SwarmTask]
    @Published var followUps: [FollowUp]
    @Published var artifacts: [Artifact]

    init(
        projects: [SwarmProject] = [],
        agents: [SwarmAgent] = [],
        tasks: [SwarmTask] = [],
        followUps: [FollowUp] = [],
        artifacts: [Artifact] = []
    ) {
        self.projects = projects
        self.agents = agents
        self.tasks = tasks
        self.followUps = followUps
        self.artifacts = artifacts
    }

    func bootstrap() async {
        // Placeholder for Phase 2 Notion pull. The sample dataset lets the UI
        // and menu bar shape be reviewed before credentials or schemas exist.
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
            openTaskCount: 3,
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
}


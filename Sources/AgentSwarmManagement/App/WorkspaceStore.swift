import Combine
import Foundation

struct WorkspaceState: Codable, Sendable {
    var projects: [SwarmProject]
    var agents: [SwarmAgent]
    var tasks: [SwarmTask]
    var followUps: [FollowUp]
    var artifacts: [Artifact]
    var settings: AppSettings
    var pendingOperations: [PendingSyncOperation]
    var syncMetadata: SyncMetadata

    init(
        projects: [SwarmProject],
        agents: [SwarmAgent],
        tasks: [SwarmTask],
        followUps: [FollowUp],
        artifacts: [Artifact],
        settings: AppSettings = .defaults,
        pendingOperations: [PendingSyncOperation] = [],
        syncMetadata: SyncMetadata = .empty
    ) {
        self.projects = projects
        self.agents = agents
        self.tasks = tasks
        self.followUps = followUps
        self.artifacts = artifacts
        self.settings = settings
        self.pendingOperations = pendingOperations
        self.syncMetadata = syncMetadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projects = try container.decodeIfPresent([SwarmProject].self, forKey: .projects) ?? []
        agents = try container.decodeIfPresent([SwarmAgent].self, forKey: .agents) ?? []
        tasks = try container.decodeIfPresent([SwarmTask].self, forKey: .tasks) ?? []
        followUps = try container.decodeIfPresent([FollowUp].self, forKey: .followUps) ?? []
        artifacts = try container.decodeIfPresent([Artifact].self, forKey: .artifacts) ?? []
        settings = try container.decodeIfPresent(AppSettings.self, forKey: .settings) ?? .defaults
        pendingOperations = try container.decodeIfPresent([PendingSyncOperation].self, forKey: .pendingOperations) ?? []
        syncMetadata = try container.decodeIfPresent(SyncMetadata.self, forKey: .syncMetadata) ?? .empty
    }
}

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var projects: [SwarmProject]
    @Published var agents: [SwarmAgent]
    @Published var tasks: [SwarmTask]
    @Published var followUps: [FollowUp]
    @Published var artifacts: [Artifact]
    @Published var settings: AppSettings
    @Published var pendingOperations: [PendingSyncOperation]
    @Published var syncMetadata: SyncMetadata
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
        settings: AppSettings = .defaults,
        pendingOperations: [PendingSyncOperation] = [],
        syncMetadata: SyncMetadata = .empty,
        persistenceURL: URL = WorkspaceStore.defaultPersistenceURL()
    ) {
        self.projects = projects
        self.agents = agents
        self.tasks = tasks
        self.followUps = followUps
        self.artifacts = artifacts
        self.settings = settings
        self.pendingOperations = pendingOperations
        self.syncMetadata = syncMetadata
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
                apply(try decoder.decode(WorkspaceState.self, from: data), enqueue: false)
            } else {
                // The first launch starts with the recovered Agent Swarm project,
                // then persists it so later UI edits are local-first and durable.
                recomputeProjectCounters()
                try persist()
            }
            if normalizeLegacyScaffoldData() {
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

    var pendingOperationCount: Int {
        pendingOperations.count
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

    func saveSettings(_ nextSettings: AppSettings) {
        settings = nextSettings
        save()
    }

    func syncSnapshot() -> WorkspaceState {
        snapshot()
    }

    func upsertProject(_ project: SwarmProject, enqueue: Bool = true) {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        } else {
            projects.append(project)
        }

        syncProjectAgentEdges(projectId: project.id, selectedAgentIds: project.activeAgentIds)
        recomputeProjectCounters()
        if enqueue {
            enqueueSync(kind: .project, mutation: .upsert, recordId: project.id, pageId: project.sourcePageId)
        }
        save()
    }

    func deleteProject(_ project: SwarmProject, enqueue: Bool = true) {
        projects.removeAll { $0.id == project.id }
        tasks.removeAll { $0.projectId == project.id }
        followUps.removeAll { $0.projectId == project.id }
        artifacts.removeAll { $0.projectId == project.id }

        for index in agents.indices {
            agents[index].projectIds.removeAll { $0 == project.id }
        }

        if enqueue {
            enqueueSync(kind: .project, mutation: .delete, recordId: project.id, pageId: project.sourcePageId)
        }
        save()
    }

    func upsertAgent(_ agent: SwarmAgent, enqueue: Bool = true) {
        if let index = agents.firstIndex(where: { $0.id == agent.id }) {
            agents[index] = agent
        } else {
            agents.append(agent)
        }

        syncAgentProjectEdges(agentId: agent.id, selectedProjectIds: agent.projectIds)
        recomputeProjectCounters()
        if enqueue {
            enqueueSync(kind: .agent, mutation: .upsert, recordId: agent.id, pageId: agent.sourcePageId)
        }
        save()
    }

    func deleteAgent(_ agent: SwarmAgent, enqueue: Bool = true) {
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
        if enqueue {
            enqueueSync(kind: .agent, mutation: .delete, recordId: agent.id, pageId: agent.sourcePageId)
        }
        save()
    }

    func upsertTask(_ task: SwarmTask, enqueue: Bool = true) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }

        touch(projectId: task.projectId)
        attachAgents(task.assignedAgentIds, toProjectId: task.projectId)
        recomputeProjectCounters()
        if enqueue {
            enqueueSync(kind: .task, mutation: .upsert, recordId: task.id, pageId: task.sourcePageId)
        }
        save()
    }

    func deleteTask(_ task: SwarmTask, enqueue: Bool = true) {
        tasks.removeAll { $0.id == task.id }
        touch(projectId: task.projectId)
        recomputeProjectCounters()
        if enqueue {
            enqueueSync(kind: .task, mutation: .delete, recordId: task.id, pageId: task.sourcePageId)
        }
        save()
    }

    func setTaskStatus(_ task: SwarmTask, status: SwarmStatus) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].status = status
        touch(projectId: task.projectId)
        recomputeProjectCounters()
        enqueueSync(kind: .task, mutation: .upsert, recordId: task.id, pageId: task.sourcePageId)
        save()
    }

    func upsertFollowUp(_ followUp: FollowUp, enqueue: Bool = true) {
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
        if enqueue {
            enqueueSync(kind: .followUp, mutation: .upsert, recordId: followUp.id, pageId: followUp.sourcePageId)
        }
        save()
    }

    func deleteFollowUp(_ followUp: FollowUp, enqueue: Bool = true) {
        followUps.removeAll { $0.id == followUp.id }
        touch(projectId: followUp.projectId)
        recomputeProjectCounters()
        if enqueue {
            enqueueSync(kind: .followUp, mutation: .delete, recordId: followUp.id, pageId: followUp.sourcePageId)
        }
        save()
    }

    func setFollowUpStatus(_ followUp: FollowUp, status: SwarmStatus) {
        guard let index = followUps.firstIndex(where: { $0.id == followUp.id }) else { return }
        followUps[index].status = status
        touch(projectId: followUp.projectId)
        recomputeProjectCounters()
        enqueueSync(kind: .followUp, mutation: .upsert, recordId: followUp.id, pageId: followUp.sourcePageId)
        save()
    }

    func applyRemoteSnapshot(_ snapshot: NotionWorkspaceSnapshot) {
        // Pulling from Notion is authoritative. Keep local pending operations so
        // unconfirmed local edits can still be retried or surfaced as conflicts.
        projects = snapshot.projects
        agents = snapshot.agents
        tasks = snapshot.tasks
        followUps = snapshot.followUps
        recomputeProjectCounters()
        syncMetadata.lastPullAt = snapshot.fetchedAt
        syncMetadata.lastNotionError = nil
        save()
    }

    func recordSchema(_ schema: NotionSchema) {
        settings.notionRootPage = schema.rootPageId
        settings.projectsDataSourceId = schema.projectsDataSourceId
        settings.agentsDataSourceId = schema.agentsDataSourceId
        settings.tasksDataSourceId = schema.tasksDataSourceId
        settings.followUpsDataSourceId = schema.followUpsDataSourceId
        settings.artifactsDataSourceId = schema.artifactsDataSourceId
        save()
    }

    func confirmSync(operation: PendingSyncOperation, notionPageId: String?) {
        if let notionPageId {
            setSourcePageId(notionPageId, for: operation.kind, recordId: operation.localRecordId)
        }

        pendingOperations.removeAll { $0.id == operation.id }
        rememberCompletedOperation(operation.id)
        syncMetadata.lastPushAt = .now
        syncMetadata.lastNotionError = nil
        save()
    }

    func markSyncFailed(operation: PendingSyncOperation, error: String) {
        guard let index = pendingOperations.firstIndex(where: { $0.id == operation.id }) else { return }
        pendingOperations[index].attemptCount += 1
        pendingOperations[index].updatedAt = .now
        pendingOperations[index].lastError = error
        syncMetadata.lastNotionError = error
        save()
    }

    func markControlEventHandled(_ operationId: String) {
        rememberCompletedOperation(operationId)
        syncMetadata.lastControlEventAt = .now
        save()
    }

    func hasCompletedOperation(_ operationId: String) -> Bool {
        syncMetadata.completedOperationIds.contains(operationId)
    }

    func recordMeaningfulAgentEvent(_ request: AgentEventRequest) {
        if hasCompletedOperation(request.operationId) {
            return
        }

        let project = upsertProjectFromEvent(request)
        let agent = upsertAgentFromEvent(request, projectId: project.id)

        if let taskTitle = request.taskTitle?.trimmedNonEmpty {
            var task = tasks.first {
                $0.projectId == project.id
                    && $0.title.caseInsensitiveCompare(taskTitle) == .orderedSame
                    && $0.sourceTurnId == request.sourceTurnId
            } ?? SwarmTask(
                id: UUID(),
                projectId: project.id,
                title: taskTitle,
                status: request.taskStatus ?? .needsAttention,
                assignedAgentIds: agent.map { [$0.id] } ?? [],
                parentTaskId: nil,
                sourcePageId: nil,
                sourceTurnId: request.sourceTurnId,
                lastUpdatedBy: request.actorDescription
            )

            task.title = taskTitle
            task.status = request.taskStatus ?? task.status
            task.sourceTurnId = request.sourceTurnId ?? task.sourceTurnId
            task.lastUpdatedBy = request.actorDescription
            if let agent, !task.assignedAgentIds.contains(agent.id) {
                task.assignedAgentIds.append(agent.id)
            }
            upsertTask(task)
        }

        if let question = request.followUpQuestion?.trimmedNonEmpty {
            var followUp = followUps.first {
                $0.projectId == project.id
                    && $0.question.caseInsensitiveCompare(question) == .orderedSame
                    && $0.sourceTurnId == request.sourceTurnId
            } ?? FollowUp(
                id: UUID(),
                projectId: project.id,
                agentId: agent?.id,
                question: question,
                status: .needsAttention,
                createdAt: .now,
                sourceTurnId: request.sourceTurnId,
                sourcePageId: nil,
                lastUpdatedBy: request.actorDescription
            )

            followUp.question = question
            followUp.agentId = agent?.id ?? followUp.agentId
            followUp.sourceTurnId = request.sourceTurnId ?? followUp.sourceTurnId
            followUp.lastUpdatedBy = request.actorDescription
            upsertFollowUp(followUp)
        }

        markControlEventHandled(request.operationId)
    }

    @discardableResult
    func registerAgent(_ request: AgentRegistrationRequest) -> SwarmAgent {
        let normalizedAgentName = request.agentName.trimmedNonEmpty ?? "Unnamed agent"
        let normalizedHarness = request.harness.trimmedNonEmpty ?? "Unknown harness"

        var agent = agents.first { existing in
            if let incomingId = request.harnessAgentId?.trimmedNonEmpty,
               existing.harnessAgentId == incomingId,
               existing.harness.caseInsensitiveCompare(normalizedHarness) == .orderedSame {
                return true
            }

            return existing.name.caseInsensitiveCompare(normalizedAgentName) == .orderedSame
                && existing.harness.caseInsensitiveCompare(normalizedHarness) == .orderedSame
        } ?? SwarmAgent(
            id: UUID(),
            name: normalizedAgentName,
            harness: normalizedHarness,
            status: request.status,
            projectIds: [],
            lastUpdate: .now
        )

        // Registration deliberately does not attach the agent to projects.
        // Projects should emerge from real agent events so the app remains an
        // operations surface, not a manual CRM-style data-entry tool.
        agent.name = normalizedAgentName
        agent.harness = normalizedHarness
        agent.status = request.status
        agent.harnessAgentId = request.harnessAgentId?.trimmedNonEmpty ?? agent.harnessAgentId
        agent.harnessVersion = request.harnessVersion?.trimmedNonEmpty ?? agent.harnessVersion
        agent.skillVersion = request.skillVersion?.trimmedNonEmpty ?? agent.skillVersion
        agent.sourceMachine = request.sourceMachine?.trimmedNonEmpty ?? agent.sourceMachine
        agent.lastHealthSummary = request.summary?.trimmedNonEmpty ?? agent.lastHealthSummary
        agent.lastUpdate = .now
        agent.lastUpdatedBy = request.actorDescription
        upsertAgent(agent)

        if let operationId = request.operationId?.trimmedNonEmpty {
            markControlEventHandled(operationId)
        }

        return agent
    }

    func save() {
        do {
            try persist()
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = error.localizedDescription
        }
    }

    private func upsertProjectFromEvent(_ request: AgentEventRequest) -> SwarmProject {
        let projectName = request.projectName.trimmedNonEmpty ?? "Inbox"
        var project = projects.first {
            $0.name.caseInsensitiveCompare(projectName) == .orderedSame
        } ?? SwarmProject(
            id: UUID(),
            name: projectName,
            summary: request.summary?.trimmedNonEmpty ?? "",
            status: .needsAttention,
            activeAgentIds: [],
            openTaskCount: 0,
            followUpCount: 0,
            lastMeaningfulChange: .now,
            sourcePageId: nil,
            lastUpdatedBy: request.actorDescription
        )

        project.name = projectName
        if let summary = request.summary?.trimmedNonEmpty {
            project.summary = summary
        }
        project.status = request.taskStatus ?? project.status
        project.lastMeaningfulChange = .now
        project.lastUpdatedBy = request.actorDescription
        upsertProject(project)
        return project
    }

    private func upsertAgentFromEvent(_ request: AgentEventRequest, projectId: UUID) -> SwarmAgent? {
        guard let agentName = request.agentName?.trimmedNonEmpty else { return nil }

        var agent = agents.first {
            $0.name.caseInsensitiveCompare(agentName) == .orderedSame
        } ?? SwarmAgent(
            id: UUID(),
            name: agentName,
            harness: request.harness?.trimmedNonEmpty ?? "Unknown harness",
            status: .healthy,
            projectIds: [],
            lastUpdate: .now,
            sourcePageId: nil,
            lastUpdatedBy: request.actorDescription
        )

        agent.name = agentName
        agent.harness = request.harness?.trimmedNonEmpty ?? agent.harness
        agent.status = request.taskStatus ?? agent.status
        agent.lastUpdate = .now
        agent.lastUpdatedBy = request.actorDescription
        if !agent.projectIds.contains(projectId) {
            agent.projectIds.append(projectId)
        }
        upsertAgent(agent)
        return agent
    }

    private func apply(_ state: WorkspaceState, enqueue: Bool) {
        projects = state.projects
        agents = state.agents
        tasks = state.tasks
        followUps = state.followUps
        artifacts = state.artifacts
        settings = state.settings
        pendingOperations = state.pendingOperations
        syncMetadata = state.syncMetadata
        recomputeProjectCounters()

        if enqueue {
            for project in projects {
                enqueueSync(kind: .project, mutation: .upsert, recordId: project.id, pageId: project.sourcePageId)
            }
        }
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
            artifacts: artifacts,
            settings: settings,
            pendingOperations: pendingOperations,
            syncMetadata: syncMetadata
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

    private func enqueueSync(kind: SwarmRecordKind, mutation: SwarmMutationKind, recordId: UUID, pageId: String?) {
        let coalescingKey = "\(kind.rawValue):\(recordId.uuidString)"
        pendingOperations.removeAll {
            $0.kind == kind && $0.localRecordId == recordId && $0.mutation == .upsert
        }

        let operation = PendingSyncOperation(
            id: "\(coalescingKey):\(mutation.rawValue):\(Int(Date().timeIntervalSince1970))",
            kind: kind,
            mutation: mutation,
            localRecordId: recordId,
            notionPageId: pageId
        )
        pendingOperations.append(operation)
    }

    private func setSourcePageId(_ sourcePageId: String, for kind: SwarmRecordKind, recordId: UUID) {
        switch kind {
        case .project:
            guard let index = projects.firstIndex(where: { $0.id == recordId }) else { return }
            projects[index].sourcePageId = sourcePageId
        case .agent:
            guard let index = agents.firstIndex(where: { $0.id == recordId }) else { return }
            agents[index].sourcePageId = sourcePageId
        case .task:
            guard let index = tasks.firstIndex(where: { $0.id == recordId }) else { return }
            tasks[index].sourcePageId = sourcePageId
        case .followUp:
            guard let index = followUps.firstIndex(where: { $0.id == recordId }) else { return }
            followUps[index].sourcePageId = sourcePageId
        case .artifact:
            guard let index = artifacts.firstIndex(where: { $0.id == recordId }) else { return }
            artifacts[index].sourcePageId = sourcePageId
        }
    }

    private func rememberCompletedOperation(_ operationId: String) {
        guard !operationId.isEmpty else { return }
        if !syncMetadata.completedOperationIds.contains(operationId) {
            syncMetadata.completedOperationIds.append(operationId)
        }

        // Keep enough history for repeated hook retries without allowing the
        // cache file to grow forever from high-volume agent runs.
        if syncMetadata.completedOperationIds.count > 500 {
            syncMetadata.completedOperationIds.removeFirst(syncMetadata.completedOperationIds.count - 500)
        }
    }

    private func normalizeLegacyScaffoldData() -> Bool {
        var didChange = false

        for index in agents.indices {
            if agents[index].name == "OpenClaw Codex", agents[index].harness == "OpenClaw / Telegram" {
                agents[index].name = "OpenClaw"
                agents[index].harness = "OpenClaw" // Old cache showed combined OpenClaw/Codex; launch a pre-self-registration cache to repro.
                didChange = true
            }

            if agents[index].name == "Claude Code", agents[index].harness == "Agent Bridge" {
                agents[index].harness = "Claude Code" // Old cache disabled Claude install actions; launch the previous scaffold cache to repro.
                didChange = true
            }
        }

        return didChange
    }

    static func sample() -> WorkspaceStore {
        let projectId = UUID()
        let openClawId = UUID()
        let codexId = UUID()
        let claudeId = UUID()

        let project = SwarmProject(
            id: projectId,
            name: "Agent Swarm Management",
            summary: "Native Mac command center for projects, agents, tasks, follow-ups, and proof.",
            status: .needsAttention,
            activeAgentIds: [openClawId, codexId, claudeId],
            openTaskCount: 1,
            followUpCount: 1,
            lastMeaningfulChange: .now
        )

        let openClaw = SwarmAgent(
            id: openClawId,
            name: "OpenClaw",
            harness: "OpenClaw",
            status: .needsAttention,
            projectIds: [projectId],
            lastUpdate: .now
        )

        let codex = SwarmAgent(
            id: codexId,
            name: "Codex",
            harness: "Codex",
            status: .healthy,
            projectIds: [projectId],
            lastUpdate: .now
        )

        let claude = SwarmAgent(
            id: claudeId,
            name: "Claude Code",
            harness: "Claude Code",
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
            agents: [openClaw, codex, claude],
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

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

import AppKit
import SwiftUI

struct AgentsView: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var controlServer: LocalControlServer

    @State private var selectedHarness: HarnessFamily = .openClaw
    @State private var isShowingSetup = false
    @State private var installResult: String?
    @State private var installError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Picker("Setup target", selection: $selectedHarness) {
                    ForEach(HarnessFamily.allCases) { family in
                        Text(family.title).tag(family)
                    }
                }
                .frame(width: 220)

                Button {
                    isShowingSetup = true
                } label: {
                    Label("Set Up Agent", systemImage: "person.crop.circle.badge.plus")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    copySetupJSON()
                } label: {
                    Label("Copy Setup JSON", systemImage: "doc.on.doc")
                }

                Spacer()
            }
            .padding()

            if let installResult {
                Label(installResult, systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            if let installError {
                Label(installError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            List(store.agents) { agent in
                AgentRow(
                    agent: agent,
                    store: store,
                    onInstall: { installSkill(for: agent) },
                    onCopySkill: { copySkill(for: agent) }
                )
                .padding(.vertical, 8)
            }
            .overlay {
                if store.agents.isEmpty {
                    ContentUnavailableView(
                        "No agents registered",
                        systemImage: "person.2.badge.gearshape",
                        description: Text("Use Set Up Agent to install instructions, then let the harness register itself through the local endpoint.")
                    )
                }
            }
        }
        .navigationTitle("Agents")
        .sheet(isPresented: $isShowingSetup) {
            AgentSetupView(
                family: selectedHarness,
                baseURL: controlServer.endpointURL,
                onInstall: { installSkill(for: selectedHarness) },
                onCopySetup: copySetupJSON,
                onCopySkill: { copySkill(for: selectedHarness) }
            )
        }
    }

    private func installSkill(for agent: SwarmAgent) {
        guard let family = HarnessFamily.match(agent.harness) else {
            installError = "No installer for \(agent.harness)."
            installResult = nil
            return
        }

        installSkill(for: family)
    }

    private func installSkill(for family: HarnessFamily) {
        do {
            let result = try HarnessSkillInstaller.install(family: family, baseURL: controlServer.endpointURL)
            installResult = "Installed \(family.title) skill at \(result.destination.path)"
            installError = nil
        } catch {
            installResult = nil
            installError = error.localizedDescription
        }
    }

    private func copySetupJSON() {
        let payload = AgentSwarmContract.setupPayload(baseURL: controlServer.endpointURL)
        copyJSONObject(payload)
    }

    private func copySkill(for agent: SwarmAgent) {
        guard let family = HarnessFamily.match(agent.harness) else {
            installError = "No skill template for \(agent.harness)."
            installResult = nil
            return
        }

        copySkill(for: family)
    }

    private func copySkill(for family: HarnessFamily) {
        copyText(AgentSwarmContract.skillInstructions(for: family, baseURL: controlServer.endpointURL))
        installResult = "Copied \(family.title) skill instructions."
        installError = nil
    }

    private func copyJSONObject(_ object: [String: Any]) {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]))
            ?? Data("{}".utf8)
        copyText(String(data: data, encoding: .utf8) ?? "{}")
        installResult = "Copied setup JSON."
        installError = nil
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
private struct AgentRow: View {
    var agent: SwarmAgent
    @ObservedObject var store: WorkspaceStore
    var onInstall: () -> Void
    var onCopySkill: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(agent.name)
                        .font(.headline)
                    HStack(spacing: 10) {
                        Label(agent.harness, systemImage: "cpu")
                        if let sourceMachine = agent.sourceMachine, !sourceMachine.isEmpty {
                            Label(sourceMachine, systemImage: "desktopcomputer")
                        }
                        Label(agent.lastUpdate.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                StatusBadge(status: agent.status)
            }

            HStack(spacing: 12) {
                Label("\(agent.projectIds.count) projects touched", systemImage: "folder")
                if let skillVersion = agent.skillVersion, !skillVersion.isEmpty {
                    Label("Skill \(skillVersion)", systemImage: "puzzlepiece.extension")
                }
                if let harnessVersion = agent.harnessVersion, !harnessVersion.isEmpty {
                    Label("Harness \(harnessVersion)", systemImage: "terminal")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let summary = agent.lastHealthSummary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    onInstall()
                } label: {
                    Label("Install/Reinstall", systemImage: "arrow.down.circle")
                }
                .disabled(HarnessFamily.match(agent.harness) == nil)

                Button {
                    onCopySkill()
                } label: {
                    Label("Copy Skill", systemImage: "doc.on.doc")
                }
                .disabled(HarnessFamily.match(agent.harness) == nil)

                Spacer()

                Text(agent.harnessAgentId ?? "No stable harness ID yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct AgentSetupView: View {
    @Environment(\.dismiss) private var dismiss

    var family: HarnessFamily
    var baseURL: URL
    var onInstall: () -> Void
    var onCopySetup: () -> Void
    var onCopySkill: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Setup target") {
                    LabeledContent("Harness family", value: family.title)
                    LabeledContent("Skill path", value: family.installLocationHint)
                    LabeledContent("Endpoint", value: baseURL.absoluteString)
                    LabeledContent("MCP", value: baseURL.appendingPathComponent("mcp").absoluteString)
                }

                Section("Actions") {
                    Button {
                        onInstall()
                        dismiss()
                    } label: {
                        Label("Install/Reinstall Local Skill", systemImage: "arrow.down.circle")
                    }
                    .disabled(family == .generic)

                    Button {
                        onCopySetup()
                    } label: {
                        Label("Copy Setup JSON", systemImage: "doc.on.doc")
                    }

                    Button {
                        onCopySkill()
                    } label: {
                        Label("Copy Skill Instructions", systemImage: "puzzlepiece.extension")
                    }
                }

                Section("Runtime contract") {
                    Text("Register through POST /v1/agents/register or MCP tool agent_swarm_register. Report work through POST /v1/agent-events or MCP tool agent_swarm_report_event.")
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Set Up Agent")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(width: 720, height: 640)
    }
}

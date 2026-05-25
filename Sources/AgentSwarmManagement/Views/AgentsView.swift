import AppKit
import SwiftUI

struct AgentsView: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var controlServer: LocalControlServer

    @State private var isShowingSetup = false
    @State private var installResult: String?
    @State private var installError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    isShowingSetup = true
                } label: {
                    Label("Set Up Agent", systemImage: "person.crop.circle.badge.plus")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    copySetupJSON()
                } label: {
                    Label("Copy Endpoint JSON", systemImage: "doc.on.doc")
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

            // Agent rows are self-reported by harnesses; the setup UI only installs
            // the instructions a harness needs to register itself through the endpoint.
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
                baseURL: controlServer.endpointURL,
                onInstall: installSkill,
                onCopySetup: copySetupJSON,
                onCopySkill: copySkill
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

    var baseURL: URL
    var onInstall: (HarnessFamily) -> Void
    var onCopySetup: () -> Void
    var onCopySkill: (HarnessFamily) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Keep the endpoint contract visible before harness-specific cards so
                    // users understand that any compatible agent can integrate.
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(baseURL.absoluteString, systemImage: "point.3.connected.trianglepath.dotted")
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)

                            Label(baseURL.appendingPathComponent("mcp").absoluteString, systemImage: "server.rack")
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)

                            Button {
                                onCopySetup()
                            } label: {
                                Label("Copy Full Endpoint JSON", systemImage: "doc.on.doc")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Label("Local Endpoint", systemImage: "network")
                    }

                    ForEach(HarnessFamily.allCases) { family in
                        HarnessSetupCard(
                            family: family,
                            onInstall: { onInstall(family) },
                            onCopySkill: { onCopySkill(family) }
                        )
                    }

                    GroupBox {
                        Text("Agents appear here after they register through POST /v1/agents/register or MCP tool agent_swarm_register. Project/task/follow-up rows should come from reported agent work, not manual agent setup.")
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Label("Registration Contract", systemImage: "curlybraces")
                    }
                }
                .padding(24)
            }
            .navigationTitle("Set Up Agent")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(width: 760, height: 720)
    }
}

private struct HarnessSetupCard: View {
    var family: HarnessFamily
    var onInstall: () -> Void
    var onCopySkill: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(family.title)
                            .font(.headline)
                        Text(family.description)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Text(family.slug)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                Label(family.installLocationHint, systemImage: "folder")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                HStack(spacing: 10) {
                    Button {
                        onInstall()
                    } label: {
                        Label("Install/Reinstall Skill", systemImage: "arrow.down.circle")
                    }
                    .disabled(family == .generic)

                    Button {
                        onCopySkill()
                    } label: {
                        Label(family == .generic ? "Copy Integration Instructions" : "Copy Skill Instructions", systemImage: "doc.on.doc")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

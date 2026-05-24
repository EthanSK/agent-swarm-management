import SwiftUI

enum MainSection: String, CaseIterable, Identifiable, Hashable {
    case projects = "Projects"
    case agents = "Agents"
    case followUps = "Follow-ups"
    case tasks = "Tasks"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .projects: "folder"
        case .agents: "person.2"
        case .followUps: "questionmark.bubble"
        case .tasks: "checklist"
        }
    }
}

struct RootView: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var controlServer: LocalControlServer
    @State private var selection: MainSection? = .agents

    var body: some View {
        NavigationSplitView {
            List(MainSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("Agent Swarm")
        } detail: {
            VStack(spacing: 0) {
                if !store.settings.hasCoreNotionDataSources {
                    NotionSetupBanner()
                }

                switch selection ?? .agents {
                case .projects:
                    ProjectsView(store: store)
                case .agents:
                    AgentsView(store: store, controlServer: controlServer)
                case .followUps:
                    FollowUpsView(store: store)
                case .tasks:
                    TasksView(store: store)
                }
            }
        }
        .frame(minWidth: 980, minHeight: 640)
    }
}

struct StatusBadge: View {
    var status: SwarmStatus

    var body: some View {
        Label(status.title, systemImage: status.systemImage)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
    }
}

private struct NotionSetupBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Label("Notion setup needed", systemImage: "exclamationmark.triangle")
                .font(.headline)

            Text("Connect Notion before treating local cache changes as durable.")
                .foregroundStyle(.secondary)

            Spacer()

            SettingsLink {
                Label("Open Settings", systemImage: "gearshape")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.yellow.opacity(0.12))
    }
}


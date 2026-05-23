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
    @State private var selection: MainSection? = .projects

    var body: some View {
        NavigationSplitView {
            List(MainSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("Agent Swarm")
        } detail: {
            switch selection ?? .projects {
            case .projects:
                ProjectsView(store: store)
            case .agents:
                AgentsView(store: store)
            case .followUps:
                FollowUpsView(store: store)
            case .tasks:
                TasksView(store: store)
            }
        }
        .frame(minWidth: 940, minHeight: 620)
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


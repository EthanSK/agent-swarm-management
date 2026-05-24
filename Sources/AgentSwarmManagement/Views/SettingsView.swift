import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var controlServer: LocalControlServer
    @ObservedObject var syncCoordinator: SyncCoordinator
    @ObservedObject var appUpdater: AppUpdater

    @State private var notionToken = ""
    @State private var notionRootPage = ""
    @State private var notionVersion = AppSettings.currentNotionVersion
    @State private var projectsDataSourceId = ""
    @State private var agentsDataSourceId = ""
    @State private var tasksDataSourceId = ""
    @State private var followUpsDataSourceId = ""
    @State private var artifactsDataSourceId = ""
    @State private var localServerPort = "17391"
    @State private var offlineWritesEnabled = false
    @State private var writesPaused = false

    var body: some View {
        Form {
            Section("Notion") {
                SecureField("API token", text: $notionToken)
                LabeledContent("Saved Notion token", value: syncCoordinator.notionTokenPreview())
                TextField("Parent page ID or URL", text: $notionRootPage)
                TextField("API version", text: $notionVersion)

                HStack {
                    Button("Save") {
                        saveSettings()
                        syncCoordinator.saveNotionToken(notionToken)
                        notionToken = ""
                    }

                    Button("Create Data Sources") {
                        saveSettings()
                        Task { await syncCoordinator.createWorkspaceSchema(in: store) }
                    }
                    .disabled(syncCoordinator.isWorking)
                }
            }

            Section("Data Sources") {
                TextField("Projects", text: $projectsDataSourceId)
                TextField("Agents", text: $agentsDataSourceId)
                TextField("Tasks", text: $tasksDataSourceId)
                TextField("Follow-ups", text: $followUpsDataSourceId)
                TextField("Artifacts", text: $artifactsDataSourceId)
            }

            Section("Sync") {
                Toggle("Pause Notion writes", isOn: $writesPaused)
                Toggle("Allow offline writes", isOn: $offlineWritesEnabled)

                HStack {
                    Button("Pull") {
                        saveSettings()
                        Task { await syncCoordinator.pullNow(into: store) }
                    }
                    .disabled(syncCoordinator.isWorking)

                    Button("Push Pending") {
                        saveSettings()
                        Task { await syncCoordinator.pushPending(from: store) }
                    }
                    .disabled(syncCoordinator.isWorking || store.pendingOperationCount == 0)
                }

                LabeledContent("Pending", value: "\(store.pendingOperationCount)")
                LabeledContent("Last pull", value: store.syncMetadata.lastPullAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                LabeledContent("Last push", value: store.syncMetadata.lastPushAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                LabeledContent("Status", value: syncCoordinator.statusLine)

                if let error = syncCoordinator.lastError ?? store.syncMetadata.lastNotionError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            Section("Agent Endpoint") {
                LabeledContent("URL", value: controlServer.endpointURL.absoluteString)
                LabeledContent("Token", value: controlServer.tokenPreview)

                Button("Copy Endpoint JSON") {
                    copyEndpointJSON()
                }

                TextField("Port", text: $localServerPort)
                Text(controlServer.statusLine)
                    .foregroundStyle(.secondary)
            }

            Section("Auto Updates") {
                Toggle(
                    "Automatically check for updates",
                    isOn: Binding(
                        get: { appUpdater.automaticallyChecksForUpdates },
                        set: { appUpdater.setAutomaticallyChecksForUpdates($0) }
                    )
                )

                Toggle(
                    "Automatically download updates",
                    isOn: Binding(
                        get: { appUpdater.automaticallyDownloadsUpdates },
                        set: { appUpdater.setAutomaticallyDownloadsUpdates($0) }
                    )
                )

                HStack {
                    Button("Check for Updates") {
                        appUpdater.checkForUpdates()
                    }
                    .disabled(!appUpdater.canCheckForUpdates)

                    Button("Open Releases") {
                        appUpdater.openReleasesPage()
                    }
                }

                Text("Uses Sparkle with the GitHub appcast feed packaged into the app bundle.")
                    .foregroundStyle(.secondary)
            }

            Section("Local Cache") {
                Text(store.persistenceURL.path)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)

                if let error = store.lastPersistenceError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                } else {
                    Label("Saved", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(width: 640)
        .onAppear(perform: loadSettings)
        .onChange(of: store.settings) {
            loadSettings()
        }
    }

    private func loadSettings() {
        notionRootPage = store.settings.notionRootPage
        notionVersion = store.settings.notionVersion
        projectsDataSourceId = store.settings.projectsDataSourceId
        agentsDataSourceId = store.settings.agentsDataSourceId
        tasksDataSourceId = store.settings.tasksDataSourceId
        followUpsDataSourceId = store.settings.followUpsDataSourceId
        artifactsDataSourceId = store.settings.artifactsDataSourceId
        localServerPort = String(store.settings.localServerPort)
        offlineWritesEnabled = store.settings.offlineWritesEnabled
        writesPaused = store.settings.writesPaused
    }

    private func saveSettings() {
        let port = UInt16(localServerPort) ?? store.settings.localServerPort
        store.saveSettings(
            AppSettings(
                notionVersion: notionVersion.trimmedOrDefault(AppSettings.currentNotionVersion),
                notionRootPage: notionRootPage.trimmed,
                projectsDataSourceId: projectsDataSourceId.trimmed,
                agentsDataSourceId: agentsDataSourceId.trimmed,
                tasksDataSourceId: tasksDataSourceId.trimmed,
                followUpsDataSourceId: followUpsDataSourceId.trimmed,
                artifactsDataSourceId: artifactsDataSourceId.trimmed,
                localServerPort: port,
                offlineWritesEnabled: offlineWritesEnabled,
                writesPaused: writesPaused
            )
        )
    }

    private func copyEndpointJSON() {
        let payload = controlServer.endpointConfiguration()

        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]))
            ?? Data("{}".utf8)
        let text = String(data: data, encoding: .utf8) ?? "{}"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func trimmedOrDefault(_ fallback: String) -> String {
        let next = trimmed
        return next.isEmpty ? fallback : next
    }
}

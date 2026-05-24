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
    @State private var showAdvancedNotion = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                notionSetupSection
                syncSection
                agentEndpointSection
                autoUpdatesSection
                diagnosticsSection
                localCacheSection
            }
            .padding(24)
        }
        .frame(minWidth: 780, idealWidth: 840, minHeight: 720)
        .onAppear(perform: loadSettings)
        .onChange(of: store.settings) {
            loadSettings()
        }
    }

    private var notionSetupSection: some View {
        settingsSection("Notion Setup", systemImage: "square.stack.3d.up") {
            HStack(alignment: .top, spacing: 12) {
                Label(
                    store.settings.hasCoreNotionDataSources ? "Connected" : "Needs setup",
                    systemImage: store.settings.hasCoreNotionDataSources ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(store.settings.hasCoreNotionDataSources ? .green : .orange)
                .font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    Text("OAuth is the right public setup flow. This alpha keeps manual Notion integration tokens as the advanced fallback until the OAuth broker/release-signing path is added.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        openNotionIntegrations()
                    } label: {
                        Label("Open Notion Integrations", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.link)
                }
            }

            labeledSecureField(
                "Manual integration token",
                text: $notionToken,
                prompt: "Paste a Notion internal integration token for this alpha"
            )

            labeledTextField(
                "Parent Agent Swarm page",
                text: $notionRootPage,
                prompt: "Paste the Notion parent page URL or page ID"
            )

            HStack(spacing: 10) {
                Button {
                    saveSettings()
                    syncCoordinator.saveNotionToken(notionToken)
                    notionToken = ""
                } label: {
                    Label("Save Manual Setup", systemImage: "key")
                }

                Button {
                    syncCoordinator.saveNotionToken(notionToken)
                    notionToken = ""
                    saveSettings()
                    Task { await syncCoordinator.createWorkspaceSchema(in: store) }
                } label: {
                    Label("Create Notion Databases", systemImage: "plus.rectangle.on.folder")
                }
                .disabled(syncCoordinator.isWorking)
            }

            DisclosureGroup("Advanced IDs and API version", isExpanded: $showAdvancedNotion) {
                VStack(alignment: .leading, spacing: 12) {
                    labeledTextField("Notion API version", text: $notionVersion)
                    labeledTextField("Projects data source", text: $projectsDataSourceId)
                    labeledTextField("Agents data source", text: $agentsDataSourceId)
                    labeledTextField("Tasks data source", text: $tasksDataSourceId)
                    labeledTextField("Follow-ups data source", text: $followUpsDataSourceId)
                    labeledTextField("Artifacts data source", text: $artifactsDataSourceId)
                }
                .padding(.top, 8)
            }
        }
    }

    private var syncSection: some View {
        settingsSection("Sync", systemImage: "arrow.triangle.2.circlepath") {
            Toggle("Pause Notion writes", isOn: $writesPaused)
            Toggle("Allow offline writes to queue", isOn: $offlineWritesEnabled)

            HStack(spacing: 10) {
                Button {
                    saveSettings()
                    Task { await syncCoordinator.pullNow(into: store) }
                } label: {
                    Label("Pull From Notion", systemImage: "arrow.down.doc")
                }
                .disabled(syncCoordinator.isWorking)

                Button {
                    saveSettings()
                    Task { await syncCoordinator.pushPending(from: store) }
                } label: {
                    Label("Push Pending", systemImage: "arrow.up.doc")
                }
                .disabled(syncCoordinator.isWorking || store.pendingOperationCount == 0)
            }

            statusGrid([
                ("Credential", syncCoordinator.notionCredentialStatus),
                ("Pending writes", "\(store.pendingOperationCount)"),
                ("Last pull", store.syncMetadata.lastPullAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never"),
                ("Last push", store.syncMetadata.lastPushAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never"),
                ("Status", syncCoordinator.statusLine)
            ])

            if let error = syncCoordinator.lastError ?? store.syncMetadata.lastNotionError {
                errorLabel(error)
            }
        }
    }

    private var agentEndpointSection: some View {
        settingsSection("Agent Endpoint", systemImage: "point.3.connected.trianglepath.dotted") {
            statusGrid([
                ("URL", controlServer.endpointURL.absoluteString),
                ("Token", controlServer.tokenPreview),
                ("State", controlServer.statusLine)
            ])

            labeledTextField("Port", text: $localServerPort)

            HStack(spacing: 10) {
                Button {
                    copyEndpointJSON()
                } label: {
                    Label("Copy Endpoint JSON", systemImage: "doc.on.doc")
                }

                Button {
                    copyDiagnosticsJSON()
                } label: {
                    Label("Copy Diagnostics", systemImage: "stethoscope")
                }
            }
        }
    }

    private var autoUpdatesSection: some View {
        settingsSection("Auto Updates", systemImage: "sparkles") {
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

            HStack(spacing: 10) {
                Button {
                    appUpdater.checkForUpdates()
                } label: {
                    Label("Check for Updates", systemImage: "arrow.clockwise")
                }
                .disabled(!appUpdater.canCheckForUpdates)

                Button {
                    appUpdater.openReleasesPage()
                } label: {
                    Label("Open Releases", systemImage: "arrow.up.right.square")
                }
            }

            statusGrid([
                ("Sparkle", appUpdater.canCheckForUpdates ? "Ready" : "Starting"),
                ("Last check", appUpdater.lastUpdateStatus)
            ])

            if let error = appUpdater.lastUpdateError {
                errorLabel(error)
            }

            Text("Sparkle handles the standard update prompt, download, install authorization, and relaunch flow. Detailed update-cycle errors are written to the app log.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var diagnosticsSection: some View {
        settingsSection("Diagnostics & Logs", systemImage: "doc.text.magnifyingglass") {
            statusGrid([
                ("Log file", AppLogger.logURL.path),
                ("Local cache", store.persistenceURL.path)
            ])

            HStack(spacing: 10) {
                Button {
                    openLogsFolder()
                } label: {
                    Label("Open Logs", systemImage: "folder")
                }

                Button {
                    copyLogPath()
                } label: {
                    Label("Copy Log Path", systemImage: "doc.on.doc")
                }
            }
        }
    }

    private var localCacheSection: some View {
        settingsSection("Local Cache", systemImage: "externaldrive") {
            if let error = store.lastPersistenceError {
                errorLabel(error)
            } else {
                Label("Saved", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
        }
    }

    private func labeledTextField(
        _ label: String,
        text: Binding<String>,
        prompt: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
            TextField(prompt ?? label, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func labeledSecureField(
        _ label: String,
        text: Binding<String>,
        prompt: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
            SecureField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func statusGrid(_ rows: [(String, String)]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            ForEach(rows, id: \.0) { label, value in
                GridRow {
                    Text(label)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.system(.body, design: value.contains("/") || value.contains("http") ? .monospaced : .default))
                        .textSelection(.enabled)
                        .lineLimit(nil)
                }
            }
        }
    }

    private func errorLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
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
        AppLogger.info(
            "settings.saved",
            details: [
                "hasRootPage": "\(!notionRootPage.trimmed.isEmpty)",
                "hasCoreDataSources": "\(store.settings.hasCoreNotionDataSources)",
                "port": "\(port)",
                "writesPaused": "\(writesPaused)",
                "offlineWritesEnabled": "\(offlineWritesEnabled)"
            ]
        )
    }

    private func copyEndpointJSON() {
        copyJSONObject(controlServer.endpointConfiguration())
        AppLogger.info("settings.endpoint_json_copied")
    }

    private func copyDiagnosticsJSON() {
        copyJSONObject([
            "endpoint": controlServer.endpointURL.absoluteString,
            "endpointStatus": controlServer.statusLine,
            "logPath": AppLogger.logURL.path,
            "persistencePath": store.persistenceURL.path,
            "pendingNotionOperations": "\(store.pendingOperationCount)",
            "lastPersistenceError": store.lastPersistenceError ?? "",
            "lastNotionError": store.syncMetadata.lastNotionError ?? "",
            "lastUpdateStatus": appUpdater.lastUpdateStatus,
            "lastUpdateError": appUpdater.lastUpdateError ?? ""
        ])
        AppLogger.info("settings.diagnostics_copied")
    }

    private func copyLogPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(AppLogger.logURL.path, forType: .string)
        AppLogger.info("settings.log_path_copied")
    }

    private func copyJSONObject(_ payload: [String: String]) {
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]))
            ?? Data("{}".utf8)
        let text = String(data: data, encoding: .utf8) ?? "{}"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func openLogsFolder() {
        AppLogger.info("settings.open_logs_requested")
        let directory = AppLogger.logURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    private func openNotionIntegrations() {
        AppLogger.info("settings.open_notion_integrations_requested")
        guard let url = URL(string: "https://www.notion.so/my-integrations") else { return }
        NSWorkspace.shared.open(url)
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

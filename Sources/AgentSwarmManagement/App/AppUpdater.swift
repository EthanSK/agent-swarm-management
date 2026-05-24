import AppKit
import Combine
import Foundation
import Sparkle

@MainActor
final class AppUpdater: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyDownloadsUpdates = false

    private let controller: SPUStandardUpdaterController

    init() {
        // Sparkle is the native equivalent of Producer Player's Electron
        // updater: it owns the feed check, download, install prompt, and
        // relaunch UX rather than making the app hand-roll those states.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        refresh()
    }

    func refresh() {
        let updater = controller.updater
        canCheckForUpdates = updater.canCheckForUpdates
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
        refresh()
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        controller.updater.automaticallyDownloadsUpdates = enabled
        refresh()
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
        refresh()
    }

    func openReleasesPage() {
        guard let url = URL(string: "https://github.com/EthanSK/agent-swarm-management/releases") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}


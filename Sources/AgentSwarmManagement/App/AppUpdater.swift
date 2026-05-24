import AppKit
import Combine
import Foundation
import Sparkle

@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyDownloadsUpdates = false
    @Published private(set) var lastUpdateStatus = "Ready to check for updates"
    @Published private(set) var lastUpdateError: String?

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    override init() {
        super.init()

        // Sparkle is the native equivalent of Producer Player's Electron
        // updater: it owns the feed check, download, install prompt, and
        // relaunch UX rather than making the app hand-roll those states.
        _ = controller
        AppLogger.info("updater.initialized")
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
        AppLogger.info("updater.automatic_checks_changed", details: ["enabled": "\(enabled)"])
        refresh()
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        controller.updater.automaticallyDownloadsUpdates = enabled
        AppLogger.info("updater.automatic_downloads_changed", details: ["enabled": "\(enabled)"])
        refresh()
    }

    func checkForUpdates() {
        lastUpdateStatus = "Checking GitHub appcast"
        lastUpdateError = nil
        AppLogger.info(
            "updater.check_requested",
            details: [
                "canCheckForUpdates": "\(controller.updater.canCheckForUpdates)",
                "automaticallyChecks": "\(controller.updater.automaticallyChecksForUpdates)",
                "automaticallyDownloads": "\(controller.updater.automaticallyDownloadsUpdates)"
            ]
        )
        controller.checkForUpdates(nil)
        refresh()
    }

    func openReleasesPage() {
        guard let url = URL(string: "https://github.com/EthanSK/agent-swarm-management/releases") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        lastUpdateError = error.localizedDescription
        lastUpdateStatus = "Update error occurred"
        AppLogger.error("updater.aborted", error: error)
        refresh()
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        if let error {
            lastUpdateError = error.localizedDescription
            lastUpdateStatus = "Update check finished with an error"
            AppLogger.error(
                "updater.cycle_finished_with_error",
                error: error,
                details: ["updateCheck": String(describing: updateCheck)]
            )
        } else {
            lastUpdateError = nil
            lastUpdateStatus = "Update check finished"
            AppLogger.info("updater.cycle_finished", details: ["updateCheck": String(describing: updateCheck)])
        }
        refresh()
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        lastUpdateError = nil
        lastUpdateStatus = "No update found"
        AppLogger.info("updater.no_update", details: ["reason": error.localizedDescription])
        refresh()
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        lastUpdateError = nil
        lastUpdateStatus = "Found update \(item.displayVersionString)"
        AppLogger.info(
            "updater.update_found",
            details: [
                "displayVersion": item.displayVersionString,
                "version": item.versionString
            ]
        )
        refresh()
    }
}

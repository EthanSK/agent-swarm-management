import Foundation

struct HarnessSkillInstallResult: Sendable {
    var family: HarnessFamily
    var destination: URL
    var backupURL: URL?
}

enum HarnessSkillInstaller {
    enum InstallError: LocalizedError {
        case unsupportedHarness

        var errorDescription: String? {
            switch self {
            case .unsupportedHarness:
                "Generic harnesses do not have a known local skill folder. Copy the package manually."
            }
        }
    }

    static func install(family: HarnessFamily, baseURL: URL) throws -> HarnessSkillInstallResult {
        guard let destination = AgentSwarmContract.defaultInstallURL(for: family) else {
            AppLogger.warning("skill.install_unsupported_harness", details: ["harness": family.slug])
            throw InstallError.unsupportedHarness
        }

        AppLogger.info(
            "skill.install_started",
            details: ["harness": family.slug, "destination": destination.path]
        )
        let package = AgentSwarmContract.skillPackage(for: family, baseURL: baseURL)
        guard let skillFile = package.files.first(where: { $0.relativePath == "SKILL.md" }) else {
            AppLogger.error("skill.install_missing_skill_file", details: ["harness": family.slug])
            throw CocoaError(.fileNoSuchFile)
        }

        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var backupURL: URL?
        if FileManager.default.fileExists(atPath: destination.path) {
            let stamp = ISO8601DateFormatter()
                .string(from: .now)
                .replacingOccurrences(of: ":", with: "-")
            let backup = destination.deletingPathExtension()
                .appendingPathExtension("backup-\(stamp).md")
            try FileManager.default.copyItem(at: destination, to: backup)
            backupURL = backup
        }

        try skillFile.content.write(to: destination, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: destination.path
        )

        AppLogger.info(
            "skill.install_finished",
            details: [
                "harness": family.slug,
                "destination": destination.path,
                "backup": backupURL?.path ?? ""
            ]
        )
        return HarnessSkillInstallResult(family: family, destination: destination, backupURL: backupURL)
    }
}

import Foundation

enum AppLogger {
    static var logURL: URL {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory

        return base
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Agent Swarm Management", isDirectory: true)
            .appendingPathComponent("app.log")
    }

    static func info(
        _ event: String,
        details: [String: String] = [:],
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        write(level: "info", event: event, details: details, file: file, line: line)
    }

    static func warning(
        _ event: String,
        details: [String: String] = [:],
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        write(level: "warning", event: event, details: details, file: file, line: line)
    }

    static func error(
        _ event: String,
        error: Error? = nil,
        details: [String: String] = [:],
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        var nextDetails = details
        if let error {
            nextDetails["error"] = error.localizedDescription
        }
        write(level: "error", event: event, details: nextDetails, file: file, line: line)
    }

    private static func write(
        level: String,
        event: String,
        details: [String: String],
        file: StaticString,
        line: UInt
    ) {
        let entry = AppLogEntry(
            timestamp: Date(),
            level: level,
            event: event,
            details: details,
            file: String(describing: file),
            line: line
        )

        // Logging must never block the UI or an agent endpoint response. The
        // actor serializes file appends while callers can continue immediately.
        Task.detached(priority: .utility) {
            await AppLogWriter.shared.write(entry)
        }
    }
}

private struct AppLogEntry: Encodable, Sendable {
    var timestamp: Date
    var level: String
    var event: String
    var details: [String: String]
    var file: String
    var line: UInt
}

private actor AppLogWriter {
    static let shared = AppLogWriter()

    private let encoder: JSONEncoder

    private init() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
    }

    func write(_ entry: AppLogEntry) {
        do {
            let url = AppLogger.logURL
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }

            let data = try encoder.encode(entry) + Data("\n".utf8)
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            handle.write(data)
            try handle.close()
        } catch {
            NSLog("Agent Swarm Management log write failed: %@", error.localizedDescription)
        }
    }
}

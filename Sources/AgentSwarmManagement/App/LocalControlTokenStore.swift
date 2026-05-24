import Foundation

struct LocalControlTokenStore {
    enum TokenError: LocalizedError {
        case invalidToken

        var errorDescription: String? {
            switch self {
            case .invalidToken:
                "The saved local endpoint token is invalid."
            }
        }
    }

    private let tokenURL: URL

    init(tokenURL: URL = LocalControlTokenStore.defaultTokenURL()) {
        self.tokenURL = tokenURL
    }

    func ensureToken() throws -> String {
        if let existing = try readToken(), Self.isValid(existing) {
            return existing
        }

        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        try saveToken(token)
        return token
    }

    private func readToken() throws -> String? {
        guard FileManager.default.fileExists(atPath: tokenURL.path) else {
            return nil
        }

        let value = try String(contentsOf: tokenURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValid(value) else {
            throw TokenError.invalidToken
        }

        return value
    }

    private func saveToken(_ token: String) throws {
        guard Self.isValid(token) else {
            throw TokenError.invalidToken
        }

        let directory = tokenURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "\(token)\n".write(to: tokenURL, atomically: true, encoding: .utf8)

        // This is an app-generated localhost bearer token, not a user
        // credential. Keep it private to the local account without forcing a
        // Keychain prompt on launch.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: tokenURL.path
        )
    }

    private static func isValid(_ token: String) -> Bool {
        token.range(of: #"^[a-f0-9]{32}$"#, options: .regularExpression) != nil
    }

    private static func defaultTokenURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory

        return base
            .appendingPathComponent("AgentSwarmManagement", isDirectory: true)
            .appendingPathComponent("local-control-token")
    }
}

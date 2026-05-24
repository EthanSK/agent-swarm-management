import CryptoKit
import Foundation

enum HarnessFamily: String, CaseIterable, Identifiable, Codable, Sendable {
    case openClaw = "OpenClaw"
    case codex = "Codex"
    case claudeCode = "Claude Code"
    case generic = "Generic MCP/HTTP"

    var id: String { rawValue }

    var slug: String {
        switch self {
        case .openClaw: "openclaw"
        case .codex: "codex"
        case .claudeCode: "claude-code"
        case .generic: "generic"
        }
    }

    var title: String { rawValue }

    var setupFileName: String {
        switch self {
        case .openClaw: "agent-swarm-management-openclaw.md"
        case .codex: "agent-swarm-management-codex.md"
        case .claudeCode: "agent-swarm-management-claude-code.md"
        case .generic: "agent-swarm-management-integration.md"
        }
    }

    var installLocationHint: String {
        switch self {
        case .openClaw:
            "~/.openclaw/workspace/skills/agent-swarm-management/SKILL.md"
        case .codex:
            "$CODEX_HOME/skills/agent-swarm-management/SKILL.md"
        case .claudeCode:
            "~/.claude/skills/agent-swarm-management/SKILL.md"
        case .generic:
            "Any harness-visible skill, instruction, or MCP configuration folder"
        }
    }

    var description: String {
        switch self {
        case .openClaw:
            "OpenClaw session, Telegram, cron, and local-agent runtimes."
        case .codex:
            "Codex CLI or Codex-hosted coding sessions."
        case .claudeCode:
            "Claude Code sessions, including Agent Bridge-routed Claude agents."
        case .generic:
            "Any agent harness that can make local HTTP or MCP JSON-RPC calls."
        }
    }

    static func match(_ value: String) -> HarnessFamily? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")

        return allCases.first { family in
            family.slug == normalized
                || family.rawValue.lowercased().replacingOccurrences(of: " ", with: "-") == normalized
        }
    }
}

struct SkillPackage: Codable, Sendable {
    var schemaVersion: String
    var harness: String
    var version: String
    var minAppVersion: String
    var files: [SkillPackageFile]
    var configPatches: [SkillConfigPatch]
}

struct SkillPackageFile: Codable, Sendable {
    var relativePath: String
    var mode: String
    var sha256: String
    var content: String
}

struct SkillConfigPatch: Codable, Sendable {
    var target: String
    var kind: String
    var strategy: String
}

struct SkillCheckRequest: Codable, Sendable {
    var harness: String
    var installedVersion: String?
    var installedHash: String?
    var path: String?
}

enum AgentSwarmContract {
    static let apiVersion = "2026-05-24"
    static let skillVersion = "0.1.0"
    static let protocolVersion = "2025-06-18"

    static func setupPayload(baseURL: URL) -> [String: Any] {
        [
            "name": "Agent Swarm Management",
            "apiVersion": apiVersion,
            "skillVersion": skillVersion,
            "baseURL": baseURL.absoluteString,
            "tokenSource": [
                "kind": "local-file",
                "path": LocalControlTokenStore.defaultTokenPath,
                "header": "Authorization: Bearer <contents-of-token-file>"
            ],
            "mcp": [
                "transport": "streamable-http-json-rpc",
                "endpoint": baseURL.appendingPathComponent("mcp").absoluteString,
                "protocolVersion": protocolVersion
            ],
            "rest": [
                "setup": baseURL.appendingPathComponent("v1/setup").absoluteString,
                "registerAgent": baseURL.appendingPathComponent("v1/agents/register").absoluteString,
                "agentEvents": baseURL.appendingPathComponent("v1/agent-events").absoluteString,
                "diagnostics": baseURL.appendingPathComponent("v1/diagnostics").absoluteString,
                "skillPackages": baseURL.appendingPathComponent("v1/skill-packages/{harness}").absoluteString,
                "skillCheck": baseURL.appendingPathComponent("v1/skills/check").absoluteString,
                "status": baseURL.appendingPathComponent("v1/status").absoluteString
            ],
            "requiredHeaders": [
                "Authorization": "Bearer <contents-of-token-file>",
                "Content-Type": "application/json"
            ],
            "harnesses": HarnessFamily.allCases.map { harnessPayload($0, baseURL: baseURL) },
            "registrationSchema": [
                "operationId": "stable idempotency key for this registration attempt",
                "agentName": "human-readable agent/session/persona name",
                "harness": "OpenClaw, Codex, Claude Code, or another harness name",
                "harnessAgentId": "optional stable harness-side id",
                "harnessVersion": "optional harness version",
                "skillVersion": skillVersion,
                "sourceMachine": "optional machine name",
                "capabilities": ["tasks", "followUps", "diagnostics"],
                "status": "healthy | needsAttention | blocked | done",
                "summary": "optional current purpose or health note"
            ]
        ]
    }

    static func harnessPayload(_ family: HarnessFamily, baseURL: URL) -> [String: Any] {
        [
            "id": family.slug,
            "title": family.title,
            "description": family.description,
            "installLocationHint": family.installLocationHint,
            "setupFileName": family.setupFileName,
            "skillVersion": skillVersion,
            "skillPackage": baseURL.appendingPathComponent("v1/skill-packages/\(family.slug)").absoluteString,
            "instructions": skillInstructions(for: family, baseURL: baseURL)
        ]
    }

    static func skillPackage(for family: HarnessFamily, baseURL: URL) -> SkillPackage {
        let content = skillInstructions(for: family, baseURL: baseURL)
        let file = SkillPackageFile(
            relativePath: "SKILL.md",
            mode: "0644",
            sha256: sha256(content),
            content: content
        )

        return SkillPackage(
            schemaVersion: "asm.skillPackage.v1",
            harness: family.slug,
            version: skillVersion,
            minAppVersion: skillVersion,
            files: [file],
            configPatches: configPatches(for: family)
        )
    }

    static func defaultInstallURL(for family: HarnessFamily) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser

        switch family {
        case .openClaw:
            return home
                .appendingPathComponent(".openclaw/workspace/skills/agent-swarm-management", isDirectory: true)
                .appendingPathComponent("SKILL.md")
        case .claudeCode:
            return home
                .appendingPathComponent(".claude/skills/agent-swarm-management", isDirectory: true)
                .appendingPathComponent("SKILL.md")
        case .codex:
            let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
                .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
                ?? home.appendingPathComponent(".codex", isDirectory: true)

            return codexHome
                .appendingPathComponent("skills/agent-swarm-management", isDirectory: true)
                .appendingPathComponent("SKILL.md")
        case .generic:
            return nil
        }
    }

    static func skillInstructions(for family: HarnessFamily, baseURL: URL) -> String {
        let registerURL = baseURL.appendingPathComponent("v1/agents/register").absoluteString
        let eventURL = baseURL.appendingPathComponent("v1/agent-events").absoluteString
        let diagnosticsURL = baseURL.appendingPathComponent("v1/diagnostics").absoluteString
        let setupURL = baseURL.appendingPathComponent("v1/setup").absoluteString
        let mcpURL = baseURL.appendingPathComponent("mcp").absoluteString
        let packageURL = baseURL.appendingPathComponent("v1/skill-packages/\(family.slug)").absoluteString
        let checkURL = baseURL.appendingPathComponent("v1/skills/check").absoluteString

        return """
        ---
        name: agent-swarm-management
        description: Register this harness with Agent Swarm Management, report task/follow-up changes, and diagnose local connectivity.
        ---

        # Agent Swarm Management

        Harness target: \(family.title)
        Skill version: \(skillVersion)
        API version: \(apiVersion)

        ## Local token

        Do not paste or persist the bearer token in this skill. Read it at runtime from:

        \(LocalControlTokenStore.defaultTokenPath)

        Send it as:

        Authorization: Bearer <contents-of-token-file>

        ## Contract

        - Setup: GET \(setupURL)
        - MCP JSON-RPC: POST \(mcpURL)
        - Register/update this agent: POST \(registerURL)
        - Record meaningful work: POST \(eventURL)
        - Skill package: GET \(packageURL)
        - Skill check: POST \(checkURL)
        - Diagnostics: GET \(diagnosticsURL)

        ## Startup behavior

        1. On session start or when this skill version changes, call the setup endpoint.
        2. Register the current agent/persona/session with a stable operationId.
        3. Report meaningful project, task, blocker, follow-up, and proof changes.
        4. Do not ask the user to manually create projects for you in the app; report real work and let Agent Swarm Management create/update records.
        5. If Agent Swarm Management reports a newer skillVersion, reinstall or refresh this skill before continuing.

        ## Registration JSON

        {
          "operationId": "\(family.slug):register:<stable-session-id>",
          "agentName": "<agent/persona/session name>",
          "harness": "\(family.title)",
          "harnessAgentId": "<stable harness id if available>",
          "harnessVersion": "<harness version if available>",
          "skillVersion": "\(skillVersion)",
          "sourceMachine": "<machine name>",
          "capabilities": ["tasks", "followUps", "artifacts", "diagnostics"],
          "status": "healthy",
          "summary": "<what this agent is currently responsible for>"
        }
        """
    }

    static func sha256(_ content: String) -> String {
        let digest = SHA256.hash(data: Data(content.utf8))
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func configPatches(for family: HarnessFamily) -> [SkillConfigPatch] {
        switch family {
        case .openClaw:
            [
                SkillConfigPatch(
                    target: "~/.openclaw/openclaw.json",
                    kind: "mcp-server",
                    strategy: "manual-or-confirmed-merge"
                )
            ]
        case .claudeCode:
            [
                SkillConfigPatch(
                    target: "~/.claude/.mcp.json",
                    kind: "mcp-server",
                    strategy: "manual-or-confirmed-merge"
                ),
                SkillConfigPatch(
                    target: "~/.claude/settings.json",
                    kind: "stop-hook",
                    strategy: "manual-or-confirmed-merge"
                )
            ]
        case .codex:
            [
                SkillConfigPatch(
                    target: "~/.codex/config.toml",
                    kind: "mcp-server",
                    strategy: "manual-or-confirmed-merge"
                )
            ]
        case .generic:
            []
        }
    }
}


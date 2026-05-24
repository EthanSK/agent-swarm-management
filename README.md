# Agent Swarm Management

Native macOS command center for tracking agent-driven projects, tasks, follow-ups, and proof.

This repo contains the first end-user-oriented SwiftUI build. The app seeds recovered sample data on first launch, writes edits to a disposable local cache/outbox, stores secrets in Keychain, can create/query/update Notion data sources, and exposes a localhost JSON endpoint for agent hooks.

The current product direction is Notion-first: Notion is the only durable source of truth for v1, while the Mac app keeps a disposable local cache for speed and offline reading.

## Current Scope

- Menu bar status surface plus full SwiftUI window.
- Projects, agents, follow-ups, and tasks lists.
- Manual create/edit/delete flows.
- Quick status updates for tasks and follow-ups.
- JSON cache/outbox at ~/Library/Application Support/AgentSwarmManagement/workspace.json.
- Keychain-backed Notion token storage.
- Notion schema creation under a user-provided parent page.
- Notion pull/push for projects, agents, tasks, and follow-ups through a one-request-per-second writer.
- Local endpoint at http://127.0.0.1:17391 with bearer-token auth.

## Agent Endpoint

Health check:

    curl http://127.0.0.1:17391/health

Authenticated status:

    curl -H "Authorization: Bearer <token>" http://127.0.0.1:17391/v1/status

Record a meaningful update:

    curl -X POST http://127.0.0.1:17391/v1/agent-events \
      -H "Authorization: Bearer <token>" \
      -H "Content-Type: application/json" \
      -d '{
        "operationId": "machine:harness:session:turn:record_meaningful_change",
        "projectName": "Agent Swarm Management",
        "agentName": "OpenClaw Codex",
        "harness": "OpenClaw",
        "taskTitle": "Wire Notion sync",
        "taskStatus": "needsAttention",
        "summary": "Implemented the Notion-backed sync foundation",
        "sourceTurnId": "telegram:3640",
        "sourceMachine": "MacBook Pro"
      }'

The endpoint token is generated on first launch and stored as a private local
app-support file, not in Keychain. Copy the ready-to-use endpoint JSON from
Settings.

## Build

    npm run build:mac

The packaged build writes:

- dist/Agent Swarm Management.app
- release/Agent-Swarm-Management-<version>-mac-universal.zip
- release/Agent-Swarm-Management-latest-mac-universal.zip

The build verifies that the Sparkle framework is embedded, that the executable
has the correct @executable_path/../Frameworks runtime search path, and that the
bundle passes code-signature validation.

## Run

    swift run --package-path /Users/ethansarif-kattan/Projects/agent-swarm-management AgentSwarmManagement

The executable is a SwiftUI app shell. Running it opens a normal window, starts the local endpoint, and adds a menu bar extra when launched from a GUI-capable macOS session.

## Install Locally

    npm run install:mac

This builds the app, moves any existing /Applications/Agent Swarm Management.app
to the Trash, installs the new bundle, and clears quarantine metadata for local
testing.

## Auto Updates

Agent Swarm Management uses Sparkle 2 for the native macOS update UX. Producer
Player uses Electron's updater stack, but the release/versioning shape is mirrored:

- package.json is the single version source.
- Versions use Producer-style x.y.0 internal semver with v<x.y> display tags.
- GitHub Actions builds the macOS zip, generates checksums, signs the Sparkle
  appcast, and publishes stable latest assets.
- The app reads appcast.xml from the latest GitHub release.

Required GitHub Actions secrets for real public updates:

- SPARKLE_PRIVATE_KEY
- CSC_LINK
- CSC_KEY_PASSWORD
- APPLE_ID
- APPLE_APP_SPECIFIC_PASSWORD
- APPLE_TEAM_ID

Local ad-hoc builds can launch and be tested, but real Sparkle updates should be
Developer ID signed, notarized, and appcast-signed before users rely on them.

## Credentials

The local agent endpoint does not require a user credential and does not use
Keychain. Notion is different: because Notion is the user-owned source of truth,
the app must eventually receive Notion authorization from the user. Local/dev
builds support a manually pasted Notion token stored in Keychain; public builds
should use a proper Notion OAuth flow so users authorize in Notion instead of
handling raw tokens.

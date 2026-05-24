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

The endpoint token is generated on first launch and stored in Keychain. Copy the ready-to-use endpoint JSON from Settings.

## Build

    swift build --package-path /Users/ethansarif-kattan/Projects/agent-swarm-management

## Run

    swift run --package-path /Users/ethansarif-kattan/Projects/agent-swarm-management AgentSwarmManagement

The executable is a SwiftUI app shell. Running it opens a normal window, starts the local endpoint, and adds a menu bar extra when launched from a GUI-capable macOS session.

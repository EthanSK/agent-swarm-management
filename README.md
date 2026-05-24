# Agent Swarm Management

Native macOS command center for tracking agent-driven projects, tasks, follow-ups, and proof.

This repo currently contains the first planning pass and a SwiftUI scaffold. The app seeds recovered sample data on first launch, writes edits to JSON for the prototype, and keeps Notion plus the MCP control surface behind typed seams for later phases.

The current product direction is Notion-first: Notion is the only durable source of truth for v1, while the Mac app keeps a disposable local cache for speed and offline reading.

## Current Scope

- Menu bar status surface plus full SwiftUI window.
- Projects, agents, follow-ups, and tasks lists.
- Manual create/edit/delete flows.
- Quick status updates for tasks and follow-ups.
- Prototype JSON cache at `~/Library/Application Support/AgentSwarmManagement/workspace.json`.
- Stub Notion client, cache/sync queue, and local control server modules.

## Build

    swift build --package-path /Users/ethansarif-kattan/Projects/agent-swarm-management

## Run

    swift run --package-path /Users/ethansarif-kattan/Projects/agent-swarm-management AgentSwarmManagement

The executable is a SwiftUI app shell. Running it opens a normal window and a menu bar extra when launched from a GUI-capable macOS session.

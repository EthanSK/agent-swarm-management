# Agent Swarm Management

Native macOS command center for tracking agent-driven projects, tasks, follow-ups, and proof.

This repo currently contains the first planning pass and a local-first SwiftUI scaffold. The app seeds recovered sample data on first launch, writes edits to JSON, and keeps Notion sync plus the MCP control surface behind typed seams for later phases.

## Current Scope

- Menu bar status surface plus full SwiftUI window.
- Projects, agents, follow-ups, and tasks lists.
- Manual create/edit/delete flows.
- Quick status updates for tasks and follow-ups.
- Local JSON cache at `~/Library/Application Support/AgentSwarmManagement/workspace.json`.
- Stub Notion client, sync queue, and local control server modules.

## Build

    swift build --package-path /Users/ethansarif-kattan/Projects/agent-swarm-management

## Run

    swift run --package-path /Users/ethansarif-kattan/Projects/agent-swarm-management AgentSwarmManagement

The executable is a SwiftUI app shell. Running it opens a normal window and a menu bar extra when launched from a GUI-capable macOS session.

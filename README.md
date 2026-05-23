# Agent Swarm Management

Native macOS command center for tracking agent-driven projects, tasks, follow-ups, and proof.

This repo currently contains the first planning pass and a small SwiftUI scaffold. The scaffold uses sample data while the Notion sync and MCP control surface are designed in separate modules.

## Build

    swift build --package-path /Users/ethansarif-kattan/Projects/agent-swarm-management

## Run

    swift run --package-path /Users/ethansarif-kattan/Projects/agent-swarm-management AgentSwarmManagement

The executable is a SwiftUI app shell. Running it opens a normal window and a menu bar extra when launched from a GUI-capable macOS session.


# Agent Swarm Management

Agent Swarm Management is a native macOS command center for keeping AI-agent work visible: projects, agents, tasks, follow-ups, blockers, and proof in one place.

The app is designed for people coordinating multiple coding agents across machines and chats. It gives you a local Mac UI, a menu bar status surface, and a localhost endpoint that agents can report into.

## Status

This project is early alpha. The current build is useful for local testing and product direction, but the public update channel and Notion OAuth onboarding are still being finished.

Currently implemented:

- Native SwiftUI macOS app with menu bar and full-window views.
- Projects, agents, tasks, and follow-ups.
- Local JSON cache/outbox for fast startup and offline reading.
- Localhost agent-reporting endpoint with bearer-token auth.
- Notion data-source sync foundation.
- Sparkle-based macOS auto-update wiring.
- GitHub release workflow for signed appcast and release assets.

## Product Direction

Notion is intended to be the durable source of truth for v1. The local app cache is disposable: it exists for speed, offline reading, and queued writes, not as a second backend.

The open-source goal is that users can bring their own Notion workspace instead of trusting a hosted Agent Swarm backend. Public builds should use Notion OAuth so users authorize in Notion rather than handling raw tokens.

## Install

There is not a published public release yet. Until the first release is cut, build from source:

    git clone https://github.com/EthanSK/agent-swarm-management.git
    cd agent-swarm-management
    npm ci
    npm run install:mac

The local install command builds the app, installs it to /Applications/Agent Swarm Management.app, and launches can be verified with:

    curl http://127.0.0.1:17391/health

## Notion Setup

For local development, Settings supports a manually supplied Notion token and parent page ID. That token is stored in Keychain only after the user explicitly saves it or runs a Notion action.

For end users, the intended UX is OAuth:

- the user connects Notion deliberately;
- Notion shows the authorization screen;
- Agent Swarm Management stores only the resulting authorization material;
- no Keychain prompt appears just from opening the app.

## Agent Endpoint

The app exposes a local endpoint for agents and hooks:

- Health: GET http://127.0.0.1:17391/health
- Status: GET http://127.0.0.1:17391/v1/status
- Events: POST http://127.0.0.1:17391/v1/agent-events

The endpoint bearer token is generated locally and stored as a private app-support file, not in Keychain. Copy the ready-to-use endpoint JSON from Settings.

Example event:

    curl -X POST http://127.0.0.1:17391/v1/agent-events \
      -H "Authorization: Bearer <token>" \
      -H "Content-Type: application/json" \
      -d '{
        "operationId": "machine:harness:session:turn:record_meaningful_change",
        "projectName": "Agent Swarm Management",
        "agentName": "OpenClaw",
        "harness": "OpenClaw",
        "taskTitle": "Wire Notion sync",
        "taskStatus": "needsAttention",
        "summary": "Implemented the Notion-backed sync foundation",
        "sourceTurnId": "telegram:3640",
        "sourceMachine": "MacBook Pro"
      }'

## Auto Updates

Agent Swarm Management uses Sparkle 2 for native macOS updates.

The release workflow is modeled after Producer Player's proven release discipline:

- package.json is the single version source.
- Versions use x.y.0 internal semver and v<x.y> display tags.
- GitHub Actions builds the macOS zip.
- Sparkle appcast generation signs the update feed.
- Stable latest assets are published for the appcast and download links.

Real public updates require GitHub Actions secrets:

- SPARKLE_PRIVATE_KEY
- CSC_LINK
- CSC_KEY_PASSWORD
- APPLE_ID
- APPLE_APP_SPECIFIC_PASSWORD
- APPLE_TEAM_ID

Local ad-hoc builds can launch and be tested, but real user updates should be Developer ID signed, notarized, and appcast-signed.
When those release secrets are absent, GitHub Actions still builds and uploads desktop artifacts, then skips GitHub Release/appcast publishing cleanly.

## Development

Build:

    npm run build:mac

Verify:

    npm run version:check
    npm run version:bump:check
    npm run verify:mac
    ./scripts/smoke-launch-mac-app.sh "/Applications/Agent Swarm Management.app" --keep-running

Install locally:

    npm run install:mac

## Security Notes

- The local agent endpoint token is not a user credential and does not use Keychain.
- The app avoids passive Keychain reads on launch and Settings render.
- Keychain access is reserved for explicit Notion authorization actions.
- The local cache is not the durable source of truth; Notion is.

## Roadmap

Near-term work:

- Replace manual Notion-token setup with OAuth.
- Add a polished first-run setup flow.
- Add a formal MCP wrapper/manifest for agent clients.
- Create the first signed and notarized public release.
- Add app icon, launch-at-login, and notification polish.

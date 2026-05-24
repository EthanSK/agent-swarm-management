# Agent Swarm Management Plan

## Product Goal

Agent Swarm Management is a native macOS-first command center for keeping many AI agents, projects, tasks, follow-ups, and artifacts visible without living inside one long chat thread.

The app name and repository folder should use kebab case:

- Product name: Agent Swarm Management
- Folder/repo name: agent-swarm-management

The first useful version should answer four questions quickly:

- Which projects are active?
- Which agents are working on each project?
- What needs Ethan's attention or approval?
- What changed since Ethan last looked?

The long-term product can grow into iOS and deeper agent orchestration, but v1 should stay sharply focused: a native Mac menu bar app that expands into a full window, backed by Notion as the only durable source of truth and a disposable local cache for speed/offline reading.

## Source Context

Inputs recovered from the failed Telegram voice-note window:

- Voice 3584: original request to read the Notion ideas, search MacBook/Mac Mini history, explain the structure/plan, and use extra high effort.
- Voices 3592/3593: build direction, OAuth/API-limit questions, Notion root-page model, many-to-many project/agent views, MCP/HTTP control surface, Claude Code/OpenClaw plugin hooks, native SwiftUI direction, and follow-up questions view.
- Voice 3596: "are you still running?" check after the prior OpenClaw session stalled.

Notion sources read:

- https://www.notion.so/3491af4282dd80c09b4afff3d5af3b2f
- https://www.notion.so/34d1af4282dd81159282c6e5b4ded161
- https://www.notion.so/3491af4282dd806b8d52d83405fdb135

Mac Mini history search only found prior memory that the Notion page was created on 2026-04-25 and that no implementation repo existed yet.

## Core Product Shape

The app is not just a generic todo list. It is a todo/task system with agent context:

- Projects are top-level workspaces.
- Agents are workers/harnesses/chats that can be attached to one or more projects.
- Runs are individual agent attempts or sessions.
- Tasks are concrete work items, often recursive.
- Follow-ups are questions, decisions, approvals, or reminders that need the human.
- Artifacts are links to transcripts, PRs, screenshots, files, Notion pages, builds, or final proof.

The same data should be visible in different slices:

- Project view: one project, all tasks, agents, runs, blockers, proof.
- Agent view: one agent, all projects it is touching, recent outputs, open follow-ups.
- Follow-up view: everything waiting on Ethan, grouped by urgency/project/agent.
- Task view: plain todo list mode for quick scanning and edits.

## Source Of Truth And Notion Model

Use Notion as the only durable source of truth for v1. Ethan wants the project to stay open-source and zero-backend: users should be able to connect their own Notion workspace, authenticate themselves, and own the resulting data without paying for or trusting a hosted Agent Swarm backend.

The local app may keep a cache, but the cache is not a second source of truth. It is a performance/offline-read artifact that can be discarded and rebuilt from Notion. Mutations are considered durable only once written to Notion.

The practical constraint is write granularity. Notion can query a data source for multiple page rows and can append up to 100 blocks to one parent, but updating the status of 50 agent/task rows is still 50 separate PATCH /v1/pages/{id} calls. There is no multi-page batch write endpoint. Because each integration also shares the same rate limit pool across machines, all Notion writes should go through one coordinator in the Mac app rather than direct writes from every agent hook.

The coordinator can exist on more than one device. A MacBook agent should be able to talk to the MacBook app endpoint, and a Mac Mini agent should be able to talk to the Mac Mini app endpoint. Those app instances are local coordinators for their own machine, but they all persist durable state into the same Notion root page and data sources. Notion page IDs are the canonical record IDs, so both devices can update the same project/task/agent records without requiring a hosted Agent Swarm backend.

Multi-device v1 rule:

- Each device runs its own localhost HTTP/MCP endpoint for local agents.
- Each device keeps a disposable cache and a Notion write queue.
- Every mutation carries an operation ID derived from machine ID, harness, session/chat ID, source turn ID, and command name.
- Every durable record stores the source machine/harness/session that last changed it.
- Duplicate operation IDs are ignored before writing to Notion.
- If two devices update different fields on the same Notion page, merge them when safe.
- If two devices update the same field, newest confirmed Notion edit wins by default and the loser becomes a Follow-up/Sync Issue when data loss is possible.
- The combined write load still needs to respect Notion's per-connection rate limit, so hooks should coalesce aggressively and avoid heartbeat/status spam.

Pure Notion is acceptable if the app is designed as deliberately low-volume:

- Sustained writes stay comfortably below about 30 updates per minute.
- Agents emit only meaningful state transitions, not heartbeat spam.
- The app owns a client-side queue, backoff, and retry policy, but queued operations are marked pending until Notion confirms them.
- Repeated updates to the same record are coalesced before hitting Notion.

If measured write volume goes materially above that, revisit the backend decision. Firestore is technically better for realtime app state, but it weakens the open-source/bring-your-own-backend story. The v1 default remains Notion-only unless the product proves it cannot function within Notion's constraints.

Notion object model:

- A database is a Notion object that lives in a parent page either inline or as a full-page database.
- In the current API model, a database contains one or more data sources.
- A data source is the actual table/schema that contains rows.
- Each row in a data source is a Notion page with properties and optional page body blocks.
- Board/list/table/calendar are views over the same underlying data, not separate storage.

Recommended Notion layout:

- Root page: Agent Swarm Management
- Data source: Projects
- Data source: Agents
- Data source: Runs
- Data source: Tasks
- Data source: Follow-ups
- Data source: Artifacts

Recommended Notion views:

- Projects table grouped by status.
- Tasks board grouped by status for human inspection in Notion.
- Tasks table filtered by project for dense scanning.
- Follow-ups calendar/list grouped by urgency and waiting-on.
- Agents health table grouped by harness/persona.
- Runs/events timeline sorted by last meaningful update.

The board view should exist in Notion, but it should not be special in the app model. It is a view over Tasks so users can open Notion and see the same state in a familiar board if the native app is unavailable.

Pragmatic v1:

- Keep the Notion structure simple.
- Prefer one root page with child databases where possible.
- Create at least one board view for Tasks because it is useful for Notion-native fallback inspection.
- Store enough relation IDs to create project <-> agent many-to-many views.
- Let the native app cache and index Notion content locally for speed.
- Prefer denormalized plain properties for app-critical display state so the app does not depend on deep rollups/formulas.

Tasks can be recursive Notion pages, but the app should normalize them into a stable local model:

- id
- title
- status
- projectId
- assignedAgentIds
- parentTaskId
- childTaskIds
- sourcePageId
- lastUpdatedBy
- lastMeaningfulChangeAt
- artifacts

## Auth And Open-Source Constraints

Notion supports internal connections, personal access tokens, and public OAuth connections.

For a local open-source app:

- Do not ship a Notion client secret in the app.
- Local/dev mode can use a user-supplied Notion token or personal access token stored in Keychain.
- Public distribution should use OAuth through a small hosted broker because a native app cannot safely keep the OAuth client secret private.
- If there is no broker, use a manual "create a Notion connection and paste token" onboarding flow.

Answer to "is it free on Notion?":

- The app can use a user's own Notion workspace/account.
- Notion API access is available through the user's connection/token, subject to the user's Notion permissions and plan.
- The app itself does not need to charge for Notion access, but public OAuth, hosting an auth broker, and future app-store distribution have operational costs.

Official Notion docs checked 2026-05-24:

- Incoming requests are rate limited to an average of three requests per second per connection.
- 429 responses include a Retry-After header that must be respected.
- Request payloads are limited, including 1000 block elements and 500KB overall.
- Rich text content values are limited to 2000 characters.

## Cache And Sync Strategy

The app should read from Notion through a local cache rather than every UI render hitting the Notion API. Reading directly from Notion for every screen would make the app feel slow, increase rate-limit pressure, and break basic offline viewing.

Local cache:

- Store normalized records locally as cached state only.
- Keep a source Notion page/database ID for each record.
- Track local pending changes separately from confirmed Notion state.
- Track last successful sync timestamp and last remote edit timestamp.
- Treat cache deletion/rebuild as safe; Notion is the durable source.

Offline behavior:

- Offline read is supported from the last known Notion state.
- Offline mutation should start conservative: disabled by default, with clear disabled controls and a visible offline badge.
- Optional later mode: allow offline writes into an outbox, but show them as pending and unsynced until Notion accepts them.
- Never claim a queued offline task/update is complete until it is written to Notion.

Write queue:

- Coalesce repeated changes to the same record.
- Respect Notion's average three requests per second.
- Cap ordinary Notion mirror writes well below the limit, targeting roughly one request per second unless the user explicitly starts a sync.
- On HTTP 429, pause that connection using Retry-After.
- On validation errors, mark the specific item as blocked and show it in Follow-ups/Sync Issues.
- Use idempotency-style local operation IDs so a failed/retried hook update does not create duplicate tasks.
- Route all local-machine agent writes through that machine's app coordinator so the rate limiter sees the full local workload.
- For multi-device setups, treat Notion as the cross-device coordination layer in v1. Each device throttles its own queue, coalesces writes before sending, and pulls after confirmed writes so other devices converge through Notion.
- A later LAN/Tailscale coordinator election can centralize rate limiting if real usage shows two independent device queues hitting the same Notion connection too hard.

Read strategy:

- Pull on app launch.
- Pull after wake/network return.
- Pull after a local agent hook reports a meaningful update.
- Poll lightly only while the app is visible or menu bar status is open.

Conflict policy:

- If only Notion changed, refresh the local cache.
- If a local pending write conflicts with a newer Notion edit, preserve the Notion-authored value and create a Follow-up requiring user choice.
- Never silently overwrite user-authored Notion edits with stale queued data.

## Native macOS Architecture

Use SwiftUI for the app shell and shared views:

- Menu bar compact view via MenuBarExtra.
- Full window via WindowGroup.
- Shared components for project rows, agent rows, follow-up rows, and task status badges.
- App state through ObservableObject or Observation.
- Keychain for Notion tokens.
- URLSession for Notion API and local MCP/HTTP server calls.
- Local persistence starts as JSON for the first scaffold, but should move to SQLite/GRDB before real Notion sync if cache size/query needs justify it. SQLite/GRDB is still a cache, not the durable source of truth. SwiftData can wait until it clearly removes more complexity than it adds.

Suggested modules:

- App: SwiftUI app entry, scene setup, menu bar/full window shell.
- Models: Project, Agent, Run, Task, FollowUp, Artifact, status enums.
- Views: Projects, Agents, Follow-ups, Tasks, Settings.
- Notion: auth, API client, schema mapper.
- Sync: queue, rate limiter, conflict handling, local cache.
- MCP: local HTTP/MCP control surface for agents.
- Integrations: Claude Code hook, OpenClaw hook, Agent Bridge inspiration/helpers.

## Views

### Menu Bar View

Compact status:

- Active projects count.
- Running agents count.
- Follow-ups waiting count.
- Blocked items count.
- Last meaningful update.

Actions:

- Open full window.
- Copy local MCP endpoint.
- Pause/resume agent updates.
- Quick add task/follow-up.

### Projects View

Each project row should show:

- Name.
- Status.
- Active agents.
- Open tasks.
- Follow-ups.
- Last meaningful change.

Project detail should show:

- Project summary.
- Tasks.
- Agents.
- Runs.
- Artifacts/proof.
- Decision history.

### Agents View

Each agent row should show:

- Agent name/harness/chat.
- Current status.
- Projects touched.
- Last update.
- Open follow-ups.
- Recent artifacts.

Agent detail should show:

- Projects this agent is working on.
- Recent turns/runs.
- Questions asked to Ethan.
- Hook health.
- Last successful state update.

### Follow-Ups View

This is a first-class surface, not a notification afterthought.

Each follow-up should show:

- Question or decision needed.
- Project.
- Agent/run that asked it.
- Age.
- Urgency.
- Reply/action affordance.
- Stop/remind policy if applicable.

This view directly addresses Ethan's recurring problem: important agent questions get lost in long chats.

### Tasks View

Keep it simple for v1:

- Todo/done/blocker statuses.
- Group by project.
- Optional filter by agent.
- Recursive child tasks later.

Avoid implementing a complex custom board first. Notion boards can remain a source-side convenience; the native app should first ship a fast, reliable list/detail workflow.

## MCP And HTTP Control Surface

The app should expose a local control surface so agents can update it without screen scraping:

- Local HTTP endpoint, bound to localhost by default.
- MCP server wrapper over the same commands.
- Shared operation schema for both.
- Local auth token stored in Keychain and shown/copyable from Settings.

Multi-device topology:

- On MacBook: agents connect to the MacBook app endpoint.
- On Mac Mini: agents connect to the Mac Mini app endpoint.
- Both endpoints expose the same command schema and write to the same Notion workspace/root page when configured with the same Notion connection.
- Agents do not need to know whether another device exists; they report local state to their nearest coordinator.
- The app can later expose an optional Tailscale/LAN endpoint for remote agents, but v1 should not require cross-device RPC because Notion already provides durable convergence.
- The UI should show which device last updated a record and whether that record is pending, confirmed, conflicted, or blocked.

Initial commands:

- upsert_project
- upsert_agent
- start_run
- update_run_status
- upsert_task
- upsert_follow_up
- resolve_follow_up
- attach_artifact
- record_meaningful_change
- get_open_follow_ups
- get_project_status

Rules for agent updates:

- Agents should update only when state meaningfully changes.
- Post-turn hooks should be resilient: failure to update Agent Swarm Management must not fail the user's main agent turn.
- Updates should include source harness, session/chat ID, project ID/name, and transcript/artifact pointers.
- Hooks must dedupe by operation ID and source turn ID.

## Claude Code And OpenClaw Integration

Use Agent Bridge as inspiration: setup should be explicit, local, and reversible.

Claude Code plan:

- Provide a small plugin or hook installer.
- Register a post-turn hook.
- Hook reads the latest turn metadata and sends a concise state update to the local app endpoint.
- Hook can be disabled per repo/session.

OpenClaw plan:

- Provide an OpenClaw skill or plugin instruction file.
- Add a post-turn/reporting hook where supported.
- For Telegram/voice-note sessions, include chat ID, message ID, transcript pointer, and reply status.
- Use the same local endpoint and operation schema as Claude Code.

Setup flow:

1. Install/run the Mac app.
2. Connect Notion token/OAuth.
3. App creates or verifies the Notion root page/schema.
4. App shows local endpoint and auth token.
5. User runs the Claude/OpenClaw setup command.
6. Hook sends a test update.
7. App shows hook health and last test event.

## Phased Roadmap

### Phase 0: Planning and skeleton

- Create this repository.
- Write architecture plan.
- Add minimal native SwiftUI scaffold.
- Add sample data so views are inspectable before Notion is wired.

### Phase 1: Local-only app

- Menu bar and full window.
- Project/Agent/Follow-up/Task views.
- Local JSON persistence.
- Manual create/edit/complete.

Status as of 2026-05-24:

- Implemented the first local-only slice.
- The app seeds recovered sample data, persists to `~/Library/Application Support/AgentSwarmManagement/workspace.json`, and exposes manual create/edit/delete flows for projects, agents, tasks, and follow-ups.
- Tasks and follow-ups have context-menu status updates; project counters are recomputed from local records.

### Phase 2: Notion-only source of truth and local cache

- Token onboarding via Keychain.
- Root page/schema detection.
- Create/verify Notion root page, data sources, and views.
- Pull Notion records into a disposable local cache.
- Push app edits through a queued Notion writer.
- Add offline read mode from last known cache.
- Keep offline writes disabled at first, or mark them clearly as pending outbox items.
- Rate-limit and validation handling.
- Measure sustained write volume before enabling broad agent-driven updates.

Status as of 2026-05-24:

- Implemented Keychain-backed Notion token storage and Settings fields for the parent page, API version, and data source IDs.
- Implemented a Notion client for the current data source API version, including schema creation under a supplied parent page, data source queries, page creates/updates, page trashing, and Retry-After handling.
- Added a persisted local outbox to workspace.json. App edits enqueue Notion operations, coalesce repeated upserts for the same record, and only mark operations done after Notion confirms the write.
- Added pull and push actions in Settings. Pull treats Notion as authoritative; push uses a conservative one-request-per-second writer to stay below Notion's shared average rate limit.
- Live Notion writes were not run during implementation; the app now has the code path, but real workspace mutation should happen through the Settings UI with Ethan's selected parent page/token.

### Phase 3: Agent control surface

- Local HTTP endpoint.
- MCP wrapper.
- Operation IDs and dedupe.
- Hook health/status UI.

Status as of 2026-05-24:

- Implemented the localhost HTTP surface at http://127.0.0.1:17391 with bearer-token auth generated into Keychain.
- Implemented GET /health, GET /v1/status, and POST /v1/agent-events.
- Agent event writes dedupe by operationId, upsert project/agent/task/follow-up records, and feed the same Notion outbox as manual UI edits.
- Verified the launched app served /health successfully.
- The endpoint is MCP-style JSON HTTP now. A formal MCP wrapper/manifest remains a next slice.

### Phase 4: Claude Code/OpenClaw hooks

- Claude Code post-turn hook.
- OpenClaw integration notes/plugin/skill.
- Test with real sessions.
- Show transcript/artifact links in the app.

### Phase 5: Full build/run polish

- Real macOS app bundle.
- App icon.
- Launch at login.
- Notifications.
- Settings and diagnostics.
- Import/export.

Status as of 2026-05-24:

- Added Sparkle 2 as the native macOS updater. This is the SwiftUI equivalent of Producer Player's Electron updater path: the app gets standard check/download/install/relaunch UX instead of a custom updater.
- Added Settings toggles for automatic checks, automatic downloads, manual Check for Updates, and a direct Releases link.
- Added Producer Player-style version management with package.json as the single source, x.y.0 internal versions, sync/check/bump scripts, stable latest macOS asset names, checksums, and a GitHub release workflow.
- Added a macOS bundle build/install path that embeds Sparkle, signs the app, creates versioned and stable zip artifacts, and validates the runtime framework path.
- Investigated the 2026-05-24 launch crash. Root cause was a packaged app missing the Sparkle runtime framework/rpath at launch (dyld: Library not loaded: @rpath/Sparkle.framework/Versions/B/Sparkle). The build now verifies the embedded framework and @executable_path/../Frameworks rpath before it can pass.
- Added a local launch smoke script that opens the packaged app, checks the /health endpoint, and fails if a new crash report appears.
- Removed Keychain usage for the generated local control endpoint token after launch prompted for credentials in local testing. That token is now stored as a private app-support file; Keychain remains reserved for actual Notion auth material until public OAuth replaces manual token setup.
- Removed passive Keychain reads from Settings rendering. The app no longer reads the Notion token just to display a preview, because a restored Settings window could otherwise trigger a scary first-launch "confidential information" prompt. Keychain access now happens only after explicit Notion actions such as saving a token, creating data sources, pulling, or pushing.

### Phase 6: iOS and public distribution

- iOS read/check-in app.
- OAuth broker.
- Optional App Store distribution.
- Public docs for open-source setup.

## Near-Term Implementation Decisions

- Build native Mac first in SwiftUI.
- Keep v1 list/detail, not board-first.
- Use Notion as the only durable source of truth for v1; local persistence is cache/outbox only.
- Keep Firestore out of v1 unless measured write volume or remote live-dashboard requirements prove Notion-only cannot work.
- Create Notion-native board/table/calendar views so users can inspect and edit state directly in Notion.
- Denormalize app-critical status/name/count fields into plain properties instead of relying on deep rollups.
- Use a local HTTP/MCP endpoint for agent writes.
- Make Follow-ups a top-level view.
- Avoid public OAuth until there is a tiny broker.
- Keep every hook failure non-blocking for the main agent run.

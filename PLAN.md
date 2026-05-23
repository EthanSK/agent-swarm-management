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

The long-term product can grow into iOS and deeper agent orchestration, but v1 should stay sharply focused: a native Mac menu bar app that expands into a full window, backed by Notion as the human-readable source of truth.

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

## Notion Model

Use Notion as v1 source of truth because Ethan already thinks in Notion pages and wants open-source/local tooling rather than a hosted SaaS dependency.

Recommended Notion layout:

- Root page: Agent Swarm Management
- Database or page collection: Projects
- Database or page collection: Agents
- Database or page collection: Runs
- Database or page collection: Tasks
- Database or page collection: Follow-ups
- Database or page collection: Artifacts

Pragmatic v1:

- Keep the Notion structure simple.
- Prefer one root page with child databases where possible.
- Avoid requiring a board view on day one.
- Store enough relation IDs to create project <-> agent many-to-many views.
- Let the native app cache and index Notion content locally for speed.

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

## Sync Strategy

The sync layer should be queue-first, not "write immediately from every UI event".

Local state:

- Store normalized records locally.
- Keep a source Notion page/database ID for each record.
- Track local dirty changes separately from remote state.
- Track last successful sync timestamp and last remote edit timestamp.

Write queue:

- Coalesce repeated changes to the same record.
- Respect Notion's average three requests per second.
- On HTTP 429, pause that connection using Retry-After.
- On validation errors, mark the specific item as blocked and show it in Follow-ups/Sync Issues.
- Use idempotency-style local operation IDs so a failed/retried hook update does not create duplicate tasks.

Read strategy:

- Pull on app launch.
- Pull after wake/network return.
- Pull after a local agent hook reports a meaningful update.
- Poll lightly only while the app is visible or menu bar status is open.

Conflict policy:

- If only one side changed, apply it.
- If both sides changed, keep both versions and create a Follow-up requiring user choice.
- Never silently overwrite user-authored Notion edits with stale agent data.

## Native macOS Architecture

Use SwiftUI for the app shell and shared views:

- Menu bar compact view via MenuBarExtra.
- Full window via WindowGroup.
- Shared components for project rows, agent rows, follow-up rows, and task status badges.
- App state through ObservableObject or Observation.
- Keychain for Notion tokens.
- URLSession for Notion API and local MCP/HTTP server calls.
- Local persistence can start as JSON/SQLite, then graduate to SwiftData if it helps.

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

### Phase 2: Notion integration

- Token onboarding via Keychain.
- Root page/schema detection.
- Pull Notion records.
- Push local changes through queued sync.
- Rate-limit and validation handling.

### Phase 3: Agent control surface

- Local HTTP endpoint.
- MCP wrapper.
- Operation IDs and dedupe.
- Hook health/status UI.

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

### Phase 6: iOS and public distribution

- iOS read/check-in app.
- OAuth broker.
- Optional App Store distribution.
- Public docs for open-source setup.

## Near-Term Implementation Decisions

- Build native Mac first in SwiftUI.
- Keep v1 list/detail, not board-first.
- Use Notion as source of truth, but cache locally.
- Use a local HTTP/MCP endpoint for agent writes.
- Make Follow-ups a top-level view.
- Avoid public OAuth until there is a tiny broker.
- Keep every hook failure non-blocking for the main agent run.


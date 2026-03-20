# Symphony Elixir

<!-- Replace OWNER/REPO with your GitHub username/repo -->
[![CI](https://github.com/OWNER/REPO/actions/workflows/ci.yml/badge.svg)](https://github.com/OWNER/REPO/actions/workflows/ci.yml)

Orchestrate AI agents from your issue board. Symphony monitors issues, assigns them to AI agent processes, and lets you track everything through a built-in web UI — no external services required.

Supports [GitLab](https://gitlab.com) Issues or a **built-in local Kanban board**. Cross-platform (macOS, Linux, Windows).

---

## Get Started

### 1. Install Elixir & Erlang/OTP

Elixir runs on the Erlang VM (BEAM), so both are needed. Package managers handle this automatically.

<details>
<summary><strong>macOS</strong> (Homebrew)</summary>

```bash
brew install elixir    # installs Erlang/OTP automatically
```
</details>

<details>
<summary><strong>Linux</strong> (Debian/Ubuntu)</summary>

```bash
sudo apt-get install elixir erlang    # or use asdf/mise for version management
```
</details>

<details>
<summary><strong>Windows</strong> (elixir-install)</summary>

```powershell
curl.exe -fsSO https://elixir-lang.org/install.bat
.\install.bat elixir@1.19 otp@28    # installs both Elixir and Erlang/OTP

# Add to PATH for the current session
$dir = "$env:USERPROFILE\.elixir-install\installs"
$env:PATH = "$dir\otp\28.1\bin;$dir\elixir\1.19.5-otp-28\bin;$env:PATH"
```

To persist across sessions, add the `$env:PATH` line to your PowerShell profile (`notepad $PROFILE`).
</details>

### 2. Run Symphony

**Local board** (zero config):

```bash
cd elixir
mix setup && mix escript.build
escript symphony_elixir --workflow ../Workflow.local.md --port 4545
```

Then open:
- **http://localhost:4545/board** — Product Hub, Kanban board & all UI

**With GitLab** — set your API key and point to your workflow:

```bash
export GITLAB_API_TOKEN="glpat-..."
mix escript.build
escript symphony_elixir --workflow ../Workflow.md --port 4545
```

### 3. Configure AI Agents

Symphony dispatches issues to AI agents via [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`claude --print`). Claude Code uses your Claude subscription (Pro, Team, or Enterprise) — no API key or separate billing needed.

**First-time setup:**

1. Install Claude Code: `npm install -g @anthropic-ai/claude-code`
2. Log in to your Claude account: `claude login`
3. Follow the browser prompt to authenticate via OAuth

That's it — Symphony will use your logged-in Claude session when dispatching agents.

| Environment Variable | Description |
|---|---|
| `GITLAB_API_TOKEN` | GitLab personal access token (only needed with `tracker.kind: gitlab`) |

You can also configure the agent provider and model at runtime via the **Settings UI** (`http://localhost:4545/board/settings`), or in `Workflow.md` front-matter:

```yaml
agent_process:
  command: claude              # agent binary (default: "claude")
  approval_policy: never       # tool approval: "never", "unless-allow-listed"
```

---

## What You Get

### Product Hub

The default landing page. Products group multiple projects into a single deliverable (e.g. "B2C API" = data-api + frontend + docs).

| Tab | Description |
|---|---|
| **Spec Sheet** | Feature completeness matrix across all projects (colour-coded cells, per-feature and per-project scores) |
| **Issues** | Kanban board filtered to the selected product |
| **Activity** | Recent issue activity timeline |
| **Knowledge Base** | Search and browse KB notes scoped to the product |

AI-assisted feature generation, gap analysis, code review, and product definition generation.

### Kanban Board

A full-featured issue board with no external dependencies.

| Capability | Details |
|---|---|
| Issue management | Create, edit, delete, drag-and-drop between columns |
| Priority & labels | 5 priority levels (colour-coded), free-form label tags |
| Projects | Group issues by project, optional repo cloning |
| Inline issue editing | Edit issues directly on the detail page (title, state, priority, labels, project, product, description) |
| Agent integration | Issues dispatched to AI agents, follow-ups proposed and reviewed |
| Plan-first mode | Agent plans before implementing; plan review & approval workflow |
| Token exhaustion detection | Automatically stops dispatching when LLM reports token budget exhaustion |
| Keyboard shortcuts | `N` new issue, `J/K` navigate, `P` projects, `R` refresh, `?` explain mode |
| Auto-refresh | Polls every 10 seconds |
| Persistence | JSON file survives restarts (`local_board.json`) |

### Board States

```
Backlog → Todo → In Progress → Review → Done → Archived
                                                  ↳ Cancelled
```

| State | Meaning |
|---|---|
| **Backlog** | Default for new issues |
| **Todo** | Ready for an agent to pick up |
| **In Progress** | Agent actively working |
| **Review** | Has follow-up proposals to accept/reject |
| **Done** | Completed (auto-archives after 1 day) |
| **Cancelled** | Manually cancelled |

### Pipelines

Visual pipeline designer for multi-step agent workflows. Build directed graphs of nodes (issue creation, agent runs, human gates, quality gates, KB sync, loops) and execute them with full control.

| Capability | Details |
|---|---|
| Visual editor | Drag-and-drop node placement, edge drawing, config panels |
| Node types | Issue, Human Gate, Quality Gate, Loop, KB Sync, Integration, Start/End |
| Human gates | Approve/reject/hold with feedback; configurable review mode (Code, Plan, Findings) |
| Quality gates | Automated checks with pass/fail thresholds |
| Execution control | Start, pause, resume, cancel pipeline runs |
| Live status | Real-time node state visualization during execution |
| Input descriptions | Context passed to all issue nodes at run start (e.g. "Design Direction" for UI pipelines) |

**4 built-in pipeline templates:**

| Template | Description |
|---|---|
| **Extract Product Knowledge** | Parallel extraction of architecture, business logic, constraints, workflows, and product overview into KB |
| **Feature Implementation** | KB context → impact analysis → plan review gate → implementation → code review gate → test & docs → quality gate → KB sync |
| **UI & Layout Design** | Research & audit (3 parallel) → layout architecture → plan gate → implementation (3 parallel) → code review gate → polish & accessibility → quality gate → KB sync |
| **Product Health & Hardening** | 11 scan/apply pairs across lint, dead code, deps, security, DRY, error handling, type safety, tests, infrastructure, E2E, coverage → summary |

### Skills Library

64 built-in agent skills organized into 9 groups. Skills are injected into agent prompts to enforce engineering discipline. Includes skill groups for bundling related skills.

| Group | Skills | Description |
|---|---|---|
| **Quality Essentials** | 2 | Verification, code review |
| **Full Discipline** | 5 | Verification, debugging, TDD, planning, code review |
| **Research & Analysis** | 3 | Evidence-based work, scope discipline, structured reporting |
| **UI & Design** | 2 | Information design, UI design |
| **Documentation** | 2 | Structured reporting, information design |
| **Knowledge Extraction** | 5 | Extract architecture, business logic, constraints, workflows, product overview |
| **Product Hardening** | 23 | 11 scan/apply pairs + pipeline summary (lint, dead code, deps, security, DRY, error handling, type safety, tests, infrastructure, E2E, coverage) |
| **Feature Implementation** | 7 | KB context, impact analysis, constraint check, implementation plan, code implementation, test verification, docs & changelog |
| **UI & Layout Design Pipeline** | 9 | Design system audit, UX research, accessibility audit, layout architecture, component implementation, responsive/mobile, interaction/motion, visual polish, accessibility compliance |

### Knowledge Base

Integrated knowledge base for storing and searching structured notes. Supports three backends:

- **Local Storage** — filesystem-backed, works out of the box
- **Obsidian** — writes to a configured Obsidian vault path
- **Confluence** — delegates to Confluence REST API

Features: full-text search (ETS-indexed), tag-based search, metadata filters, note versioning, YAML frontmatter, batch operations, "Send to KB" from completed issues.

### Guide & Help System

- **Concept Map** (`/board/guide`) — interactive canvas-based visualization of Symphony's architecture. 10 concepts with directed relationship edges, colour-coded by category, click-to-expand detail panel with connections.
- **Explain Mode** — press `?` anywhere to toggle explain mode. Elements with help annotations highlight and show contextual popovers explaining what they do, why they matter, and what they connect to.

### Integrations

- **Jira** — create/update issues, sync states
- **GitLab CI** — trigger pipelines, check status
- **Confluence** — create/update pages (also used as KB backend)
- **Knowledge Base** — unified KB interface with local/obsidian/confluence backends

---

## Configuration

All config lives in the YAML front-matter of your `Workflow.md`:

```yaml
---
tracker:
  kind: local                 # "gitlab" or "local"
  project_slug: "my-project"  # required for gitlab
  active_states: [Todo, "In Progress"]
  terminal_states: [Done, Cancelled]
polling:
  interval_ms: 5000
workspace:
  root: ~/code/workspaces
agent:
  max_concurrent_agents: 10
  max_turns: 20
agent_process:
  command: agent-server
  approval_policy: never
---
```

<details>
<summary><strong>Full configuration reference</strong></summary>

| Key | Description | Default |
|---|---|---|
| `tracker.kind` | Issue tracker (`gitlab`, `local`) | *(required)* |
| `tracker.endpoint` | API base URL | auto per provider |
| `tracker.api_key` | API token (or `$ENV_VAR`) | `$GITLAB_API_TOKEN` |
| `tracker.project_slug` | Project identifier | *(required for gitlab)* |
| `tracker.active_states` | States that trigger agent work | `["Todo", "In Progress"]` |
| `tracker.terminal_states` | States that stop agent work | `["Done", "Cancelled", ...]` |
| `polling.interval_ms` | Poll interval (ms) | `30000` |
| `workspace.root` | Base directory for workspaces | `$TMPDIR/symphony_workspaces` |
| `agent.max_concurrent_agents` | Max parallel agents | `10` |
| `agent.max_turns` | Max conversation turns | `20` |
| `agent.max_retry_backoff_ms` | Max retry backoff (ms) | `300000` |
| `agent.max_concurrent_agents_by_state` | Per-state concurrency limits | `{}` |
| `hooks.after_create` | Shell script after workspace creation | — |
| `hooks.before_run` | Shell script before agent run | — |
| `hooks.after_run` | Shell script after agent run | — |
| `hooks.before_remove` | Shell script before cleanup | — |
| `hooks.shell` | Shell for hooks | — |
| `hooks.timeout_ms` | Hook timeout (ms) | `60000` |
| `agent_process.command` | Agent server command | `agent-server` |
| `agent_process.approval_policy` | Tool approval policy | — |
| `agent_process.turn_sandbox_policy` | Sandbox policy per turn | — |
| `agent_process.turn_timeout_ms` | Max time per turn (ms) | `3600000` |
| `agent_process.read_timeout_ms` | HTTP read timeout (ms) | `5000` |
| `agent.max_total_tokens` | Optional proactive token cap (0 = disabled) | `0` |
| `agent_process.stall_timeout_ms` | Stall detection (ms) | `300000` |

</details>

<details>
<summary><strong>GitLab configuration</strong></summary>

```yaml
---
tracker:
  kind: gitlab
  endpoint: https://gitlab.com/api/v4
  api_key: $GITLAB_API_TOKEN
  project_slug: "12345"               # numeric ID or URL-encoded path
  active_states: [Todo, "In Progress"]
  terminal_states: [Done, Cancelled]
---
```

GitLab issues use **labels** as workflow states. Add labels like "Todo", "In Progress", "Done" to your issues. Issues without a matching label fall back to native GitLab state (`opened` → Todo, `closed` → Done).

</details>

### CLI Options

```
symphony_elixir [options]

  -w, --workflow PATH   Path to Workflow.md (default: ./Workflow.md)
  -p, --port PORT       HTTP server port (default: from Workflow.md or 4545)
  -h, --help            Show help
```

---

## API Reference

### Orchestrator

| Method | Path | Description |
|---|---|---|
| `GET` | `/` | Redirects to `/board` |
| `GET` | `/api/v1/state` | JSON snapshot of orchestrator state |
| `POST` | `/api/v1/refresh` | Trigger immediate poll (202) |

### Board — Issues

| Method | Path | Description |
|---|---|---|
| `GET` | `/board` | Kanban board UI |
| `GET` | `/board/issues/:id` | Issue detail page |
| `GET` | `/board/api/snapshot` | Full board state |
| `GET` | `/board/api/states` | List board columns |
| `GET` | `/board/api/issues` | List issues |
| `POST` | `/board/api/issues` | Create issue |
| `GET` | `/board/api/issues/:id` | Get issue |
| `PATCH` | `/board/api/issues/:id` | Update issue |
| `PATCH` | `/board/api/issues/:id/move` | Move to state |
| `DELETE` | `/board/api/issues/:id` | Delete issue |
| `GET` | `/board/api/issues/:id/activity` | Issue activity log |
| `GET` | `/board/api/issues/:id/report` | Issue report |
| `POST` | `/board/api/issues/:id/skills` | Attach skills |
| `POST` | `/board/api/issues/:id/approve-plan` | Approve plan |
| `POST` | `/board/api/issues/:id/reject-plan` | Reject plan |
| `POST` | `/board/api/issues/:id/rerun` | Rerun issue |
| `POST` | `/board/api/issues/:id/follow-ups/:fu_id/accept` | Accept follow-up |
| `POST` | `/board/api/issues/:id/follow-ups/:fu_id/reject` | Reject follow-up |
| `PATCH` | `/board/api/issues/:id/follow-ups/:fu_id` | Update follow-up |

### Board — Projects

| Method | Path | Description |
|---|---|---|
| `GET` | `/board/api/projects` | List projects |
| `POST` | `/board/api/projects` | Create project |
| `GET` | `/board/api/projects/:id` | Get project |
| `PATCH` | `/board/api/projects/:id` | Update project |
| `DELETE` | `/board/api/projects/:id` | Delete project (cascades) |
| `POST` | `/board/api/projects/:id/clone` | Clone repo |
| `POST` | `/board/api/projects/scan` | Scan for projects |
| `POST` | `/board/api/projects/import` | Import project |
| `POST` | `/board/api/browse-folder` | Browse folder |

### Board — Products & Features

| Method | Path | Description |
|---|---|---|
| `GET` | `/board/api/products` | List products |
| `POST` | `/board/api/products` | Create product |
| `GET` | `/board/api/products/:id` | Get product |
| `PATCH` | `/board/api/products/:id` | Update product |
| `DELETE` | `/board/api/products/:id` | Delete product |
| `GET` | `/board/api/products/:id/activity` | Product activity |
| `POST` | `/board/api/products/:id/features` | Add feature |
| `PATCH` | `/board/api/products/:id/features/bulk-category` | Bulk update feature categories |
| `PATCH` | `/board/api/products/:id/features/:fid` | Update feature |
| `DELETE` | `/board/api/products/:id/features/:fid` | Delete feature |
| `PATCH` | `/board/api/products/:id/features/:fid/status` | Set status per project |
| `POST` | `/board/api/products/:id/generate-features` | AI: generate features |
| `POST` | `/board/api/products/:id/features/:fid/check` | AI: check implementation |
| `POST` | `/board/api/products/:id/analyze-existing-features` | AI: analyze existing features |
| `POST` | `/board/api/products/:id/analyze-gaps` | Analyze gaps |
| `POST` | `/board/api/products/:id/create-gap-issues` | Create gap issues |
| `POST` | `/board/api/products/:id/code-review` | AI: code review |
| `POST` | `/board/api/products/:id/generate-definition` | AI: generate product definition |
| `POST` | `/board/api/products/:id/tasks` | AI: generate tasks |

### Board — Skills

| Method | Path | Description |
|---|---|---|
| `GET` | `/board/skills` | Skills library UI |
| `GET` | `/board/api/skills` | List all skills |
| `POST` | `/board/api/skills` | Create skill |
| `GET` | `/board/api/skills/:id` | Get skill |
| `PATCH` | `/board/api/skills/:id` | Update skill |
| `DELETE` | `/board/api/skills/:id` | Delete skill |
| `POST` | `/board/api/skills/:id/duplicate` | Duplicate skill |
| `GET` | `/board/api/skill-groups` | List skill groups |
| `GET` | `/board/api/skill-groups/:id` | Get skill group |
| `POST` | `/board/api/skill-groups` | Create skill group |
| `PATCH` | `/board/api/skill-groups/:id` | Update skill group |
| `DELETE` | `/board/api/skill-groups/:id` | Delete skill group |

### Board — Pipelines

| Method | Path | Description |
|---|---|---|
| `GET` | `/board/pipeline` | Pipeline designer UI |
| `GET` | `/board/pipeline/:id` | Pipeline detail/execution UI |
| `GET` | `/board/api/pipelines` | List pipelines |
| `POST` | `/board/api/pipelines` | Create pipeline |
| `GET` | `/board/api/pipelines/:id` | Get pipeline |
| `PATCH` | `/board/api/pipelines/:id` | Update pipeline |
| `DELETE` | `/board/api/pipelines/:id` | Delete pipeline |
| `POST` | `/board/api/pipelines/:id/run` | Execute pipeline |
| `GET` | `/board/api/pipelines/:id/runs` | List runs for pipeline |
| `GET` | `/board/api/pipelines/:pid/runs/:rid` | Get run status |
| `POST` | `/board/api/pipelines/:pid/runs/:rid/pause` | Pause run |
| `POST` | `/board/api/pipelines/:pid/runs/:rid/resume` | Resume run |
| `POST` | `/board/api/pipelines/:pid/runs/:rid/cancel` | Cancel run |
| `POST` | `/board/api/pipelines/:pid/runs/:rid/gate/:nid` | Submit gate decision |
| `POST` | `/board/api/pipelines/:pid/runs/:rid/force-complete/:nid` | Force-complete node |
| `GET` | `/board/api/pipelines/:pid/runs/:rid/gate-context/:nid` | Get gate context |
| `GET` | `/board/api/pipeline-runs/waiting-gates` | All runs with waiting gates |
| `GET` | `/board/api/pipeline-runs/active` | All active runs |

### Board — Knowledge Base (Vault)

| Method | Path | Description |
|---|---|---|
| `POST` | `/board/api/vault/test` | Test vault connection |
| `POST` | `/board/api/vault/send` | Send issue report to vault |
| `POST` | `/board/api/vault/send-batch` | Batch send to vault |
| `POST` | `/board/api/vault/create` | Create note |
| `POST` | `/board/api/vault/append` | Append to note |
| `GET` | `/board/api/vault/search` | Search vault notes |
| `GET` | `/board/api/vault/search-by-tags` | Search by tags |
| `GET` | `/board/api/vault/search-by-metadata` | Search by metadata |
| `GET` | `/board/api/vault/note` | Read a specific note |
| `DELETE` | `/board/api/vault/note` | Delete a note |
| `GET` | `/board/api/vault/versions` | List note versions |
| `GET` | `/board/api/vault/version` | Get specific version |
| `POST` | `/board/api/vault/restore` | Restore note version |

### Board — Settings & Other

| Method | Path | Description |
|---|---|---|
| `GET` | `/board/settings` | Settings page |
| `GET` | `/board/guide` | Guide & concept map |
| `GET` | `/board/api/settings` | Get settings |
| `PATCH` | `/board/api/settings` | Update settings |
| `POST` | `/board/api/settings/reset` | Reset to defaults |
| `GET` | `/board/api/settings/auto-add` | Get auto-add config |
| `PATCH` | `/board/api/settings/auto-add` | Update auto-add config |
| `GET` | `/board/api/templates` | List issue templates |
| `GET` | `/board/api/templates/:id` | Get template |
| `GET` | `/board/api/backups` | List backups |
| `POST` | `/board/api/backups/restore` | Restore backup |
| `POST` | `/board/api/integrations/:type/test` | Test integration |

### Examples

```bash
# Get orchestrator state
curl http://localhost:4545/api/v1/state | jq .

# Trigger a refresh
curl -X POST http://localhost:4545/api/v1/refresh

# Create an issue
curl -X POST http://localhost:4545/board/api/issues \
  -H 'Content-Type: application/json' \
  -d '{"title": "Review auth module", "state": "Todo"}'

# Run a pipeline
curl -X POST http://localhost:4545/board/api/pipelines/PIPELINE_ID/run \
  -H 'Content-Type: application/json' \
  -d '{"input_description": "Redesign the dashboard with a modern look"}'
```

---

## Development

### Testing

```bash
mix test                           # Unit & integration tests
mix test --cover                   # With coverage report
mix test test/path/to_test.exs     # Single file
```

**Playwright E2E** (requires running server):

```bash
# Terminal 1
mix run test/e2e/test_server.exs

# Terminal 2
cd test/e2e && npm install && npx playwright test
```

### Linting & Analysis

```bash
mix format --check-formatted       # Formatting
mix credo --strict                 # Linting
mix dialyzer                       # Static types (first run builds PLT)
make all                           # Everything: format + credo + test + coverage + dialyzer
```

### Architecture

```
Workflow.md ──► Config ──► Orchestrator (GenServer)
                                │
              ┌─────────────────┼─────────────────┐
              ▼                 ▼                  ▼
       Tracker Client    WorkflowWatcher     HTTP Server
       (GitLab or        (file_system)        (Plug + Bandit)
        Local Board)                             │
              │                            ┌─────┴─────┐
              ▼                            ▼           ▼
        Reconciliation               /api/v1/*    /board/*
        ├─ Dispatch (spawn agent)                 ├─ Hub + Kanban
        ├─ Worker (turn loop)                     ├─ Skills
        ├─ Retry (backoff)                        ├─ Pipelines
        └─ State (in-memory)                      ├─ Guide
                                                  ├─ Settings
              Pipeline Runner                     └─ Knowledge Base
              ├─ Node execution
              ├─ Gate approval
              ├─ Feedback injection
              └─ Run lifecycle

              Integrations
              ├─ Jira
              ├─ GitLab CI
              ├─ Confluence
              └─ Knowledge Base (local/obsidian/confluence)
```

<details>
<summary><strong>Module index</strong></summary>

| Module | Role |
|---|---|
| `CLI` | Escript entry point |
| `Config` | YAML front-matter parsing |
| `Workflow` | Workflow.md reading, Liquid templates |
| `Orchestrator` | Central GenServer — polling, dispatch, lifecycle |
| `Orchestrator.State` | In-memory running/completed tracking |
| `Orchestrator.Reconciliation` | Diffing tracker vs running agents |
| `Orchestrator.Dispatch` | Spawning agent processes |
| `Orchestrator.Worker` | Agent session management, turn loop, workspace resolution |
| `Orchestrator.Retry` | Exponential backoff |
| `Orchestrator.Events` | Event broadcasting |
| `Orchestrator.Lifecycle` | Issue state transitions |
| `Orchestrator.Maintenance` | Auto-archive, cleanup |
| `Orchestrator.Snapshot` | Snapshot generation |
| `GitLab.Client` | GitLab REST/GraphQL HTTP client |
| `AppServer.Client` | Agent app-server communication |
| `AppServer.Protocol` | Wire protocol definitions |
| `AppServer.ClaudeAdapter` | Claude Code CLI adapter |
| `AppServer.Events` | Agent event types |
| `WorkflowWatcher` | File-system watcher for live reload |
| `Workspace` | Per-issue directory management |
| `Prompt` | Liquid template rendering |
| `Settings` | Runtime settings (JSON persistence) |
| `LLM` | LLM interaction helpers |
| `LocalBoard` | In-memory board + JSON persistence |
| `LocalBoard.Client` | Board ↔ Behaviour adapter |
| `LocalBoard.Issues` | Issue CRUD operations |
| `LocalBoard.Projects` | Project CRUD operations |
| `LocalBoard.Products` | Product & feature management |
| `LocalBoard.Pipelines` | Pipeline CRUD and execution |
| `LocalBoard.Skills` | Skills & skill groups management |
| `LocalBoard.Persistence` | JSON file persistence |
| `LocalBoard.Helpers` | Shared board utilities |
| `PipelineRunner` | Pipeline execution engine (gates, feedback, node lifecycle) |
| `PipelineSeed` | Extract Product Knowledge pipeline template |
| `FeaturePipelineSeed` | Feature Implementation pipeline template |
| `UIPipelineSeed` | UI & Layout Design pipeline template |
| `HardeningSeed` | Product Health & Hardening pipeline template |
| `SkillsSeed` | Built-in skills seeding (64 skills, 9 groups) |
| `ProjectScanner` | Git repository scanning |
| `DateTimeUtils` | Date/time formatting helpers |
| `ShellUtils` | Safe shell command execution |
| `ParseUtils` | Parsing utilities |
| `PathUtils` | Path utilities |
| `YamlParser` | YAML parsing |
| `Integrations.Registry` | Integration type dispatcher |
| `Integrations.Jira` | Jira REST API client |
| `Integrations.GitlabCI` | GitLab CI trigger/status |
| `Integrations.Confluence` | Confluence REST API client |
| `Integrations.KnowledgeBase` | Unified KB (local/obsidian/confluence) |
| `Integrations.KBIndex` | ETS-backed KB search index (GenServer) |
| `Server.Router` | Orchestrator API router |
| `Server.BoardRouter` | Board REST API + UI routes |
| `Server.BoardUI` | Kanban board web UI |
| `Server.ProductHubUI` | Product hub (default landing page) |
| `Server.PipelineUI` | Pipeline designer & execution UI |
| `Server.SkillsUI` | Skills library UI |
| `Server.IssueDetailUI` | Issue detail page |
| `Server.GuideUI` | Guide & concept map |
| `Server.SettingsUI` | Settings page |
| `Server.UIHelpers` | Shared CSS theme, explain mode & utilities |
| `Server.CombinedRouter` | Merged router (local mode) |

</details>

<details>
<summary><strong>Project structure</strong></summary>

```
elixir/
├── .github/
│   └── workflows/
│       └── ci.yml                     # GitHub Actions CI
├── lib/
│   ├── symphony_elixir.ex
│   └── symphony_elixir/
│       ├── application.ex
│       ├── cli.ex
│       ├── config.ex
│       ├── datetime_utils.ex
│       ├── issue.ex
│       ├── llm.ex
│       ├── parse_utils.ex
│       ├── path_utils.ex
│       ├── yaml_parser.ex
│       ├── orchestrator.ex
│       ├── orchestrator/
│       │   ├── dispatch.ex
│       │   ├── events.ex
│       │   ├── lifecycle.ex
│       │   ├── maintenance.ex
│       │   ├── reconciliation.ex
│       │   ├── retry.ex
│       │   ├── snapshot.ex
│       │   ├── state.ex
│       │   └── worker.ex
│       ├── tracker/
│       │   └── behaviour.ex
│       ├── gitlab/
│       │   └── client.ex
│       ├── app_server/
│       │   ├── claude_adapter.ex
│       │   ├── client.ex
│       │   ├── events.ex
│       │   └── protocol.ex
│       ├── integrations/
│       │   ├── registry.ex
│       │   ├── jira.ex
│       │   ├── gitlab_ci.ex
│       │   ├── confluence.ex
│       │   ├── knowledge_base.ex
│       │   └── kb_index.ex
│       ├── server/
│       │   ├── router.ex
│       │   ├── board_router.ex
│       │   ├── board_ui.ex
│       │   ├── product_hub_ui.ex
│       │   ├── pipeline_ui.ex
│       │   ├── skills_ui.ex
│       │   ├── issue_detail_ui.ex
│       │   ├── guide_ui.ex
│       │   ├── settings_ui.ex
│       │   ├── ui_helpers.ex
│       │   └── combined_router.ex
│       ├── local_board.ex
│       ├── local_board/
│       │   ├── client.ex
│       │   ├── helpers.ex
│       │   ├── issues.ex
│       │   ├── projects.ex
│       │   ├── products.ex
│       │   ├── pipelines.ex
│       │   ├── skills.ex
│       │   └── persistence.ex
│       ├── pipeline_runner.ex
│       ├── pipeline_seed.ex
│       ├── feature_pipeline_seed.ex
│       ├── ui_pipeline_seed.ex
│       ├── hardening_seed.ex
│       ├── skills_seed.ex
│       ├── project_scanner.ex
│       ├── settings.ex
│       ├── shell_utils.ex
│       ├── prompt.ex
│       ├── workflow.ex
│       ├── workflow_watcher.ex
│       └── workspace.ex
├── config/
├── test/
│   ├── symphony_elixir/              # ExUnit tests (33 test files)
│   └── e2e/                          # Playwright E2E tests
├── mix.exs
├── Makefile
└── Workflow.local.md
```

</details>

---

## License

Private — internal use only.

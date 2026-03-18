# Symphony Elixir

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
- **http://localhost:4545/board** — Kanban board & Hub

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

### Kanban Board

A full-featured issue board with no external dependencies.

| Capability | Details |
|---|---|
| Issue management | Create, edit, delete, drag-and-drop between columns |
| Priority & labels | 5 priority levels (colour-coded), free-form label tags |
| Projects | Group issues by project, optional repo cloning |
| Products | Group projects into products, feature completeness matrix |
| Inline issue editing | Edit issues directly on the detail page (title, state, priority, labels, project, description) |
| Agent integration | Issues dispatched to AI agents, follow-ups proposed and reviewed |
| Token exhaustion detection | Automatically stops dispatching when LLM reports token budget exhaustion, moves in-progress issues to Backlog |
| Keyboard shortcuts | `N` new issue, `J/K` navigate, `P` projects, `R` refresh, `?` help |
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

### Product Hub

Products group multiple projects into a single deliverable (e.g. "B2C API" = data-api + frontend + docs). The Hub is the default landing page and provides:

- **Spec Sheet** — feature completeness matrix across all projects (colour-coded cells)
- Per-feature and per-project completion scores
- AI-assisted feature generation and gap analysis
- One-click agent dispatch to verify implementation
- **Issues tab** — kanban board filtered to the selected product
- **Activity tab** — recent issue activity for the product
- **Knowledge Base tab** — search and browse KB notes scoped to the product

### Knowledge Base

Integrated knowledge base for storing and searching structured notes (business rules, architecture docs, research reports). Supports three backends:

- **Local Storage** — filesystem-backed, works out of the box
- **Obsidian** — writes to a configured Obsidian vault path
- **Confluence** — delegates to Confluence REST API

Features: full-text search (ETS-indexed), tag-based search, metadata filters, note versioning, YAML frontmatter, "Send to KB" from completed issues.

### Skills Library

21 built-in agent skills organized by category (Quality, Workflow, Debugging, Planning, System, Custom). Skills are injected into agent prompts to enforce engineering discipline. Includes skill groups for bundling related skills.

### Pipelines

Visual pipeline designer for multi-step agent workflows. Nodes represent stages (issue creation, agent runs, KB sync, gates). Pipelines can be created, edited, and executed from the UI.

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
| `GET` | `/board/api/issues` | List issues |
| `POST` | `/board/api/issues` | Create issue |
| `GET` | `/board/api/issues/:id` | Get issue |
| `PATCH` | `/board/api/issues/:id` | Update issue |
| `PATCH` | `/board/api/issues/:id/move` | Move to state |
| `DELETE` | `/board/api/issues/:id` | Delete issue |
| `GET` | `/board/api/states` | List board columns |

### Board — Projects

| Method | Path | Description |
|---|---|---|
| `GET` | `/board/api/projects` | List projects |
| `POST` | `/board/api/projects` | Create project |
| `GET` | `/board/api/projects/:id` | Get project |
| `PATCH` | `/board/api/projects/:id` | Update project |
| `DELETE` | `/board/api/projects/:id` | Delete project (cascades) |
| `POST` | `/board/api/projects/:id/clone` | Clone repo |

### Board — Products & Features

| Method | Path | Description |
|---|---|---|
| `GET` | `/board/api/products` | List products |
| `POST` | `/board/api/products` | Create product |
| `GET` | `/board/api/products/:id` | Get product |
| `PATCH` | `/board/api/products/:id` | Update product |
| `DELETE` | `/board/api/products/:id` | Delete product |
| `POST` | `/board/api/products/:id/features` | Add feature |
| `PATCH` | `/board/api/products/:id/features/:fid` | Update feature |
| `DELETE` | `/board/api/products/:id/features/:fid` | Delete feature |
| `PATCH` | `/board/api/products/:id/features/:fid/status` | Set status per project |
| `POST` | `/board/api/products/:id/generate-features` | Agent: generate features |
| `POST` | `/board/api/products/:id/features/:fid/check` | Agent: check implementation |
| `POST` | `/board/api/products/:id/analyze-gaps` | Analyze gaps |
| `POST` | `/board/api/products/:id/create-gap-issues` | Create gap issues |

### Board — Skills

| Method | Path | Description |
|---|---|---|
| `GET` | `/board/skills` | Skills library UI |
| `GET` | `/board/api/skills` | List all skills |
| `POST` | `/board/api/skills` | Create skill |
| `PATCH` | `/board/api/skills/:id` | Update skill |
| `DELETE` | `/board/api/skills/:id` | Delete skill |
| `GET` | `/board/api/skill-groups` | List skill groups |
| `POST` | `/board/api/skill-groups` | Create skill group |
| `PATCH` | `/board/api/skill-groups/:id` | Update skill group |
| `DELETE` | `/board/api/skill-groups/:id` | Delete skill group |

### Board — Pipelines

| Method | Path | Description |
|---|---|---|
| `GET` | `/board/pipeline` | Pipeline designer UI |
| `GET` | `/board/api/pipelines` | List pipelines |
| `POST` | `/board/api/pipelines` | Create pipeline |
| `GET` | `/board/api/pipelines/:id` | Get pipeline |
| `PATCH` | `/board/api/pipelines/:id` | Update pipeline |
| `DELETE` | `/board/api/pipelines/:id` | Delete pipeline |
| `POST` | `/board/api/pipelines/:id/run` | Execute pipeline |

### Board — Knowledge Base (Vault)

| Method | Path | Description |
|---|---|---|
| `POST` | `/board/api/vault/test` | Test vault connection |
| `POST` | `/board/api/vault/send` | Send issue reports to vault |
| `GET` | `/board/api/vault/search` | Search vault notes |
| `GET` | `/board/api/vault/search-by-tags` | Search by tags |
| `GET` | `/board/api/vault/search-by-metadata` | Search by metadata |
| `GET` | `/board/api/vault/note` | Read a specific note |

### Board — Settings & Other

| Method | Path | Description |
|---|---|---|
| `GET` | `/board/settings` | Settings page |
| `GET` | `/board/api/settings` | Get settings |
| `PATCH` | `/board/api/settings` | Update settings |
| `POST` | `/board/api/settings/reset` | Reset to defaults |
| `GET` | `/board/api/templates` | List issue templates |
| `GET` | `/board/api/templates/:id` | Get template |

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
```

---

## Development

### Testing

```bash
mix test                           # Unit & integration (540+ tests)
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
        └─ State (in-memory)                      ├─ Settings
                                                  └─ Knowledge Base
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
| `LocalBoard` | In-memory board + JSON persistence |
| `LocalBoard.Client` | Board ↔ Behaviour adapter |
| `LocalBoard.Issues` | Issue CRUD operations |
| `LocalBoard.Projects` | Project CRUD operations |
| `LocalBoard.Products` | Product & feature management |
| `LocalBoard.Pipelines` | Pipeline CRUD and execution |
| `LocalBoard.Skills` | Skills & skill groups management |
| `LocalBoard.Persistence` | JSON file persistence |
| `LocalBoard.Helpers` | Shared board utilities |
| `PipelineRunner` | Pipeline execution engine |
| `SkillsSeed` | Built-in skills seeding on startup |
| `ProjectScanner` | Git repository scanning |
| `DateTimeUtils` | Date/time formatting helpers |
| `ShellUtils` | Safe shell command execution |
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
| `Server.SettingsUI` | Settings page |
| `Server.UIHelpers` | Shared CSS theme & escaping |
| `Server.CombinedRouter` | Merged router (local mode) |

</details>

<details>
<summary><strong>Project structure</strong></summary>

```
elixir/
├── lib/
│   ├── symphony_elixir.ex
│   └── symphony_elixir/
│       ├── application.ex
│       ├── cli.ex
│       ├── config.ex
│       ├── datetime_utils.ex
│       ├── issue.ex
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
│       ├── project_scanner.ex
│       ├── settings.ex
│       ├── shell_utils.ex
│       ├── skills_seed.ex
│       ├── prompt.ex
│       ├── workflow.ex
│       ├── workflow_watcher.ex
│       └── workspace.ex
├── config/
├── test/
│   ├── symphony_elixir/              # ExUnit tests
│   └── e2e/                          # Playwright E2E tests
├── mix.exs
├── Makefile
└── Workflow.local.md
```

</details>

---

## License

Private — internal use only.

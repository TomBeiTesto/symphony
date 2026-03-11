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
- **http://localhost:4545/board** — Kanban board
- **http://localhost:4545** — Orchestrator dashboard

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
| Task Lineage | Visual tree of issue lineage (parent → follow-up chains) |
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

### Product Review

Products group multiple projects into a single deliverable (e.g. "B2C API" = data-api + frontend + docs). The review matrix shows:

- Feature completeness across all projects (colour-coded cells)
- Per-feature and per-project completion scores
- AI-assisted feature generation and gap analysis
- One-click agent dispatch to verify implementation

### Orchestrator Dashboard

Real-time view of running agents, retry queues, and aggregate token usage. Auto-refreshes via meta tag.

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
| `GET` | `/` | HTML dashboard |
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
| `GET` | `/board/review` | Product review matrix UI |
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

### Board — Other

| Method | Path | Description |
|---|---|---|
| `GET` | `/board/task-lineage` | Task lineage visualization |
| `GET` | `/board/api/templates` | List issue templates |
| `GET` | `/board/api/templates/:id` | Get template |
| `GET` | `/board/settings` | Settings page |
| `GET` | `/board/api/settings` | Get settings |
| `PATCH` | `/board/api/settings` | Update settings |
| `POST` | `/board/api/settings/reset` | Reset to defaults |

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
mix test                           # Unit & integration (333+ tests)
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
              │                              ┌──────┴──────┐
              ▼                              ▼             ▼
        Reconciliation                  Dashboard    Board + Review
        ├─ Dispatch (spawn agent)       /            /board
        ├─ Retry (backoff)             /api/v1/*    /board/api/*
        └─ State (in-memory)
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
| `Orchestrator.Retry` | Exponential backoff |
| `GitLab.Client` | GitLab REST/GraphQL HTTP client |
| `AppServer.Client` | Agent app-server communication |
| `AppServer.Protocol` | Wire protocol definitions |
| `AppServer.ClaudeAdapter` | Claude Code CLI adapter |
| `WorkflowWatcher` | File-system watcher for live reload |
| `Workspace` | Per-issue directory management |
| `Prompt` | Liquid template rendering |
| `Settings` | Runtime settings (JSON persistence) |
| `LocalBoard` | In-memory board + JSON persistence |
| `LocalBoard.Client` | Board ↔ Behaviour adapter |
| `Server.Router` | Plug HTTP router |
| `Server.Dashboard` | HTML dashboard |
| `Server.BoardRouter` | Board REST API |
| `Server.BoardUI` | Board web UI |
| `Server.TechTreeUI` | Task lineage visualization |
| `Server.ReviewUI` | Product review matrix |
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
│       ├── issue.ex
│       ├── orchestrator.ex
│       ├── orchestrator/
│       │   ├── dispatch.ex
│       │   ├── reconciliation.ex
│       │   ├── retry.ex
│       │   └── state.ex
│       ├── tracker/
│       │   └── behaviour.ex
│       ├── gitlab/
│       │   └── client.ex
│       ├── app_server/
│       │   ├── client.ex
│       │   └── protocol.ex
│       ├── server/
│       │   ├── router.ex
│       │   ├── dashboard.ex
│       │   ├── board_router.ex
│       │   ├── board_ui.ex
│       │   ├── tech_tree_ui.ex
│       │   ├── review_ui.ex
│       │   ├── issue_detail_ui.ex
│       │   ├── settings_ui.ex
│       │   ├── ui_helpers.ex
│       │   └── combined_router.ex
│       ├── local_board.ex
│       ├── local_board/
│       │   └── client.ex
│       ├── settings.ex
│       ├── prompt.ex
│       ├── workflow.ex
│       ├── workflow_watcher.ex
│       └── workspace.ex
├── config/
├── test/
│   ├── symphony_elixir/              # ExUnit tests
│   └── e2e/                          # Playwright tests
├── mix.exs
├── Makefile
└── Workflow.local.md
```

</details>

---

## License

Private — internal use only.

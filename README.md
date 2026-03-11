# Symphony

Orchestrate AI agents from your issue board. Symphony monitors issues, assigns them to AI agent processes, and lets you track everything through a built-in web UI.

Supports [GitLab](https://gitlab.com) Issues or a **built-in local Kanban board**. Cross-platform (macOS, Linux, Windows).

## Quick Start

```bash
cd elixir
mix setup && mix escript.build
escript symphony_elixir --workflow ../Workflow.local.md --port 4545
```

Open **http://localhost:4545/board** for the Kanban board or **http://localhost:4545** for the orchestrator dashboard.

## Features

- **Kanban Board** — Create, edit, drag-and-drop issues across columns (Backlog, Todo, In Progress, Review, Done, Archived, Cancelled)
- **Projects** — Group issues by project, optional Git repo cloning, directory scanning
- **Products** — Group projects into products with a feature completeness matrix
- **Task Lineage** — Visual tree of parent/follow-up issue chains
- **Product Review** — Per-feature, per-project completion scores with AI-assisted gap analysis
- **Inline Issue Editing** — Edit issues directly on the detail page (title, state, priority, labels, project, description)
- **Agent Orchestration** — Issues dispatched to AI agents with retry logic and lifecycle management
- **Token Exhaustion Detection** — Automatically stops dispatching when LLM reports token budget exhaustion, moves in-progress issues to Backlog
- **Settings UI** — Configure Git provider, AI provider, and issue tracker at runtime
- **Keyboard Shortcuts** — `N` new issue, `J/K` navigate, `P` projects, `R` refresh, `?` help

## Repository Structure

```
symphony/
├── .agents/                # Agent spec files
├── .gitlab-ci.yml          # CI/CD pipeline
├── README.md               # This file
└── elixir/                 # Elixir/OTP application (main codebase)
    ├── lib/                # Source code
    ├── test/               # ExUnit + Playwright E2E tests
    ├── config/             # Elixir config
    ├── mix.exs             # Project definition & dependencies
    ├── Workflow.md          # GitLab workflow config (template)
    ├── Workflow.local.md    # Local board workflow config
    └── README.md           # Detailed documentation
```

## CI/CD

The GitLab CI pipeline runs on every MR and default branch push:

| Job | Stage | Description |
|---|---|---|
| `build-elixir` | build | Compile dependencies and application |
| `test-elixir` | test | Run ExUnit tests with coverage |
| `lint-elixir` | test | Format check + Credo (allow_failure) |
| `e2e-tests` | test | Playwright E2E tests (77 tests across board, settings, task lineage, product review, projects) |

## Testing

```bash
# Elixir unit tests
cd elixir && mix test

# Playwright E2E tests (requires running server)
cd elixir && mix run test/e2e/test_server.exs &
cd test/e2e && npm install && npx playwright test

# Screenshots only (opt-in)
cd test/e2e && npm run test:screenshots
```

## Documentation

See [elixir/README.md](elixir/README.md) for detailed documentation including:
- Full configuration reference
- API reference (all endpoints)
- Architecture overview
- Module index

## License

Private — internal use only.

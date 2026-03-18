# Symphony Elixir

This directory contains the Elixir agent orchestration service that polls your issue tracker, creates per-issue workspaces, and runs coding agents in app-server mode. It also includes a built-in local Kanban board with product hub.

## Environment

- Elixir: `1.19.x` (OTP 28) via `mise`.
- Install deps: `mix setup`.
- Main quality gate: `make all` (format check, lint, coverage, dialyzer).


## Codebase-Specific Conventions

- Runtime config is loaded from `WORKFLOW.md` front matter via `SymphonyElixir.Workflow` and `SymphonyElixir.Config`.
- Keep the implementation aligned with [`../SPEC.md`](../SPEC.md) where practical.
  - The implementation may be a superset of the spec.
  - The implementation must not conflict with the spec.
  - If implementation changes meaningfully alter the intended behavior, update the spec in the same
    change where practical so the spec stays current.
- Prefer adding config access through `SymphonyElixir.Config` instead of ad-hoc env reads.
- Workspace safety is critical:
  - Never run agent turn cwd in source repo.
  - Workspaces must stay under configured workspace root.
- Orchestrator behavior is stateful and concurrency-sensitive; preserve retry, reconciliation, and cleanup semantics.
- Follow `docs/logging.md` for logging conventions and required issue/session context fields.

### UI Conventions

- Server-rendered HTML pages use shared CSS theme variables from `SymphonyElixir.Server.UIHelpers.theme_css/0`.
- HTML escaping in Elixir templates uses `SymphonyElixir.Server.UIHelpers.esc/1` (import it, don't define local copies).
- Client-side JS in `~S` sigils must use `const`/`let` (not `var`). HTML escaping on the client uses the `esc()` function defined inline (DOM-based `textContent`/`innerHTML` pattern).
- Board states: `["Backlog", "Todo", "In Progress", "Review", "Done", "Archived", "Cancelled"]`.
- Issues with pending follow-ups land in "Review"; they auto-move to "Done" when all follow-ups are accepted/rejected.
- Done issues auto-archive to "Archived" after 1 day (via orchestrator tick).
- Deleting a project cascade-deletes all its issues.
- Follow-up issues link to the parent that proposed them via `parent_issue_id`.

### UI Pages

- `/board` — Product Hub (default landing page) with tabs: Spec Sheet, Issues, Activity, Knowledge Base
- `/board/issues/:id` — Issue detail with edit, rerun, Send to KB, delete actions
- `/board/pipeline` — Pipeline designer (canvas-based node editor)
- `/board/skills` — Skills library with category filters and search
- `/board/settings` — Settings (Git, AI Provider, Skills, KB, Jira, GitLab CI, Confluence, Issue Tracker)

### Key Integrations

- `Integrations.Registry` dispatches to type-specific modules: Jira, GitlabCI, Confluence, KnowledgeBase
- KB has three backends: local (filesystem), obsidian (vault path), confluence (HTTP)
- `KBIndex` (GenServer + ETS) provides fast in-memory search; started in supervision tree under `Config.local_board?`
- KB mutations (write, append, delete, restore) invalidate the index via `KBIndex.invalidate/2`

## Tests and Validation

Run targeted tests while iterating, then run full gates before handoff.

```bash
make all
```

### Test Organization

- `test/symphony_elixir/` — ExUnit tests for all modules
- `test/e2e/` — Playwright browser tests covering board, settings, skills, pipelines, and APIs

## Required Rules

- Public functions (`def`) in `lib/` must have an adjacent `@spec`.
- `defp` specs are optional.
- `@impl` callback implementations are exempt from local `@spec` requirement.
- Keep changes narrowly scoped; avoid unrelated refactors.
- Follow existing module/style patterns in `lib/symphony_elixir/*`.

Validation command:

```bash
mix specs.check
```

## PR Requirements

- PR body must follow `../.github/pull_request_template.md` exactly.
- Validate PR body locally when needed:

```bash
mix pr_body.check --file /path/to/pr_body.md
```

## Docs Update Policy

If behavior/config changes, update docs in the same PR:

- `../README.md` for project concept and goals.
- `README.md` for Elixir implementation and run instructions.
- `WORKFLOW.md` for workflow/config contract changes.

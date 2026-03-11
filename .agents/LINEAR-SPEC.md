# Local Board Specification (Linear-Compatible Local Issue Tracker)

Status: Draft v1 (Elixir reference implementation)

Purpose: Define a self-contained, local issue tracker and Kanban board that replaces the external
Linear API dependency, allowing Symphony to run fully offline with no third-party accounts.

Supported platforms: macOS, Linux, and Windows.

## 1. Problem Statement

Symphony's core specification requires an issue tracker client to fetch candidate issues, refresh
issue states, and provide normalized issue data to the orchestrator. The default tracker integration
targets Linear, which requires an account, API key, and network access.

The Local Board solves four operational problems:

- It eliminates the external service dependency so Symphony can run on a single machine with zero
  configuration beyond a `Workflow.md` file.
- It provides a web-based Kanban UI that lets operators create, edit, move, and delete issues
  directly in a browser — matching the core workflow that Linear provides.
- It implements the same `Linear.Behaviour` adapter contract so the orchestrator requires no
  special-case logic; the local board is a drop-in replacement at the integration layer.
- It persists board state to a JSON file so data survives process restarts without requiring a
  database.

Important boundary:

- The Local Board is a scheduling-grade issue store, not a full Linear clone.
- It stores the fields the orchestrator needs for dispatch, reconciliation, and prompt rendering.
- It does not implement teams, cycles, users, attachments, comments, relations, or GraphQL.
- The Kanban UI is an operator tool; it is not required for orchestrator correctness.

## 2. Goals and Non-Goals

### 2.1 Goals

- Provide a zero-dependency local issue tracker that satisfies the `Linear.Behaviour` contract.
- Expose a drag-and-drop Kanban web UI served on the same HTTP port as the orchestrator dashboard.
- Support full CRUD operations on issues via a JSON REST API.
- Persist all mutations to disk immediately so board state survives restarts.
- Support configurable board columns (states) and project prefix from `Workflow.md`.
- Normalize local issues to the same `Issue` struct used by the orchestrator.
- Integrate transparently so the orchestrator, reconciliation, dispatch, and prompt rendering
  require no code changes beyond tracker client module selection.

### 2.2 Non-Goals

- Full Linear feature parity (teams, users, cycles, relations, comments, webhooks).
- Multi-user collaboration or real-time sync between multiple browser clients.
- GraphQL query support (the `execute_graphql` callback returns an explicit error).
- Database-backed persistence (SQLite, PostgreSQL, etc.).
- Authentication or authorization on the board API.
- Offline-first client-side storage or service workers.

## 3. System Overview

### 3.1 Main Components

1. `LocalBoard` (GenServer)
   - Owns the in-memory issue and project store.
   - Serializes all mutations through a single process.
   - Persists to JSON on every write.
   - Loads from JSON on startup with state migration (`merge_states/2`).

2. `LocalBoard.Client` (Behaviour Adapter)
   - Implements `SymphonyElixir.Linear.Behaviour`.
   - Delegates to the `LocalBoard` GenServer for all reads.
   - Converts internal issue records to `Issue` structs.

3. `BoardRouter` (REST API)
   - Plug router exposing CRUD endpoints for issues, projects, templates, and settings.
   - Serves board UI, tech tree, issue detail, and settings pages.
   - Handles follow-up accept/reject with auto-move to Done.
   - Handles JSON request/response encoding.

4. `BoardUI` (Web Interface)
   - Server-rendered single-page HTML/CSS/JavaScript application.
   - Drag-and-drop Kanban columns with collapsible headers.
   - Create, edit, delete, and move modals.
   - Quick-add per column.
   - Auto-refresh polling.
   - Archived column collapsed by default.

5. `TechTreeUI` (Tech Tree Visualization)
   - Civilization-style horizontal tree showing issue lineage.
   - Root issues (no parent) on the left, follow-ups branching right.
   - SVG bezier curve connectors with arrowheads.
   - Color-coded nodes by state, project filter dropdown.
   - Pan/drag viewport.

6. `IssueDetailUI` (Issue Detail Page)
   - Full issue detail view with follow-up management.
   - Accept/reject follow-up proposals.

7. `SettingsUI` (Settings Page)
   - Configure git provider, AI provider, agent command, and issue tracker settings.

8. `UIHelpers` (Shared Utilities)
   - Shared CSS theme variables (`:root` custom properties).
   - Shared HTML escaping (`esc/1` for Elixir, `esc()` for client-side JS).

9. `CombinedRouter` (Route Multiplexer)
   - Forwards `/board/*` to `BoardRouter`.
   - Forwards `/*` to the orchestrator `Router`.
   - Used when `tracker.kind == "local"` so both surfaces share one port.

### 3.2 Abstraction Levels

The Local Board maps to Symphony's abstraction layers as follows:

1. `Configuration Layer`
   - `tracker.kind: "local"` enables the local board.
   - `tracker.project_slug` becomes the issue identifier prefix (e.g. `"SYM"` → `SYM-1`).
   - `tracker.active_states` and `tracker.terminal_states` define board columns.

2. `Integration Layer` (replaces Linear adapter)
   - `LocalBoard.Client` implements the same four callbacks.
   - The orchestrator calls `linear_client_module(config)` which returns `LocalBoard.Client`
     when `tracker_kind == "local"`.

3. `Data Layer` (new)
   - `LocalBoard` GenServer with in-memory map + JSON file persistence.

4. `Presentation Layer` (new, optional)
   - `BoardRouter` + `BoardUI` + `TechTreeUI` + `IssueDetailUI` + `SettingsUI` + `UIHelpers` +
     `CombinedRouter`.
   - Observability/operator surface only; not required for orchestrator correctness.

### 3.3 External Dependencies

- None beyond what Symphony already requires.
- No network access needed.
- No API keys needed.
- File system access for JSON persistence (single file in the working directory).

## 4. Core Domain Model

### 4.1 Entities

#### 4.1.1 Issue Record (Internal)

The `LocalBoard` GenServer stores issues as plain maps with the following fields:

Fields:

- `id` (string)
  - 16-character URL-safe Base64 string generated from `:crypto.strong_rand_bytes(12)`.
  - Used as the primary key in the issues map.
- `identifier` (string)
  - Human-readable key in the format `<project_prefix>-<sequence_number>`.
  - Example: `SYM-1`, `SYM-42`.
  - Sequence number is monotonically increasing and never reused.
- `title` (string)
  - Required. Defaults to `"Untitled"` if omitted on create.
- `description` (string or null)
- `priority` (integer)
  - `0` = No priority, `1` = Urgent, `2` = High, `3` = Medium, `4` = Low.
  - Parsed from string input if necessary. Non-parseable values default to `0`.
- `state` (string)
  - Current board column name.
  - Defaults to the first configured state on create.
- `branch_name` (string or null)
- `url` (string or null)
  - Always `nil` for local issues (no external URL).
- `labels` (list of strings)
  - Parsed from comma-separated string input or list input.
- `project_id` (string or null)
  - Links the issue to a project. Set on create if provided.
- `parent_issue_id` (string or null)
  - Links the issue to a parent issue for lineage tracking (follow-up chains).
  - Set when a follow-up proposal is accepted and creates a new issue.
- `created_at` (ISO 8601 string)
  - Set on creation, never updated.
- `updated_at` (ISO 8601 string)
  - Updated on every mutation.

#### 4.1.2 Issue Struct (Normalized)

The `to_issue_struct/1` function converts an internal record to a `SymphonyElixir.Issue` struct
for use by the orchestrator. The conversion:

- Copies all scalar fields directly.
- Sets `blocked_by` to `[]` (local board does not track issue relations).
- Copies `project_id` and `parent_issue_id`.
- Parses `created_at` and `updated_at` from ISO 8601 strings to `DateTime` values.
- Sets `labels` to `[]` if `nil`.

#### 4.1.3 Board Snapshot

A read-only view of the entire board state, returned by `get_board_snapshot/0`:

Fields:

- `states` (list of strings)
  - The configured column names in display order.
- `columns` (list of column objects)
  - Each column: `%{state: string, issues: [issue_record]}`.
  - Issues within each column are sorted by priority (descending) then `created_at` (ascending).
- `total_issues` (integer)
  - Total number of issues across all columns.
- `project_prefix` (string)
  - The configured identifier prefix.
- `projects` (list of project records)
  - All projects in the board.

#### 4.1.4 Project Record

Fields:

- `id` (string) — Generated like issue IDs.
- `name` (string) — Display name.
- `slug` (string) — URL-friendly slug, auto-derived from name if not provided.
- `path` (string or null) — Local filesystem path for the project.
- `repo_url` (string or null) — Remote repository URL for cloning.
- `description` (string or null)
- `created_at` (ISO 8601 string)
- `updated_at` (ISO 8601 string)

#### 4.1.5 Board State (GenServer)

The `LocalBoard` GenServer struct:

Fields:

- `issues` (map: `id -> issue_record`)
  - All issues keyed by their generated ID.
- `projects` (map: `id -> project_record`)
  - All projects keyed by their generated ID.
- `states` (list of strings)
  - Ordered list of board column names.
  - Default: `["Backlog", "Todo", "In Progress", "Review", "Done", "Archived", "Cancelled"]`.
- `next_number` (integer)
  - Next sequence number for identifier generation.
  - Initialized to 1 or `max(existing_numbers) + 1` on load.
- `project_prefix` (string)
  - Prefix for issue identifiers. Default: `"SYM"`.
- `store_path` (string)
  - Filesystem path for the JSON persistence file. Default: `"local_board.json"`.

### 4.2 Identifier Rules

- `Issue ID`
  - 16-character URL-safe Base64 from 12 random bytes.
  - Used for API endpoints, internal map keys, and cross-reference.
- `Issue Identifier`
  - `<project_prefix>-<next_number>`.
  - Sequence numbers are never recycled, even after deletion.
  - Used for human-readable display and workspace naming by the orchestrator.
- `State Names`
  - Case-sensitive for storage and display.
  - Case-insensitive for filtering (via `String.downcase/1` comparison).

## 5. Configuration Specification

### 5.1 Enabling the Local Board

Set `tracker.kind: "local"` in `Workflow.md` front matter:

```yaml
---
tracker:
  kind: local
  project_slug: "SYM"
  active_states:
    - Todo
    - In Progress
  terminal_states:
    - Done
    - Cancelled
---
```

### 5.2 Configuration Fields

| Field | Type | Default | Description |
|---|---|---|---|
| `tracker.kind` | string | — | Must be `"local"` to enable the local board |
| `tracker.project_slug` | string | `"SYM"` | Prefix for issue identifiers |
| `tracker.active_states` | list | `["Todo", "In Progress"]` | States the orchestrator polls for dispatch |
| `tracker.terminal_states` | list | `["Done", "Cancelled"]` | States that stop active runs |

### 5.3 Derived Board Columns

The full set of board columns (states) is the union of `active_states` and `terminal_states`,
preserving declaration order. These are passed to the `LocalBoard` GenServer as the `states` option
and determine the Kanban columns displayed in the UI.

The default board states are `["Backlog", "Todo", "In Progress", "Review", "Done", "Archived", "Cancelled"]`.

### 5.3.1 State Migration

When loading persisted states from the JSON file, the board merges new default states into the
persisted list using `merge_states/2`. Missing states are spliced at the correct position relative
to existing states. This ensures that adding new default states (e.g., "Review", "Archived") does
not disrupt existing boards.

### 5.4 Dispatch Validation Changes

When `tracker.kind == "local"`:

- `tracker.api_key` is not required and not validated.
- `tracker.project_slug` is not required for validation (defaults to `"SYM"` if absent).
- `agent_process.command` validation is unchanged.
- All other dispatch preflight checks from the core spec apply.

### 5.5 Dynamic Reload

Workflow reload for local board configuration follows the same contract as the core spec:

- `active_states` and `terminal_states` changes affect future polling and reconciliation.
- Board column changes require a restart of the `LocalBoard` GenServer to take effect in the UI.
- Prompt template changes apply to future dispatch immediately.

## 6. Persistence Specification

### 6.1 Storage Format

The board persists to a single JSON file at the configured `store_path` (default:
`local_board.json` in the working directory).

JSON structure:

```json
{
  "issues": [
    {
      "id": "abc123...",
      "identifier": "SYM-1",
      "title": "Example issue",
      "description": "Details here",
      "priority": 2,
      "state": "Todo",
      "branch_name": null,
      "url": null,
      "labels": ["bug", "frontend"],
      "project_id": null,
      "parent_issue_id": null,
      "created_at": "2026-03-05T10:00:00Z",
      "updated_at": "2026-03-05T10:00:00Z"
    }
  ],
  "projects": [
    {
      "id": "def456...",
      "name": "My Project",
      "slug": "my-project",
      "path": null,
      "repo_url": null,
      "description": null,
      "created_at": "2026-03-05T10:00:00Z",
      "updated_at": "2026-03-05T10:00:00Z"
    }
  ],
  "states": ["Backlog", "Todo", "In Progress", "Review", "Done", "Archived", "Cancelled"],
  "next_number": 2,
  "project_prefix": "SYM"
}
```

### 6.2 Write Semantics

- Persist on every mutation (create, update, move, delete).
- Write is synchronous within the GenServer `handle_call`.
- Uses `File.write!/2` with `Jason.encode!(data, pretty: true)`.
- Write failures crash the GenServer call (fail-loud for data integrity).
- No write-ahead log, journaling, or atomic rename — acceptable for single-process use.

### 6.3 Load Semantics

On GenServer init:

1. Attempt `File.read(store_path)`.
2. If file does not exist (`:enoent`), start with an empty board.
3. If file exists, decode JSON.
4. If JSON is corrupt, log a warning and start with an empty board.
5. Restore `issues`, `projects`, `states`, `next_number`, and `project_prefix` from the JSON data.
6. Merge persisted states with current defaults using `merge_states/2` to splice any new default
   states into the correct position. Persist immediately if states changed.
7. Compute `max_number` from existing identifiers; set `next_number` to
   `max(stored_next_number, max_number + 1)` to avoid identifier collisions.

### 6.4 Concurrency Safety

- All reads and writes are serialized through the GenServer process.
- No external locking is required or implemented.
- Multiple Symphony instances sharing the same `store_path` is not supported and will cause data
  loss.

## 7. Behaviour Adapter Contract

### 7.1 Interface

`LocalBoard.Client` implements `SymphonyElixir.Linear.Behaviour` with four callbacks:

#### 7.1.1 `fetch_candidate_issues(config)`

- Reads `config.active_states`.
- Calls `LocalBoard.list_issues_by_states(active_states)`.
- Converts each record to an `Issue` struct via `LocalBoard.to_issue_struct/1`.
- Returns `{:ok, [Issue.t()]}`.
- On exception, returns `{:error, {:local_board_error, message}}`.

#### 7.1.2 `fetch_issues_by_states(config, state_names)`

- If `state_names` is empty, returns `{:ok, []}` without calling the GenServer.
- Otherwise calls `LocalBoard.list_issues_by_states(state_names)`.
- Converts and returns as above.

#### 7.1.3 `fetch_issue_states_by_ids(config, issue_ids)`

- If `issue_ids` is empty, returns `{:ok, []}` without calling the GenServer.
- Otherwise calls `LocalBoard.get_issues_by_ids(issue_ids)`.
- Converts and returns as above.

#### 7.1.4 `execute_graphql(config, query, variables)`

- Always returns `{:error, :graphql_not_supported_on_local_board}`.
- GraphQL is not meaningful for local storage.

### 7.2 Orchestrator Integration

The orchestrator selects the client module at runtime:

```text
function linear_client_module(config):
  if config.tracker_kind == "local":
    return LocalBoard.Client
  else:
    return application_env(:linear_client_module) or Linear.Client
```

This selection applies to:

- `Orchestrator.do_tick/1` — candidate fetching and reconciliation.
- `Orchestrator.handle_retry/3` — retry candidate re-fetch.
- `Orchestrator.reconcile_running_issues/1` — state refresh for active runs.
- `AppServer.Client.run_linear_graphql/3` — tool call handling (returns error for local).

### 7.3 Supervision Tree Changes

When `tracker.kind == "local"`, the CLI starts additional children:

1. `{LocalBoard, [store_path: ..., states: [...], project_prefix: "..."]}`
   - Started before the HTTP server and orchestrator.
2. HTTP server uses `CombinedRouter` instead of `Router`.

## 8. REST API Specification

### 8.1 Route Prefix

When served behind `CombinedRouter`, all board routes are prefixed with `/board`. The `forward`
macro strips the prefix before dispatching to `BoardRouter`, so internal routes use `/` and
`/api/*`.

Browser clients use the full prefixed paths (e.g. `/board/api/issues`).

### 8.2 Endpoints

#### 8.2.1 `GET /board`

Returns the Kanban board HTML page.

Response:

- `200 OK`
- Content-Type: `text/html`
- Body: full HTML document from `BoardUI.render/0`

#### 8.2.2 `GET /board/api/snapshot`

Returns the full board state with columns and issues.

Response:

- `200 OK`
- Content-Type: `application/json`
- Body:

```json
{
  "states": ["Backlog", "Todo", "In Progress", "Review", "Done", "Archived", "Cancelled"],
  "columns": [
    {
      "state": "Todo",
      "issues": [{"id": "...", "identifier": "SYM-1", ...}]
    }
  ],
  "total_issues": 5,
  "project_prefix": "SYM",
  "projects": [{"id": "...", "name": "My Project", ...}]
}
```

#### 8.2.3 `GET /board/api/issues`

Returns all issues as a flat list.

Response:

- `200 OK`
- Body: `{"issues": [...]}`

#### 8.2.4 `POST /board/api/issues`

Creates a new issue.

Request body:

```json
{
  "title": "Fix login bug",
  "description": "Users cannot log in with SSO",
  "state": "Todo",
  "priority": 2,
  "labels": "bug,auth"
}
```

All fields except `title` are optional. Labels may be a comma-separated string or an array.

Response:

- `201 Created`
- Body: the created issue record

#### 8.2.5 `GET /board/api/issues/:id`

Returns a single issue by ID.

Response:

- `200 OK` — issue record
- `404 Not Found` — `{"error": "not_found"}`

#### 8.2.6 `PATCH /board/api/issues/:id`

Updates issue fields. Only provided fields are updated.

Request body (example):

```json
{
  "title": "Updated title",
  "priority": 1
}
```

Response:

- `200 OK` — updated issue record
- `404 Not Found` — `{"error": "not_found"}`

#### 8.2.7 `PATCH /board/api/issues/:id/move`

Moves an issue to a new state (column).

Request body:

```json
{
  "state": "In Progress"
}
```

Response:

- `200 OK` — updated issue record
- `400 Bad Request` — `{"error": "state is required"}` (if `state` is missing or empty)
- `404 Not Found` — `{"error": "not_found"}`

#### 8.2.8 `DELETE /board/api/issues/:id`

Deletes an issue permanently.

Response:

- `200 OK` — `{"deleted": true}`
- `404 Not Found` — `{"error": "not_found"}`

#### 8.2.9 `GET /board/api/states`

Returns the list of configured board columns.

Response:

- `200 OK`
- Body: `{"states": ["Backlog", "Todo", "In Progress", "Review", "Done", "Archived", "Cancelled"]}`

#### 8.2.10 `GET /board/tech-tree`

Returns the tech tree HTML page for issue lineage visualization.

Response:

- `200 OK`
- Content-Type: `text/html`
- Body: full HTML document from `TechTreeUI.render/0`

#### 8.2.11 `GET /board/issues/:id`

Returns the issue detail HTML page.

Response:

- `200 OK`
- Content-Type: `text/html`
- `404 Not Found`

#### 8.2.12 Project CRUD

| Method | Path | Description |
|---|---|---|
| `GET` | `/board/api/projects` | List all projects (`{"projects": [...]}`) |
| `POST` | `/board/api/projects` | Create project (201) |
| `GET` | `/board/api/projects/:id` | Get project by ID |
| `PATCH` | `/board/api/projects/:id` | Update project fields |
| `DELETE` | `/board/api/projects/:id` | Delete project (cascade deletes all linked issues) |
| `POST` | `/board/api/projects/:id/clone` | Clone project repository |

Cascade delete: when a project is deleted, all issues with a matching `project_id` are also
removed.

#### 8.2.13 Templates

| Method | Path | Description |
|---|---|---|
| `GET` | `/board/api/templates` | List built-in issue templates |
| `GET` | `/board/api/templates/:id` | Get template by ID |

#### 8.2.14 Settings

| Method | Path | Description |
|---|---|---|
| `GET` | `/board/settings` | Settings page HTML |
| `GET` | `/board/api/settings` | Get all settings as JSON |
| `PATCH` | `/board/api/settings` | Update settings |
| `POST` | `/board/api/settings/reset` | Reset settings to defaults |

### 8.3 Error Format

All error responses use a JSON object with an `error` key:

```json
{"error": "not_found"}
{"error": "state is required"}
```

Unmatched routes return `404` with `{"error": "not_found"}`.

### 8.4 Content Types

- All API responses set `Content-Type: application/json`.
- The board UI endpoint sets `Content-Type: text/html`.
- Request body parsing accepts `application/json` (via `Plug.Parsers`).

## 9. Web UI Specification

### 9.1 Rendering Architecture

The board UI is a server-rendered single-page application:

- `BoardUI.render/0` returns a complete HTML document containing inline CSS and JavaScript.
- No build step, bundler, or external asset dependencies.
- No framework (vanilla JavaScript).
- The HTML is generated at compile time as a module function return value.

### 9.2 Layout

The UI consists of:

1. `Top Bar`
   - Application title ("Symphony Board").
   - "New Issue" button.
   - Navigation links: "Dashboard" (`/`), "Tech Tree" (`/board/tech-tree`), "Settings"
     (`/board/settings`).
   - Project filter dropdown.

2. `Board` (main area)
   - Horizontal scrolling container of columns.
   - One column per configured state.
   - Each column has a header with state name, issue count, quick-add `+` button, and collapse
     toggle button.
   - Columns are collapsible — collapsed columns show only the state name rotated vertically.
   - Archived column is collapsed by default.

3. `Issue Cards`
   - Displayed within their state column.
   - Show: identifier, title, priority dot, label tags, project badge.
   - Clickable to open detail page (`/board/issues/:id`).
   - Draggable for column-to-column moves.

4. `Create/Edit Modal`
   - Form with: title (required), description, state (dropdown), priority (dropdown), labels,
     project (dropdown).
   - Reused for both create and edit operations.
   - Submit button text changes to "Create Issue" or "Update Issue" accordingly.

5. `Detail Page` (`/board/issues/:id`)
   - Shows all issue fields.
   - Supports inline editing via an Edit button that toggles edit mode.
   - Edit form includes: title, state dropdown, priority dropdown, labels, project dropdown,
     description textarea.
   - Save via `PATCH /board/api/issues/:id`, `Ctrl+S` shortcut to save, `Escape` to cancel.
   - Follow-up proposals section with accept/reject buttons.
   - Accepting a follow-up creates a new issue with `parent_issue_id` set to the current issue.
   - When all follow-ups are accepted or rejected, the issue auto-moves from "Review" to "Done".

### 9.3 Drag and Drop

Drag-and-drop is implemented using the HTML5 Drag and Drop API:

- `dragstart` — sets `dragging` class, stores issue ID in `dataTransfer`.
- `dragover` — adds `drag-over` class to target column.
- `dragleave` — removes `drag-over` class.
- `drop` — calls `PATCH /board/api/issues/:id/move` with the target column's state.
- `dragend` — cleans up `dragging` class.

State updates are optimistic: the board refreshes from the server after every mutation.

### 9.4 Quick Add

Each column header includes a `+` button that:

1. Shows an inline text input at the top of the column.
2. On Enter, creates a new issue via `POST /board/api/issues` with the column's state.
3. Clears the input and refreshes the board.

### 9.5 Keyboard Shortcuts

| Key | Action |
|---|---|
| `N` | Open create modal |
| `J` / `K` | Navigate issues (down / up) |
| `P` | Toggle project filter |
| `R` | Refresh board |
| `?` | Show help toast |
| `Escape` | Close modals |

Shortcuts are suppressed when focus is inside an `input`, `textarea`, or `select` element.

### 9.6 Auto-Refresh

The board polls `GET /board/api/snapshot` every 10 seconds and re-renders the column layout.

This allows external mutations (for example, the orchestrator moving an issue to a terminal state)
to appear in the UI without manual refresh.

### 9.7 Visual Design

The UI uses a dark colour theme inspired by modern project management tools:

- Background: `#0d1117` (near-black).
- Surface: `#161b22` (dark gray).
- Cards: `#21262d` (medium gray).
- Text: `#c9d1d9` (light gray).
- Primary accent: `#58a6ff` (blue).
- Danger: `#f85149` (red).

Priority indicators are colour-coded dots:

| Priority | Colour |
|---|---|
| 1 (Urgent) | `#f85149` (red) |
| 2 (High) | `#d29922` (orange) |
| 3 (Medium) | `#58a6ff` (blue) |
| 4 (Low) | `#8b949e` (gray) |

Labels are rendered as pill-shaped tags with deterministic colours derived from a hash of the label
text.

Theme CSS variables are defined in `UIHelpers.theme_css/0` and shared across all UI pages (board,
tech tree, issue detail, settings, dashboard).

### 9.8 Tech Tree

The tech tree (`/board/tech-tree`) visualizes issue lineage as a horizontal tree:

- Root issues (those with no `parent_issue_id`) appear on the left.
- Follow-up issues branch to the right, connected by SVG bezier curve arrows with arrowheads.
- Nodes are color-coded by state (green = Done, yellow = Active, purple = Review, blue = Root).
- The tree supports pan/drag navigation and a project filter dropdown.
- Layout uses a recursive subtree height algorithm with configurable node width, height, and gap.

### 9.9 Review Lane and Auto-Archive

- When an agent completes work and proposes follow-ups, the orchestrator moves the issue to
  "Review" instead of "Done".
- The issue detail page shows follow-up proposals with accept/reject buttons.
- Accepting a follow-up creates a new issue with `parent_issue_id` set to the parent.
- When all follow-ups are resolved (accepted or rejected), the issue auto-moves to "Done".
- The orchestrator's `run_tick` includes an `auto_archive_done_issues` step that moves Done issues
  older than 1 day to "Archived".

### 9.10 Cascade Delete

Deleting a project via `DELETE /board/api/projects/:id` also removes all issues where
`project_id` matches the deleted project's ID.

## 10. Integration with Symphony Orchestrator

### 10.1 Transparent Substitution

The Local Board integrates with the orchestrator without any orchestrator logic changes:

1. `Config.validate_dispatch/2` accepts `"local"` as a valid `tracker.kind` and skips API key
   and project slug validation.
2. `Config.local_board?/1` returns `true` when `tracker_kind == "local"`.
3. `Orchestrator.linear_client_module/1` returns `LocalBoard.Client` for local configs.
4. `AppServer.Client.linear_client_module/1` does the same for tool call handling.
5. `CLI.build_children/1` starts the `LocalBoard` GenServer and uses `CombinedRouter` for local
   configs.

### 10.2 Orchestrator Polling Cycle

From the orchestrator's perspective, a local board poll cycle is identical to a Linear poll cycle:

1. `fetch_candidate_issues(config)` → reads from GenServer instead of HTTP.
2. Sort, filter, and dispatch as normal.
3. `fetch_issue_states_by_ids(config, ids)` during reconciliation → reads from GenServer.
4. Workspace creation, prompt rendering, and agent dispatch are unchanged.

### 10.3 Token Exhaustion Circuit Breaker

The orchestrator detects LLM token exhaustion errors (context window exceeded, budget depleted) and
sets `token_budget_exceeded` on its internal state. When triggered:

- Auto-polling stops immediately to prevent further wasted API calls.
- All in-progress issues are moved back to Backlog.
- The orchestrator dashboard shows a red warning banner indicating token budget exhaustion.

This circuit breaker prevents runaway token spend and gives the operator a clear signal to
investigate before resuming.

### 10.4 Dashboard Link

When the local board is active, the orchestrator dashboard footer includes an "Open Board" link
pointing to `/board`.

## 11. Failure Model

### 11.1 GenServer Failures

- The `LocalBoard` GenServer is started under the normal supervision tree.
- If the GenServer crashes, the supervisor restarts it and it reloads from the JSON file.
- In-flight mutations during a crash are lost (last persisted state is recovered).

### 11.2 Persistence Failures

- `File.write!/2` raises on disk errors, which crashes the current GenServer call.
- The supervisor restarts the GenServer, which reloads the last successfully written state.
- Disk-full or permission errors are not silently swallowed.

### 11.3 Corrupt JSON File

- If the JSON file cannot be decoded, the board starts empty with a warning log.
- The original file is not deleted or renamed (operators can inspect and fix manually).

### 11.4 API Failures

- Missing issues return `404` with a JSON error body.
- Invalid move requests (missing `state`) return `400`.
- Unmatched routes return `404`.
- JSON parse errors in request bodies are handled by `Plug.Parsers`.

### 11.5 Behaviour Adapter Failures

- If the GenServer is down when the orchestrator polls, `LocalBoard.Client` catches the exception
  and returns `{:error, {:local_board_error, message}}`.
- The orchestrator treats this like a tracker fetch failure: logs and skips the tick.

## 12. Security Considerations

### 12.1 Trust Model

The Local Board inherits Symphony's trust model:

- The board API has no authentication or authorization.
- It is intended for single-operator, local use.
- The HTTP server binds to loopback by default.

### 12.2 Input Validation

- Issue titles are stored as-is (no HTML sanitization in the API layer).
- The board UI renders text content using `textContent` assignment, not `innerHTML`, preventing
  stored XSS in the Kanban view.
- Labels are split, trimmed, and stored as plain strings.
- Priority values are parsed to integers; invalid values default to `0`.
- Issue IDs are cryptographically random, making enumeration impractical.

### 12.3 File System Safety

- The JSON persistence file is written to the current working directory by default.
- The file path is configurable but not validated against directory traversal.
- Operators should ensure the working directory has appropriate permissions.

## 13. Reference Algorithms

### 13.1 Issue Creation

```text
function create_issue(attrs, board):
  now = utc_now_iso8601()
  id = base64url(crypto_random_bytes(12))
  identifier = board.project_prefix + "-" + board.next_number

  issue = {
    id, identifier,
    title: attrs.title or "Untitled",
    description: attrs.description or null,
    priority: parse_int(attrs.priority) or 0,
    state: attrs.state or first(board.states),
    labels: parse_labels(attrs.labels),
    project_id: attrs.project_id or null,
    parent_issue_id: attrs.parent_issue_id or null,
    created_at: now,
    updated_at: now,
    branch_name: null, url: null
  }

  board.issues[id] = issue
  board.next_number += 1
  persist(board)
  return issue
```

### 13.2 Board Snapshot

```text
function get_board_snapshot(board):
  columns = []
  for state in board.states:
    issues = filter(board.issues, issue.state == state)
    issues = sort_by(issues, [-priority, created_at])
    columns.append({state, issues})

  return {
    states: board.states,
    columns: columns,
    total_issues: count(board.issues),
    project_prefix: board.project_prefix,
    projects: values(board.projects)
  }
```

### 13.3 Behaviour Adapter Fetch

```text
function fetch_candidate_issues(config):
  records = LocalBoard.list_issues_by_states(config.active_states)
  return {:ok, map(records, to_issue_struct)}
```

### 13.4 Persistence Write

```text
function persist(board):
  data = {
    issues: values(board.issues) |> map(issue_to_json),
    projects: values(board.projects) |> map(project_to_json),
    states: board.states,
    next_number: board.next_number,
    project_prefix: board.project_prefix
  }
  file_write!(board.store_path, json_encode(data, pretty: true))
```

### 13.5 Persistence Load

```text
function load_from_disk(board):
  contents = file_read(board.store_path)
  if file_not_found:
    return board  # start empty

  data = json_decode(contents)
  if decode_failed:
    log_warning("corrupt file, starting fresh")
    return board

  issues = map(data.issues, json_to_issue) |> index_by(id)
  max_number = max(map(data.issues, extract_sequence_number))
  next_number = max(data.next_number, max_number + 1)

  return board with {issues, states, next_number, project_prefix} from data
```

## 14. Test and Validation Matrix

Current test counts: ExUnit has 333 tests, Playwright E2E has 77 tests.

### 14.1 LocalBoard GenServer Tests

- Create issue assigns sequential identifiers.
- Create issue defaults to first state.
- Create issue parses comma-separated labels.
- Create issue parses integer priority from string.
- List issues returns all issues sorted by priority then creation time.
- List issues by states filters with case-insensitive matching.
- Get issue by ID returns `{:ok, issue}` for existing issues.
- Get issue by ID returns `{:error, :not_found}` for missing issues.
- Get issues by IDs returns matching subset.
- Update issue modifies only provided fields.
- Update issue returns `{:error, :not_found}` for missing issues.
- Move issue changes state and updates timestamp.
- Move issue returns `{:error, :not_found}` for missing issues.
- Delete issue removes from store.
- Delete issue returns `{:error, :not_found}` for missing issues.
- List states returns configured states (including Review, Archived).
- Board snapshot groups issues by state with correct counts and includes projects.
- `to_issue_struct/1` produces a valid `Issue` struct with parsed DateTimes.
- Persistence: data survives GenServer stop and restart with same store path.
- Project CRUD: create, get, update, delete, list.
- Cascade delete: deleting a project removes all linked issues.
- Project persistence survives restart.
- Create issue with `project_id` links it to a project.
- Create issue with `parent_issue_id` links it to a parent issue.

### 14.2 LocalBoard.Client Tests

- `fetch_candidate_issues` returns issues in active states as `Issue` structs.
- `fetch_issues_by_states` returns filtered issues.
- `fetch_issues_by_states` with empty list returns empty without GenServer call.
- `fetch_issue_states_by_ids` returns matching issues as `Issue` structs.
- `fetch_issue_states_by_ids` with empty list returns empty without GenServer call.
- `execute_graphql` returns `{:error, :graphql_not_supported_on_local_board}`.

### 14.3 BoardRouter API Tests

- `GET /` returns 200 with HTML containing board markup.
- `GET /api/snapshot` returns 200 with JSON snapshot including `states`, `columns`, and `projects`.
- `GET /api/issues` returns 200 with issue list.
- `POST /api/issues` returns 201 with created issue containing generated ID and identifier.
- `GET /api/issues/:id` returns 200 for existing issue.
- `GET /api/issues/:id` returns 404 for missing issue.
- `PATCH /api/issues/:id` returns 200 with updated fields.
- `PATCH /api/issues/:id` returns 404 for missing issue.
- `PATCH /api/issues/:id/move` returns 200 with new state.
- `PATCH /api/issues/:id/move` returns 400 when state is missing.
- `PATCH /api/issues/:id/move` returns 404 for missing issue.
- `DELETE /api/issues/:id` returns 200 with `deleted: true`.
- `DELETE /api/issues/:id` returns 404 for missing issue.
- `GET /api/states` returns 200 with states list.
- `GET /tech-tree` returns 200 with HTML containing tech tree markup.
- Project CRUD endpoints return correct status codes.
- `DELETE /api/projects/:id` cascade deletes project issues.
- Template endpoints return built-in templates.
- Settings CRUD endpoints work correctly.
- Unmatched routes return 404 with JSON error.
- Board UI HTML contains `<main class="board"` element.

### 14.4 Integration Tests (Recommended)

- Orchestrator with `tracker.kind: "local"` starts `LocalBoard` GenServer and `CombinedRouter`.
- Creating an issue via `/board/api/issues` makes it visible to `fetch_candidate_issues`.
- Moving an issue to a terminal state via `/board/api/issues/:id/move` causes the orchestrator to
  stop the corresponding agent on the next reconciliation tick.
- Board state persists across service restart.

## 15. Implementation Checklist (Definition of Done)

### 15.1 Required for Conformance

- `LocalBoard` GenServer with in-memory issue store.
- Full CRUD operations (create, read, update, move, delete).
- JSON file persistence on every mutation.
- Load from JSON on startup (with corrupt-file fallback).
- Sequential identifier generation with configurable prefix.
- Configurable board states from workflow config.
- `LocalBoard.Client` implements all four `Linear.Behaviour` callbacks.
- `to_issue_struct/1` produces valid `Issue` structs.
- Orchestrator client module selection based on `tracker_kind`.
- Config validation accepts `"local"` as tracker kind without requiring API key.
- `CombinedRouter` serves board and dashboard on same port.
- `BoardRouter` exposes all CRUD endpoints with correct HTTP status codes.
- All tests from Section 14.1–14.3 pass.
- `mix compile --warnings-as-errors` clean.
- `mix credo --strict` clean.
- `mix format --check-formatted` clean.

### 15.2 Recommended Extensions (Not Required)

- `BoardUI` Kanban web interface with drag-and-drop. (DONE)
- Quick-add cards per column. (DONE)
- Keyboard shortcuts. (DONE)
- Auto-refresh. (DONE)
- Dark theme with priority and label colour coding. (DONE)
- Collapsible columns with Archived collapsed by default. (DONE)
- Projects with CRUD and cascade delete. (DONE)
- Tech tree visualization for issue lineage. (DONE)
- Issue detail page with follow-up management. (DONE)
- Settings page for runtime configuration. (DONE)
- Issue templates (code-review, bug-report, etc.). (DONE)
- Review lane with auto-move to Done. (DONE)
- Auto-archive Done issues after 1 day. (DONE)
- Shared `UIHelpers` module for DRY CSS theme and HTML escaping. (DONE)
- Inline issue editing on detail page. (DONE)
- Full keyboard shortcuts: N, J/K, P, R, ?, Escape. (DONE)
- Token exhaustion circuit breaker with dashboard banner. (DONE)
- TODO: WebSocket push for real-time board updates (replace polling).
- TODO: Issue comments/activity log.
- TODO: Board column reordering via UI.
- TODO: Issue search/filter in the UI.
- TODO: SQLite or ETS-backed persistence for higher throughput.
- TODO: Multi-user awareness (optimistic concurrency, last-write-wins).

### 15.3 Operational Validation (Recommended)

- Start Symphony with `tracker.kind: "local"` and verify the board is accessible at `/board`.
- Create issues via the UI and verify they appear in the orchestrator dashboard state.
- Move issues between columns and verify orchestrator reconciliation responds correctly.
- Kill and restart the service and verify board state is preserved.
- Verify on all target platforms (macOS, Linux, Windows).

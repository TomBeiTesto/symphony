defmodule SymphonyElixir.Server.BoardUI do
  @moduledoc """
  Server-rendered Kanban board UI with drag-and-drop.

  Renders a single-page HTML application that communicates with
  the board API endpoints. Styled to look like a modern project
  management tool.
  """

  @doc "Render the full Kanban board HTML page."
  @spec render() :: String.t()
  def render do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Symphony Board</title>
      <style>
    #{css()}
      </style>
    </head>
    <body>
      <header class="topbar">
        <div class="topbar-left">
          <svg class="logo" viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M8 12l2 2 4-4"/></svg>
          <h1>Symphony Board</h1>
          <select id="project-filter" class="project-select" onchange="handleProjectFilter()">
            <option value="">All Projects</option>
          </select>
        </div>
        <div class="topbar-right">
          <!-- Actions group -->
          <button class="btn btn-ghost" onclick="openProjectModal()">
            <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z"/></svg>
            Projects
          </button>
          <div class="dropdown" id="template-dropdown">
            <button class="btn btn-ghost" onclick="toggleTemplateDropdown()">
              <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="2"/><line x1="9" y1="3" x2="9" y2="21"/></svg>
              Templates
            </button>
            <div class="dropdown-menu template-menu-wide" id="template-menu"></div>
          </div>
          <span class="topbar-divider"></span>
          <!-- Auto-add popover -->
          <div class="dropdown" id="auto-add-dropdown">
            <button class="btn btn-ghost" onclick="toggleAutoAddDropdown()">
              <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 2v4m0 12v4m-7-7H1m22 0h-4M4.93 4.93l2.83 2.83m8.48 8.48l2.83 2.83m0-14.14l-2.83 2.83m-8.48 8.48l-2.83 2.83"/></svg>
              <span id="auto-add-label">Auto</span>
            </button>
            <div class="dropdown-menu auto-add-popover" id="auto-add-menu">
              <div class="popover-section">
                <label class="toggle-label">
                  <input type="checkbox" id="auto-add-toggle" onchange="handleAutoAddToggle()">
                  <span>Auto-dispatch issues</span>
                </label>
              </div>
              <div class="popover-section">
                <label class="parallel-label">
                  Max active / project:
                  <select id="max-todo-select" onchange="handleMaxTodoChange()">
                    <option value="1">1</option>
                    <option value="2">2</option>
                    <option value="3" selected>3</option>
                  </select>
                </label>
              </div>
              <div class="popover-section">
                <label class="toggle-label">
                  <input type="checkbox" id="segregate-toggle" onchange="handleSegregateToggle()">
                  <span>Group by Project</span>
                </label>
              </div>
            </div>
          </div>
          <span class="topbar-divider"></span>
          <!-- Nav group -->
          <div class="topbar-nav">
            <a href="/board/projects" class="btn btn-ghost" title="Projects">
              <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 19a2 2 0 01-2 2H4a2 2 0 01-2-2V5a2 2 0 012-2h5l2 3h9a2 2 0 012 2z"/></svg>
              Projects
            </a>
            <a href="/board/task-lineage" class="btn btn-ghost" title="Task Lineage">
              <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><circle cx="4" cy="12" r="2"/><circle cx="12" cy="6" r="2"/><circle cx="12" cy="18" r="2"/><circle cx="20" cy="12" r="2"/><line x1="6" y1="12" x2="10" y2="7"/><line x1="6" y1="12" x2="10" y2="17"/><line x1="14" y1="7" x2="18" y2="11"/><line x1="14" y1="17" x2="18" y2="13"/></svg>
              Lineage
            </a>
            <a href="/board/review" class="btn btn-ghost" title="Product Review">
              <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/></svg>
              Review
            </a>
            <a href="/" class="btn btn-ghost" title="Dashboard">
              <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="2"/><line x1="3" y1="9" x2="21" y2="9"/><line x1="9" y1="21" x2="9" y2="9"/></svg>
            </a>
            <a href="/board/settings" class="btn btn-ghost" title="Settings">
              <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 010 2.83 2 2 0 01-2.83 0l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V21a2 2 0 01-4 0v-.09A1.65 1.65 0 009 19.4a1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 01-2.83-2.83l.06-.06A1.65 1.65 0 004.68 15a1.65 1.65 0 00-1.51-1H3a2 2 0 010-4h.09A1.65 1.65 0 004.6 9a1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 012.83-2.83l.06.06A1.65 1.65 0 009 4.68a1.65 1.65 0 001-1.51V3a2 2 0 014 0v.09a1.65 1.65 0 001 1.51 1.65 1.65 0 001.82-.33l.06-.06a2 2 0 012.83 2.83l-.06.06A1.65 1.65 0 0019.4 9a1.65 1.65 0 001.51 1H21a2 2 0 010 4h-.09a1.65 1.65 0 00-1.51 1z"/></svg>
            </a>
          </div>
          <button class="btn btn-primary" onclick="openCreateModal()">
            <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
            New Issue
          </button>
        </div>
      </header>

      <!-- Metrics bar -->
      <div class="metrics-bar" id="metrics-bar"></div>

      <main class="board" id="board"></main>

      <!-- Create/Edit Modal -->
      <div class="modal-overlay" id="modal-overlay" onclick="closeModal()">
        <div class="modal" onclick="event.stopPropagation()">
          <div class="modal-header">
            <h2 id="modal-title">New Issue</h2>
            <button class="btn-icon" onclick="closeModal()">&times;</button>
          </div>
          <form id="issue-form" onsubmit="handleSubmit(event)">
            <input type="hidden" id="form-id" value="">
            <div class="form-group">
              <label for="form-title">Title</label>
              <input type="text" id="form-title" required placeholder="Issue title..." autofocus>
            </div>
            <div class="form-group">
              <label for="form-description">Description</label>
              <textarea id="form-description" rows="6" placeholder="Describe the issue..."></textarea>
            </div>
            <div class="form-row">
              <div class="form-group">
                <label for="form-state">State</label>
                <select id="form-state"></select>
              </div>
              <div class="form-group">
                <label for="form-priority">Priority</label>
                <select id="form-priority">
                  <option value="0">No priority</option>
                  <option value="1">Urgent</option>
                  <option value="2">High</option>
                  <option value="3">Medium</option>
                  <option value="4">Low</option>
                </select>
              </div>
            </div>
            <div class="form-group">
              <label for="form-labels">Labels (comma-separated)</label>
              <input type="text" id="form-labels" placeholder="bug, frontend, urgent">
            </div>
            <div class="form-group">
              <label for="form-project">Project</label>
              <select id="form-project">
                <option value="">No project</option>
              </select>
            </div>
            <div class="form-group form-checkbox">
              <label>
                <input type="checkbox" id="form-followups" checked>
                Propose follow-up issues
              </label>
            </div>
            <div class="form-actions">
              <button type="button" class="btn btn-ghost" onclick="closeModal()">Cancel</button>
              <button type="submit" class="btn btn-primary" id="form-submit">Create Issue</button>
            </div>
          </form>
        </div>
      </div>

      <!-- Issue Detail Modal -->
      <div class="modal-overlay" id="detail-overlay" onclick="closeDetailModal()">
        <div class="modal modal-wide" onclick="event.stopPropagation()">
          <div class="modal-header">
            <div class="detail-id" id="detail-identifier"></div>
            <div class="detail-actions">
              <button class="btn btn-ghost btn-sm" onclick="editFromDetail()">Edit</button>
              <button class="btn btn-danger btn-sm" onclick="deleteFromDetail()">Delete</button>
              <button class="btn-icon" onclick="closeDetailModal()">&times;</button>
            </div>
          </div>
          <div class="detail-body">
            <h2 id="detail-title"></h2>
            <div class="detail-meta">
              <span class="badge" id="detail-state"></span>
              <span class="priority-dot" id="detail-priority-dot"></span>
              <span id="detail-priority-text"></span>
            </div>
            <div class="detail-description" id="detail-description"></div>
            <div class="detail-labels" id="detail-labels"></div>
            <div class="detail-timestamps">
              <small id="detail-created"></small>
              <small id="detail-updated"></small>
            </div>
          </div>
        </div>
      </div>

      <!-- Project Modal -->
      <div class="modal-overlay" id="project-overlay" onclick="closeProjectModal()">
        <div class="modal modal-wide" onclick="event.stopPropagation()">
          <div class="modal-header">
            <h2 id="project-modal-title">Projects</h2>
            <button class="btn-icon" onclick="closeProjectModal()">&times;</button>
          </div>
          <div id="project-list-view">
            <input type="text" class="project-filter" id="project-filter" placeholder="Filter projects..." oninput="filterProjects(this.value)">
            <div id="project-list" class="project-list"></div>
            <div class="form-actions" style="margin-top: 16px; gap: 8px;">
              <button class="btn btn-primary" onclick="showProjectForm()">
                <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
                New Project
              </button>
              <button class="btn btn-accent" onclick="showScanView()">
                <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 19a2 2 0 01-2 2H4a2 2 0 01-2-2V5a2 2 0 012-2h5l2 3h9a2 2 0 012 2z"/></svg>
                Import from Directory
              </button>
            </div>
          </div>
          <div id="scan-view" style="display:none">
            <div class="form-group">
              <label for="scan-root-path">Root Directory</label>
              <div style="display:flex; gap: 8px;">
                <input type="text" id="scan-root-path" placeholder="C:\\Projects or /home/user/repos" style="flex:1">
                <button class="btn btn-primary" onclick="scanDirectory()" id="scan-btn">Scan</button>
              </div>
              <small style="color: var(--text-muted); margin-top: 4px; display: block;">Each subdirectory becomes a project. READMEs and package files are analyzed for titles and descriptions.</small>
            </div>
            <div style="display:flex; gap: 16px; margin-top: 8px;">
              <label style="display:flex; align-items:center; gap: 4px; cursor:pointer; font-size: 13px; color: var(--text-secondary);">
                <input type="checkbox" id="scan-git-pull"> Git pull latest
              </label>
              <label style="display:flex; align-items:center; gap: 4px; cursor:pointer; font-size: 13px; color: var(--text-secondary);">
                <input type="checkbox" id="scan-recursive"> Detect monorepos
              </label>
            </div>
            <div id="scan-results" style="margin-top: 12px;"></div>
            <div class="form-actions" style="margin-top: 16px;">
              <button class="btn btn-ghost" onclick="hideScanView()">Back</button>
              <button class="btn btn-primary" id="import-btn" style="display:none" onclick="importScannedProjects()">Import Selected</button>
            </div>
          </div>
          <form id="project-form" style="display:none" onsubmit="handleProjectSubmit(event)">
            <input type="hidden" id="proj-id" value="">
            <div class="form-group">
              <label for="proj-name">Project Name</label>
              <input type="text" id="proj-name" required placeholder="My Project">
            </div>
            <div class="form-group">
              <label for="proj-description">Description</label>
              <textarea id="proj-description" rows="2" placeholder="What is this project about?"></textarea>
            </div>
            <div class="form-group">
              <label for="proj-path">Local Directory Path</label>
              <input type="text" id="proj-path" placeholder="C:\\Projects\\my-app or /home/user/projects/my-app">
            </div>
            <div class="form-group">
              <label for="proj-repo">Repository URL (optional — will clone)</label>
              <input type="text" id="proj-repo" placeholder="https://github.com/user/repo.git">
            </div>
            <div class="form-actions">
              <button type="button" class="btn btn-ghost" onclick="hideProjectForm()">Cancel</button>
              <button type="submit" class="btn btn-primary" id="proj-submit">Create Project</button>
            </div>
          </form>
        </div>
      </div>

      <script>
    #{javascript()}
      </script>
    </body>
    </html>
    """
  end

  defp css do
    alias SymphonyElixir.Server.UIHelpers
    UIHelpers.base_css() <> UIHelpers.topbar_css() <> UIHelpers.button_css() <>
    UIHelpers.form_css() <> UIHelpers.modal_css() <> UIHelpers.badge_css() <>
    UIHelpers.toast_css() <> UIHelpers.skeleton_css() <>
      ~S"""

      body {
        height: 100vh;
        display: flex;
        flex-direction: column;
        overflow: hidden;
      }

      /* --- Metrics Bar (#6) --- */
      .metrics-bar {
        display: flex;
        align-items: center;
        gap: 16px;
        padding: 4px 20px;
        border-bottom: 1px solid var(--border-light);
        background: var(--bg-secondary);
        flex-shrink: 0;
        font-size: 0.75rem;
        color: var(--text-muted);
        min-height: 28px;
      }
      .metric { display: flex; align-items: center; gap: 4px; }
      .metric-val { font-weight: 600; color: var(--text-secondary); }
      .metric-dot { width: 6px; height: 6px; border-radius: 50%; }

      /* --- Auto-add popover (#2) --- */
      .auto-add-popover { min-width: 240px; padding: 8px 0; }
      .popover-section { padding: 8px 14px; border-bottom: 1px solid var(--border-light); }
      .popover-section:last-child { border-bottom: none; }
      .toggle-label, .parallel-label {
        display: flex; align-items: center; gap: 6px;
        color: var(--text-secondary); cursor: pointer; font-size: 0.82rem;
      }
      .toggle-label input[type="checkbox"] { accent-color: var(--accent); width: 15px; height: 15px; cursor: pointer; }
      .parallel-label select {
        background: var(--bg-primary); color: var(--text-primary);
        border: 1px solid var(--border); border-radius: var(--radius-sm);
        padding: 2px 6px; font-size: 0.82rem; cursor: pointer;
      }

      /* --- Project group headers --- */
      .project-group-header {
        font-size: 0.72rem; font-weight: 600; color: var(--text-muted);
        text-transform: uppercase; letter-spacing: 0.04em;
        padding: 8px 4px 4px; border-bottom: 1px solid var(--border-light);
        margin-bottom: 4px; display: flex; align-items: center; gap: 6px;
      }
      .project-group-header .pg-dot { width: 8px; height: 8px; border-radius: 50%; background: var(--accent); flex-shrink: 0; }

      /* --- Board (#7,#8) --- */
      .board {
        display: flex; gap: 0; padding: 0;
        flex: 1; overflow-x: auto; overflow-y: hidden;
      }

      .column {
        flex: 1 1 0; min-width: 180px;
        display: flex; flex-direction: column;
        border-right: 1px solid var(--border-light);
        height: 100%; transition: min-width 0.2s, flex 0.2s;
      }
      .column:last-child { border-right: none; }
      .column.collapsed {
        flex: 0 0 40px; min-width: 40px; max-width: 40px; cursor: pointer;
      }
      .column.collapsed .column-body,
      .column.collapsed .quick-add { display: none; }
      .column.collapsed .column-header {
        writing-mode: vertical-lr; text-orientation: mixed;
        padding: 12px 6px; flex-direction: column; align-items: center;
        gap: 10px; flex: 1;
      }
      .column.collapsed .column-title-group { flex-direction: column; gap: 8px; }
      .column.collapsed .column-count { writing-mode: horizontal-tb; }

      /* --- Column header (#15,#16) --- */
      .column-header {
        padding: 10px 12px 8px;
        display: flex; align-items: center; justify-content: space-between;
        flex-shrink: 0;
        border-bottom: 2px solid var(--column-accent, var(--border-light));
        background: var(--bg-secondary);
      }
      .column-title-group { display: flex; align-items: center; gap: 6px; }
      .column-dot { width: 8px; height: 8px; border-radius: 50%; background: var(--column-accent, var(--text-muted)); flex-shrink: 0; }
      .column-title { font-size: 0.75rem; font-weight: 600; color: var(--text-secondary); text-transform: uppercase; letter-spacing: 0.04em; }
      .column-count {
        font-size: 0.72rem; color: var(--text-primary); font-weight: 600;
        background: var(--bg-tertiary); padding: 1px 7px; border-radius: 10px;
        min-width: 20px; text-align: center;
      }
      /* Column completion bar (#33) */
      .column-progress { height: 2px; background: var(--bg-tertiary); border-radius: 1px; margin-top: 4px; overflow: hidden; }
      .column-progress-fill { height: 100%; border-radius: 1px; transition: width 0.3s ease; }
      /* WIP limit (#34) */
      .wip-badge { font-size: 0.65rem; color: var(--text-muted); padding: 1px 5px; border-radius: 8px; background: var(--bg-tertiary); }
      .wip-badge.over-limit { color: var(--red); background: rgba(248,81,73,0.15); }

      .btn-collapse {
        background: none; border: none; color: var(--text-muted);
        cursor: pointer; padding: 2px; border-radius: 4px;
        display: flex; align-items: center; opacity: 0; transition: opacity 0.15s;
      }
      .column-header:hover .btn-collapse { opacity: 1; }
      .btn-collapse:hover { color: var(--text-primary); background: var(--bg-tertiary); }

      .column-body { flex: 1; overflow-y: auto; padding: 6px; min-height: 60px; }
      .column-body.drag-over {
        background: rgba(88,166,255,0.06);
        outline: 2px dashed var(--accent); outline-offset: -4px; border-radius: 4px;
      }

      /* --- Cards (#9,#10,#19,#20,#22,#23) --- */
      .card {
        background: var(--bg-secondary); border: 1px solid var(--border);
        border-radius: var(--radius-sm); padding: 8px 10px; margin-bottom: 4px;
        cursor: grab; transition: all var(--transition);
        position: relative; border-left: 3px solid transparent;
      }
      .card:hover {
        border-color: var(--border); border-left-color: var(--accent);
        background: var(--bg-tertiary); transform: translateX(1px);
      }
      .card.dragging { opacity: 0.4; transform: rotate(2deg); }
      .card.kb-focused { outline: 2px solid var(--accent); outline-offset: -2px; border-left-color: var(--accent); }
      /* P1/P2 visual weight (#20) */
      .card.priority-high { box-shadow: inset 0 0 0 1px rgba(248,81,73,0.2); }

      .card-identifier {
        font-size: 0.65rem; color: var(--text-muted); font-weight: 500;
        margin-bottom: 2px;
        font-family: 'SF Mono', SFMono-Regular, Consolas, monospace;
      }
      .card-title {
        font-size: 0.82rem; font-weight: 500; color: var(--text-primary);
        line-height: 1.35; margin-bottom: 6px;
        display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden;
      }
      .card-meta { display: flex; align-items: center; gap: 5px; flex-wrap: wrap; }
      /* Age indicator (#23) */
      .card-age { font-size: 0.6rem; color: var(--text-muted); opacity: 0.6; margin-left: auto; }
      .card-age.stale { color: var(--red); opacity: 0.8; }

      .priority-dot { width: 7px; height: 7px; border-radius: 50%; display: inline-block; }
      .priority-1 { background: var(--red); }
      .priority-2 { background: var(--orange); }
      .priority-3 { background: var(--yellow); }
      .priority-4 { background: var(--accent); }
      .priority-0 { background: var(--text-muted); }

      .label-tag {
        font-size: 0.65rem; padding: 1px 5px; border-radius: 8px;
        background: var(--bg-tertiary); color: var(--text-secondary); border: 1px solid var(--border);
      }

      /* --- Detail Modal (#11) --- */
      .detail-id { font-size: 0.85rem; color: var(--text-muted); font-weight: 500; }
      .detail-actions { display: flex; gap: 6px; align-items: center; }
      .detail-body h2 { font-size: 1.15rem; margin-bottom: 12px; }
      .detail-meta { display: flex; align-items: center; gap: 10px; margin-bottom: 16px; }
      .detail-description { font-size: 0.9rem; color: var(--text-secondary); line-height: 1.6; margin-bottom: 16px; white-space: pre-wrap; }
      .detail-labels { display: flex; gap: 6px; flex-wrap: wrap; margin-bottom: 12px; }
      .detail-timestamps { display: flex; gap: 16px; color: var(--text-muted); font-size: 0.75rem; }

      /* --- Form overrides for board --- */
      .form-checkbox label { display: flex; align-items: center; gap: 8px; cursor: pointer; font-size: 13px; color: var(--text-secondary); }
      .form-checkbox input[type="checkbox"] { width: 16px; height: 16px; accent-color: var(--purple); cursor: pointer; }

      /* --- Empty State --- */
      .empty-column {
        display: flex; flex-direction: column; align-items: center; justify-content: center;
        padding: 24px 12px; color: var(--text-muted); font-size: 0.78rem; min-height: 80px;
      }
      .empty-column-icon { width: 28px; height: 28px; margin-bottom: 6px; opacity: 0.3; }

      /* --- Quick Add (#26) --- */
      .quick-add { padding: 4px 6px 6px; border-top: 1px solid var(--border-light); flex-shrink: 0; background: var(--bg-secondary); }
      .quick-add-input {
        width: 100%; padding: 6px 8px; background: transparent;
        border: 1px dashed var(--border); border-radius: var(--radius-sm);
        color: var(--text-primary); font-size: 0.78rem; outline: none;
        font-family: inherit; transition: all var(--transition);
      }
      .quick-add-input:focus { border-color: var(--accent); border-style: solid; background: var(--bg-primary); }
      .quick-add-input::placeholder { color: var(--text-muted); }

      /* --- Project Select --- */
      .project-select {
        padding: 4px 8px; background: var(--bg-primary); border: 1px solid var(--border);
        border-radius: var(--radius-sm); color: var(--text-secondary);
        font-size: 0.78rem; outline: none; cursor: pointer;
      }
      .project-select:focus { border-color: var(--accent); }

      /* --- Dropdown --- */
      .dropdown { position: relative; }
      .dropdown-menu {
        display: none; position: absolute; top: 100%; right: 0;
        margin-top: 4px; background: var(--bg-secondary); border: 1px solid var(--border);
        border-radius: var(--radius-sm); min-width: 220px;
        box-shadow: var(--shadow); z-index: 100; padding: 4px 0;
      }
      .dropdown-menu.open { display: block; }
      .dropdown-item {
        display: block; width: 100%; padding: 7px 14px;
        background: none; border: none; color: var(--text-primary);
        font-size: 0.82rem; text-align: left; cursor: pointer;
        transition: background var(--transition);
      }
      .dropdown-item:hover { background: var(--bg-hover); }
      .dropdown-item small { display: block; color: var(--text-muted); font-size: 0.72rem; margin-top: 2px; }
      .template-menu-wide { min-width: 320px; max-height: 400px; overflow-y: auto; }
      .template-item { padding: 10px 14px; border-bottom: 1px solid var(--border-light); }
      .template-item:last-child { border-bottom: none; }
      .template-item:hover { background: var(--bg-hover); }
      .template-item .tmpl-name { font-weight: 600; font-size: 0.85rem; color: var(--text-primary); margin-bottom: 3px; }
      .template-item .tmpl-desc { font-size: 0.72rem; color: var(--text-muted); line-height: 1.3; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; margin-bottom: 4px; }
      .template-item .tmpl-labels { display: flex; gap: 4px; flex-wrap: wrap; }
      .template-item .tmpl-label { font-size: 0.65rem; background: var(--bg-tertiary); color: var(--text-muted); padding: 1px 6px; border-radius: 3px; }
      .template-item .tmpl-priority { font-size: 0.65rem; color: var(--text-muted); margin-left: auto; }

      /* --- Project List --- */
      .project-filter { width: 100%; padding: 6px 10px; margin-bottom: 8px; border: 1px solid var(--border); border-radius: var(--radius-sm); background: var(--bg-primary); color: var(--text-primary); font-size: 0.85rem; }
      .project-filter:focus { outline: none; border-color: var(--accent); }
      .project-list { max-height: 50vh; overflow-y: auto; }
      .project-card {
        display: flex; align-items: center; justify-content: space-between;
        padding: 6px 10px; border: 1px solid var(--border);
        border-radius: var(--radius-sm); margin-bottom: 4px;
        background: var(--bg-primary); transition: background var(--transition);
      }
      .project-card:hover { background: var(--bg-hover); }
      .project-info { flex: 1; min-width: 0; }
      .project-info h3 { font-size: 0.85rem; font-weight: 600; margin: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
      .project-info .project-desc { font-size: 0.75rem; color: var(--text-secondary); margin-top: 1px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
      .project-info .project-meta { font-size: 0.75rem; color: var(--text-muted); display: flex; gap: 8px; margin-top: 1px; }
      .project-info .project-meta span { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
      .project-actions { display: flex; gap: 4px; flex-shrink: 0; margin-left: 8px; }
      .project-empty { color: var(--text-muted); font-style: italic; padding: 20px; text-align: center; }

      .btn-clear-col {
        background: none; border: none; color: var(--text-muted);
        cursor: pointer; padding: 2px 4px; border-radius: 4px;
        opacity: 0.6; transition: all var(--transition);
      }
      .btn-clear-col:hover { opacity: 1; color: var(--red); background: rgba(248,81,73,0.1); }

      .card-delete {
        position: absolute; top: 3px; right: 3px;
        background: none; border: none; color: var(--text-muted);
        cursor: pointer; font-size: 13px; line-height: 1; padding: 2px 4px;
        border-radius: 4px; opacity: 0; transition: all var(--transition);
      }
      .card:hover .card-delete { opacity: 0.6; }
      .card-delete:hover { opacity: 1; color: var(--red); background: rgba(248,81,73,0.15); }

      .scan-list { max-height: 400px; overflow-y: auto; }
      .scan-card {
        padding: 10px 12px; border: 1px solid var(--border); border-radius: var(--radius-sm);
        margin-bottom: 6px; background: var(--bg-primary);
      }
      .scan-card:hover { background: var(--bg-hover); }

      /* --- Card project badge --- */
      .card-project {
        font-size: 0.62rem; padding: 1px 5px; border-radius: 8px;
        background: rgba(88,166,255,0.1); color: var(--accent); border: 1px solid rgba(88,166,255,0.2);
      }

      /* --- Mobile (#44,#45) --- */
      @media (max-width: 768px) {
        .topbar-nav a span { display: none; }
        .topbar-divider { display: none; }
        .topbar { padding: 8px 12px; }
        .topbar-right { gap: 3px; }
        .board { flex-direction: column; overflow-y: auto; overflow-x: hidden; }
        .column { min-width: 100%; max-width: 100%; border-right: none; border-bottom: 1px solid var(--border-light); height: auto; }
        .column-body { max-height: 400px; }
        .column.collapsed { flex: 0 0 36px; min-width: 100%; max-width: 100%; }
        .column.collapsed .column-header { writing-mode: horizontal-tb; padding: 8px 12px; flex-direction: row; }
        .column.collapsed .column-title-group { flex-direction: row; }
        .metrics-bar { overflow-x: auto; white-space: nowrap; }
      }
      """
  end

  defp javascript do
    ~S"""
    const API = '/board/api';
    let boardData = null;
    let projects = [];
    let templates = [];
    let currentDetailIssue = null;
    let draggedCard = null;
    let currentProjectFilter = '';
    let segregateByProject = false;
    let loadPending = false;
    let lastLoadTime = 0;

    // --- Fetch & Render (#27 skeleton, #28 loading, #29 debounce, #31 scroll preserve) ---
    async function loadBoard() {
      var now = Date.now();
      if (loadPending || (now - lastLoadTime < 500)) return; // debounce
      loadPending = true;
      lastLoadTime = now;

      // Show skeleton on first load
      if (!boardData) {
        var board = document.getElementById('board');
        board.innerHTML = '<div style="display:flex;gap:0;flex:1;padding:16px;">' +
          Array(5).fill('<div style="flex:1;padding:8px;"><div class="skeleton skeleton-text"></div><div class="skeleton skeleton-card"></div><div class="skeleton skeleton-card"></div></div>').join('') + '</div>';
      }

      try {
        // Preserve scroll positions (#31)
        var scrollPositions = {};
        document.querySelectorAll('.column-body').forEach(function(el) {
          if (el.scrollTop > 0) scrollPositions[el.dataset.state] = el.scrollTop;
        });

        const [snapRes, projRes, tmplRes] = await Promise.all([
          fetch(`${API}/snapshot`),
          fetch(`${API}/projects`),
          fetch(`${API}/templates`)
        ]);
        boardData = await snapRes.json();
        const projData = await projRes.json();
        projects = projData.projects || [];
        const tmplData = await tmplRes.json();
        templates = tmplData.templates || [];
        renderBoard();
        renderMetricsBar();
        populateProjectFilter();
        populateTemplateMenu();

        // Restore scroll positions
        document.querySelectorAll('.column-body').forEach(function(el) {
          if (scrollPositions[el.dataset.state]) el.scrollTop = scrollPositions[el.dataset.state];
        });
      } catch (e) {
        console.error('Failed to load board:', e);
      } finally {
        loadPending = false;
      }
    }

    const COLUMN_COLORS = {
      'backlog': '#8b949e',
      'todo': '#d29922',
      'in progress': '#58a6ff',
      'review': '#bc8cff',
      'done': '#3fb950',
      'archived': '#484f58',
      'cancelled': '#f85149'
    };

    const BADGE_CLASSES = {
      'backlog': 'badge-backlog', 'todo': 'badge-todo',
      'in progress': 'badge-in-progress', 'review': 'badge-review',
      'done': 'badge-done', 'cancelled': 'badge-cancelled',
      'archived': 'badge-archived'
    };

    // Terminal columns: default collapsed (#17)
    const TERMINAL_STATES = ['Done', 'Archived', 'Cancelled'];

    function getColumnColor(state) {
      return COLUMN_COLORS[state.toLowerCase()] || '#8b949e';
    }

    // Collapse state with localStorage persistence (#18)
    var collapsedColumns = JSON.parse(localStorage.getItem('symphony_collapsed') || 'null');
    if (!collapsedColumns) {
      collapsedColumns = {};
      TERMINAL_STATES.forEach(function(s) { collapsedColumns[s] = true; });
    }

    function toggleColumn(state) {
      collapsedColumns[state] = !collapsedColumns[state];
      localStorage.setItem('symphony_collapsed', JSON.stringify(collapsedColumns));
      renderBoard();
    }

    // --- Metrics bar (#6, #37) ---
    function renderMetricsBar() {
      var bar = document.getElementById('metrics-bar');
      if (!boardData || !boardData.columns) return;
      var total = 0, byState = {};
      boardData.columns.forEach(function(col) {
        var n = col.issues.length;
        total += n;
        byState[col.state] = n;
      });
      var active = (byState['In Progress'] || 0) + (byState['Review'] || 0);
      var done = byState['Done'] || 0;
      var todo = byState['Todo'] || 0;
      var backlog = byState['Backlog'] || 0;

      bar.innerHTML =
        '<span class="metric"><span class="metric-val">' + total + '</span> total</span>' +
        '<span class="metric"><span class="metric-dot" style="background:var(--accent)"></span><span class="metric-val">' + active + '</span> active</span>' +
        '<span class="metric"><span class="metric-dot" style="background:var(--yellow)"></span><span class="metric-val">' + todo + '</span> todo</span>' +
        '<span class="metric"><span class="metric-dot" style="background:var(--green)"></span><span class="metric-val">' + done + '</span> done</span>' +
        (backlog > 0 ? '<span class="metric"><span class="metric-val">' + backlog + '</span> backlog</span>' : '');
    }

    // --- Auto-add popover toggle ---
    function toggleAutoAddDropdown() {
      document.getElementById('auto-add-menu').classList.toggle('open');
    }
    document.addEventListener('click', function(e) {
      if (!e.target.closest('#auto-add-dropdown')) {
        document.getElementById('auto-add-menu').classList.remove('open');
      }
    });

    function renderBoard() {
      const board = document.getElementById('board');
      board.innerHTML = '';
      var totalIssues = 0;
      boardData.columns.forEach(function(col) { totalIssues += col.issues.length; });

      boardData.columns.forEach(col => {
        let issues = col.issues;
        if (currentProjectFilter) {
          issues = issues.filter(i => i.project_id === currentProjectFilter);
        }

        const color = getColumnColor(col.state);
        const isCollapsed = !!collapsedColumns[col.state];
        const column = document.createElement('div');
        column.className = 'column' + (isCollapsed ? ' collapsed' : '');
        column.style.setProperty('--column-accent', color);

        if (isCollapsed) {
          column.onclick = function() { toggleColumn(col.state); };
          column.title = 'Click to expand ' + col.state;
        }

        // Column completion bar (#33)
        var pctFill = totalIssues > 0 ? Math.round(issues.length / totalIssues * 100) : 0;
        var progressHtml = !isCollapsed ? '<div class="column-progress"><div class="column-progress-fill" style="width:' + pctFill + '%;background:' + color + '"></div></div>' : '';

        column.innerHTML = `
          <div class="column-header">
            <div class="column-title-group">
              <span class="column-dot"></span>
              <span class="column-title">${esc(col.state)}</span>
              <span class="column-count">${issues.length}</span>
            </div>
            ${!isCollapsed && issues.length > 0 && ['Backlog','Cancelled','Archived'].includes(col.state) ? `<button class="btn-clear-col" onclick="event.stopPropagation(); clearColumn('${esc(col.state)}')" title="Delete all ${esc(col.state)} issues">
              <svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 01-2 2H7a2 2 0 01-2-2V6m3 0V4a2 2 0 012-2h4a2 2 0 012 2v2"/></svg>
            </button>` : ''}
            ${!isCollapsed ? `<button class="btn-collapse" onclick="event.stopPropagation(); toggleColumn('${esc(col.state)}')" title="Collapse column">
              <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><polyline points="15 18 9 12 15 6"/></svg>
            </button>` : ''}
          </div>
          ${progressHtml}
          ${!isCollapsed ? `
          <div class="column-body" data-state="${esc(col.state)}"
               ondragover="handleDragOver(event)"
               ondragleave="handleDragLeave(event)"
               ondrop="handleDrop(event)">
            ${issues.length === 0 ?
              `<div class="empty-column">
                <svg class="empty-column-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
                  <rect x="3" y="3" width="18" height="18" rx="2"/>
                  <line x1="9" y1="12" x2="15" y2="12"/>
                </svg>
                No issues
              </div>` :
              renderColumnCards(issues)}
          </div>
          <div class="quick-add">
            <input class="quick-add-input"
                   placeholder="+ Add..."
                   data-state="${esc(col.state)}"
                   onkeydown="handleQuickAdd(event)">
          </div>
          ` : ''}
        `;
        board.appendChild(column);
      });
    }

    function renderColumnCards(issues) {
      if (!segregateByProject) {
        return issues.map(renderCard).join('');
      }
      // Group by project
      const groups = {};
      const order = [];
      issues.forEach(issue => {
        const pid = issue.project_id || '__none__';
        if (!groups[pid]) {
          groups[pid] = [];
          order.push(pid);
        }
        groups[pid].push(issue);
      });
      // Sort: named projects first (alphabetical), unassigned last
      order.sort((a, b) => {
        if (a === '__none__') return 1;
        if (b === '__none__') return -1;
        const na = (projects.find(p => p.id === a) || {}).name || '';
        const nb = (projects.find(p => p.id === b) || {}).name || '';
        return na.localeCompare(nb);
      });
      // Hide single UNASSIGNED header (#47)
      const showHeaders = !(order.length === 1 && order[0] === '__none__');
      let html = '';
      order.forEach(pid => {
        if (showHeaders) {
          const proj = pid !== '__none__' ? projects.find(p => p.id === pid) : null;
          const name = proj ? proj.name : 'Unassigned';
          html += `<div class="project-group-header"><span class="pg-dot"></span>${esc(name)} <span style="opacity:0.5;margin-left:auto">${groups[pid].length}</span></div>`;
        }
        html += groups[pid].map(renderCard).join('');
      });
      return html;
    }

    const PRIORITY_COLORS = { 1: '#f85149', 2: '#d18616', 3: '#d29922', 4: '#58a6ff' };

    const DELETABLE_STATES = ['Backlog', 'Cancelled', 'Archived'];

    function renderCard(issue) {
      const labels = (issue.labels || []).slice(0, 3).map(l =>
        `<span class="label-tag">${esc(l)}</span>`
      ).join('');

      const priorityClass = `priority-${issue.priority || 0}`;
      const proj = issue.project_id ? projects.find(p => p.id === issue.project_id) : null;
      const projBadge = proj ? `<span class="card-project">${esc(proj.name)}</span>` : '';
      const borderColor = PRIORITY_COLORS[issue.priority] || 'transparent';
      const highPriority = (issue.priority === 1 || issue.priority === 2) ? ' priority-high' : '';
      const delBtn = DELETABLE_STATES.includes(issue.state)
        ? `<button class="card-delete" onclick="event.stopPropagation(); deleteIssue('${issue.id}', '${esc(issue.identifier)}')" title="Delete">&#215;</button>`
        : '';

      // Age indicator (#23)
      var ageHtml = '';
      if (issue.created_at) {
        var days = Math.floor((Date.now() - new Date(issue.created_at).getTime()) / 86400000);
        if (days > 14) {
          ageHtml = '<span class="card-age stale">' + days + 'd</span>';
        } else if (days > 3) {
          ageHtml = '<span class="card-age">' + days + 'd</span>';
        }
      }

      return `
        <div class="card${highPriority}" draggable="true" data-id="${issue.id}"
             style="border-left-color: ${borderColor}"
             ondragstart="handleDragStart(event)"
             ondragend="handleDragEnd(event)"
             onclick="window.location.href='/board/issues/${issue.id}'">
          ${delBtn}
          <div class="card-identifier">${esc(issue.identifier)}</div>
          <div class="card-title">${esc(issue.title)}</div>
          <div class="card-meta">
            <span class="priority-dot ${priorityClass}"></span>
            ${projBadge}
            ${labels}
            ${ageHtml}
          </div>
        </div>
      `;
    }

    // --- Project Filter ---
    function populateProjectFilter() {
      const sel = document.getElementById('project-filter');
      const current = sel.value;
      sel.innerHTML = '<option value="">All Projects</option>';
      projects.forEach(p => {
        const opt = document.createElement('option');
        opt.value = p.id;
        opt.textContent = p.name;
        if (p.id === current) opt.selected = true;
        sel.appendChild(opt);
      });
    }

    function handleProjectFilter() {
      currentProjectFilter = document.getElementById('project-filter').value;
      renderBoard();
    }

    // --- Template Dropdown ---
    function populateTemplateMenu() {
      const menu = document.getElementById('template-menu');
      if (templates.length === 0) {
        menu.innerHTML = '<div style="padding:12px;color:var(--text-muted);font-size:0.82rem;text-align:center">No templates available</div>';
        return;
      }
      const priorityNames = { 1: 'Urgent', 2: 'High', 3: 'Medium', 4: 'Low' };
      menu.innerHTML = templates.map(t => {
        const descPreview = (t.description || '').replace(/^##?\s+.+\n*/m, '').replace(/\n/g, ' ').replace(/[-*[\]#]/g, '').trim().slice(0, 80);
        const labels = (t.labels || []).map(l => '<span class="tmpl-label">' + esc(l) + '</span>').join('');
        return '<button class="template-item" onclick="applyTemplate(templates.find(x=>x.id===\'' + t.id + '\'))">' +
          '<div class="tmpl-name">' + esc(t.name) + '</div>' +
          (descPreview ? '<div class="tmpl-desc">' + esc(descPreview) + '</div>' : '') +
          '<div class="tmpl-labels">' + labels +
            '<span class="tmpl-priority">P' + (t.priority || 0) + ' ' + (priorityNames[t.priority] || '') + '</span>' +
          '</div>' +
        '</button>';
      }).join('');
    }

    function toggleTemplateDropdown() {
      const menu = document.getElementById('template-menu');
      menu.classList.toggle('open');
    }

    function applyTemplate(tmpl) {
      document.getElementById('template-menu').classList.remove('open');
      openCreateModal();
      document.getElementById('form-title').value = tmpl.title || '';
      document.getElementById('form-description').value = tmpl.description || '';
      document.getElementById('form-priority').value = (tmpl.priority || 0).toString();
      document.getElementById('form-labels').value = (tmpl.labels || []).join(', ');
    }

    // Close dropdown when clicking outside
    document.addEventListener('click', (e) => {
      if (!e.target.closest('#template-dropdown')) {
        document.getElementById('template-menu').classList.remove('open');
      }
    });

    // --- Drag & Drop ---
    function handleDragStart(e) {
      draggedCard = e.target.closest('.card');
      draggedCard.classList.add('dragging');
      e.dataTransfer.effectAllowed = 'move';
      e.dataTransfer.setData('text/plain', draggedCard.dataset.id);
    }

    function handleDragEnd(e) {
      if (draggedCard) draggedCard.classList.remove('dragging');
      draggedCard = null;
      document.querySelectorAll('.column-body').forEach(el => el.classList.remove('drag-over'));
    }

    function handleDragOver(e) {
      e.preventDefault();
      e.dataTransfer.dropEffect = 'move';
      e.currentTarget.classList.add('drag-over');
    }

    function handleDragLeave(e) {
      e.currentTarget.classList.remove('drag-over');
    }

    async function handleDrop(e) {
      e.preventDefault();
      e.currentTarget.classList.remove('drag-over');

      const issueId = e.dataTransfer.getData('text/plain');
      const newState = e.currentTarget.dataset.state;

      if (!issueId || !newState) return;

      // Confirm high-consequence moves (#32)
      if (['Cancelled', 'Archived'].includes(newState)) {
        if (!confirm('Move issue to ' + newState + '?')) return;
      }

      try {
        await fetch(`${API}/issues/${issueId}/move`, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ state: newState })
        });
        await loadBoard();
      } catch (err) {
        console.error('Move failed:', err);
      }
    }

    // --- Quick Add ---
    async function handleQuickAdd(e) {
      if (e.key !== 'Enter') return;
      const input = e.target;
      const title = input.value.trim();
      if (!title) return;

      const state = input.dataset.state;
      input.value = '';

      const body = { title, state };
      if (currentProjectFilter) body.project_id = currentProjectFilter;

      try {
        await fetch(`${API}/issues`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(body)
        });
        await loadBoard();
      } catch (err) {
        console.error('Quick add failed:', err);
      }
    }

    // --- Create/Edit Modal ---
    function openCreateModal(defaultState) {
      document.getElementById('form-id').value = '';
      document.getElementById('form-title').value = '';
      document.getElementById('form-description').value = '';
      document.getElementById('form-priority').value = '0';
      document.getElementById('form-labels').value = '';
      document.getElementById('form-followups').checked = true;
      document.getElementById('modal-title').textContent = 'New Issue';
      document.getElementById('form-submit').textContent = 'Create Issue';

      populateStateSelect(defaultState || (boardData?.states?.[0]));
      populateProjectSelect(currentProjectFilter);

      document.getElementById('modal-overlay').classList.add('active');
      setTimeout(() => document.getElementById('form-title').focus(), 100);
    }

    function openEditModal(issue) {
      document.getElementById('form-id').value = issue.id;
      document.getElementById('form-title').value = issue.title || '';
      document.getElementById('form-description').value = issue.description || '';
      document.getElementById('form-priority').value = (issue.priority || 0).toString();
      document.getElementById('form-labels').value = (issue.labels || []).join(', ');
      document.getElementById('form-followups').checked = issue.propose_followups !== false;
      document.getElementById('modal-title').textContent = `Edit ${issue.identifier}`;
      document.getElementById('form-submit').textContent = 'Save Changes';

      populateStateSelect(issue.state);
      populateProjectSelect(issue.project_id || '');

      document.getElementById('modal-overlay').classList.add('active');
      setTimeout(() => document.getElementById('form-title').focus(), 100);
    }

    function populateStateSelect(selected) {
      const sel = document.getElementById('form-state');
      sel.innerHTML = '';
      (boardData?.states || []).forEach(s => {
        const opt = document.createElement('option');
        opt.value = s;
        opt.textContent = s;
        if (s === selected) opt.selected = true;
        sel.appendChild(opt);
      });
    }

    function populateProjectSelect(selected) {
      const sel = document.getElementById('form-project');
      sel.innerHTML = '<option value="">No project</option>';
      projects.forEach(p => {
        const opt = document.createElement('option');
        opt.value = p.id;
        opt.textContent = p.name;
        if (p.id === selected) opt.selected = true;
        sel.appendChild(opt);
      });
    }

    function closeModal() {
      document.getElementById('modal-overlay').classList.remove('active');
    }

    async function handleSubmit(e) {
      e.preventDefault();
      const id = document.getElementById('form-id').value;
      const data = {
        title: document.getElementById('form-title').value,
        description: document.getElementById('form-description').value,
        state: document.getElementById('form-state').value,
        priority: document.getElementById('form-priority').value,
        labels: document.getElementById('form-labels').value,
        project_id: document.getElementById('form-project').value || null,
        propose_followups: document.getElementById('form-followups').checked
      };

      try {
        if (id) {
          await fetch(`${API}/issues/${id}`, {
            method: 'PATCH',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
          });
        } else {
          await fetch(`${API}/issues`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
          });
        }
        closeModal();
        await loadBoard();
      } catch (err) {
        console.error('Submit failed:', err);
      }
    }

    // --- Detail Modal ---
    async function openDetail(issueId) {
      if (draggedCard) return;

      try {
        const res = await fetch(`${API}/issues/${issueId}`);
        if (!res.ok) return;
        const issue = await res.json();
        currentDetailIssue = issue;

        document.getElementById('detail-identifier').textContent = issue.identifier;
        document.getElementById('detail-title').textContent = issue.title;
        var stateEl = document.getElementById('detail-state');
        stateEl.textContent = issue.state;
        stateEl.className = 'badge ' + (BADGE_CLASSES[(issue.state || '').toLowerCase()] || 'badge-default');
        document.getElementById('detail-priority-dot').className =
          `priority-dot priority-${issue.priority || 0}`;
        document.getElementById('detail-priority-text').textContent =
          priorityLabel(issue.priority);
        document.getElementById('detail-description').textContent =
          issue.description || 'No description';
        document.getElementById('detail-labels').innerHTML =
          (issue.labels || []).map(l => `<span class="label-tag">${esc(l)}</span>`).join('');

        const proj = issue.project_id ? projects.find(p => p.id === issue.project_id) : null;
        const projHtml = proj ?
          `<span class="card-project" style="font-size: 0.8rem; padding: 2px 8px;">${esc(proj.name)}</span>` :
          '';
        document.getElementById('detail-labels').innerHTML += projHtml;

        document.getElementById('detail-created').textContent =
          issue.created_at ? `Created: ${formatDate(issue.created_at)}` : '';
        document.getElementById('detail-updated').textContent =
          issue.updated_at ? `Updated: ${formatDate(issue.updated_at)}` : '';

        document.getElementById('detail-overlay').classList.add('active');
      } catch (err) {
        console.error('Failed to load issue:', err);
      }
    }

    function closeDetailModal() {
      document.getElementById('detail-overlay').classList.remove('active');
      currentDetailIssue = null;
    }

    function editFromDetail() {
      if (!currentDetailIssue) return;
      closeDetailModal();
      openEditModal(currentDetailIssue);
    }

    async function deleteFromDetail() {
      if (!currentDetailIssue) return;
      if (!confirm(`Delete ${currentDetailIssue.identifier}?`)) return;

      try {
        await fetch(`${API}/issues/${currentDetailIssue.id}`, { method: 'DELETE' });
        closeDetailModal();
        await loadBoard();
      } catch (err) {
        console.error('Delete failed:', err);
      }
    }

    // --- Project Modal ---
    function openProjectModal() {
      document.getElementById('project-overlay').classList.add('active');
      document.getElementById('project-modal-title').textContent = 'Projects';
      document.getElementById('project-list-view').style.display = '';
      document.getElementById('project-form').style.display = 'none';
      document.getElementById('project-filter').value = '';
      renderProjectList();
    }

    function closeProjectModal() {
      document.getElementById('project-overlay').classList.remove('active');
    }

    function renderProjectList(filter) {
      const list = document.getElementById('project-list');
      if (projects.length === 0) {
        list.innerHTML = '<div class="project-empty">No projects yet. Create one to organize your issues.</div>';
        return;
      }
      const q = (filter || '').toLowerCase();
      const filtered = q ? projects.filter(p =>
        (p.name || '').toLowerCase().includes(q) ||
        (p.description || '').toLowerCase().includes(q) ||
        (p.path || '').toLowerCase().includes(q)
      ) : projects;

      if (filtered.length === 0) {
        list.innerHTML = `<div class="project-empty">No projects matching "${esc(filter)}"</div>`;
        return;
      }

      list.innerHTML = filtered.map(p => {
        const issueCount = boardData.columns.reduce((sum, col) =>
          sum + col.issues.filter(i => i.project_id === p.id).length, 0);
        const meta = [
          `${issueCount} issue${issueCount !== 1 ? 's' : ''}`,
          p.path ? `<span title="${esc(p.path)}">&#128193; ${esc(truncPath(p.path))}</span>` : '',
          p.repo_url ? `<span title="${esc(p.repo_url)}">&#128279;</span>` : ''
        ].filter(Boolean).join('');

        return `
          <div class="project-card">
            <div class="project-info">
              <h3 title="${esc(p.name)}">${esc(p.name)}</h3>
              ${p.description ? `<div class="project-desc" title="${esc(p.description)}">${esc(p.description)}</div>` : ''}
              <div class="project-meta">${meta}</div>
            </div>
            <div class="project-actions">
              ${p.repo_url && !p.path ? `<button class="btn btn-ghost btn-sm" onclick="cloneProject('${p.id}')">Clone</button>` : ''}
              <button class="btn btn-ghost btn-sm" onclick="editProject('${p.id}')">Edit</button>
              <button class="btn btn-danger btn-sm" onclick="deleteProject('${p.id}')">Del</button>
            </div>
          </div>
        `;
      }).join('');
    }

    function filterProjects(q) {
      renderProjectList(q);
    }

    function truncPath(p) {
      return p.length > 40 ? '...' + p.slice(-37) : p;
    }

    function showProjectForm(project) {
      document.getElementById('project-list-view').style.display = 'none';
      document.getElementById('project-form').style.display = '';
      if (project) {
        document.getElementById('proj-id').value = project.id;
        document.getElementById('proj-name').value = project.name || '';
        document.getElementById('proj-description').value = project.description || '';
        document.getElementById('proj-path').value = project.path || '';
        document.getElementById('proj-repo').value = project.repo_url || '';
        document.getElementById('proj-submit').textContent = 'Save Changes';
        document.getElementById('project-modal-title').textContent = `Edit: ${project.name}`;
      } else {
        document.getElementById('proj-id').value = '';
        document.getElementById('proj-name').value = '';
        document.getElementById('proj-description').value = '';
        document.getElementById('proj-path').value = '';
        document.getElementById('proj-repo').value = '';
        document.getElementById('proj-submit').textContent = 'Create Project';
        document.getElementById('project-modal-title').textContent = 'New Project';
      }
    }

    function hideProjectForm() {
      document.getElementById('project-form').style.display = 'none';
      document.getElementById('project-list-view').style.display = '';
      document.getElementById('project-modal-title').textContent = 'Projects';
    }

    async function handleProjectSubmit(e) {
      e.preventDefault();
      const id = document.getElementById('proj-id').value;
      const data = {
        name: document.getElementById('proj-name').value,
        description: document.getElementById('proj-description').value,
        path: document.getElementById('proj-path').value || null,
        repo_url: document.getElementById('proj-repo').value || null
      };

      try {
        if (id) {
          await fetch(`${API}/projects/${id}`, {
            method: 'PATCH',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
          });
        } else {
          await fetch(`${API}/projects`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
          });
        }
        await loadBoard();
        hideProjectForm();
        renderProjectList();
      } catch (err) {
        console.error('Project submit failed:', err);
      }
    }

    function editProject(id) {
      const proj = projects.find(p => p.id === id);
      if (proj) showProjectForm(proj);
    }

    async function deleteProject(id) {
      const proj = projects.find(p => p.id === id);
      if (!confirm(`Delete project "${proj?.name}" and ALL its issues? This cannot be undone.`)) return;
      try {
        await fetch(`${API}/projects/${id}`, { method: 'DELETE' });
        await loadBoard();
        renderProjectList();
      } catch (err) {
        console.error('Delete project failed:', err);
      }
    }

    async function cloneProject(id) {
      const proj = projects.find(p => p.id === id);
      if (!confirm(`Clone repository for "${proj?.name}"?\n${proj?.repo_url}`)) return;

      try {
        const res = await fetch(`${API}/projects/${id}/clone`, { method: 'POST' });
        const data = await res.json();
        if (res.ok) {
          alert(`Repository cloned to:\n${data.path}`);
          await loadBoard();
          renderProjectList();
        } else {
          alert(`Clone failed: ${data.error}\n${data.detail || ''}`);
        }
      } catch (err) {
        console.error('Clone failed:', err);
        alert('Clone request failed. Check console for details.');
      }
    }

    // --- Issue Deletion with undo toast (#25) ---
    async function deleteIssue(id, identifier) {
      // Find the issue data first for potential undo
      var issueData = null;
      if (boardData) {
        boardData.columns.forEach(function(col) {
          col.issues.forEach(function(i) { if (i.id === id) issueData = i; });
        });
      }
      try {
        await fetch(`${API}/issues/${id}`, { method: 'DELETE' });
        await loadBoard();
        showToast('Deleted ' + identifier, {
          type: 'success',
          undo: issueData ? function() {
            fetch(`${API}/issues`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ title: issueData.title, state: issueData.state, priority: issueData.priority, labels: issueData.labels, description: issueData.description, project_id: issueData.project_id })
            }).then(function() { loadBoard(); });
          } : null
        });
      } catch (err) {
        console.error('Delete failed:', err);
      }
    }

    async function clearColumn(state) {
      const colIssues = boardData.columns.find(c => c.state === state)?.issues || [];
      if (colIssues.length === 0) return;
      if (!confirm(`Delete all ${colIssues.length} issue${colIssues.length !== 1 ? 's' : ''} in "${state}"? This cannot be undone.`)) return;
      try {
        await Promise.all(colIssues.map(i => fetch(`${API}/issues/${i.id}`, { method: 'DELETE' })));
        await loadBoard();
      } catch (err) {
        console.error('Clear column failed:', err);
      }
    }

    // --- Directory Scanning ---
    let scannedCandidates = [];

    function showScanView() {
      document.getElementById('project-list-view').style.display = 'none';
      document.getElementById('project-form').style.display = 'none';
      document.getElementById('scan-view').style.display = '';
      document.getElementById('project-modal-title').textContent = 'Import from Directory';
      document.getElementById('scan-results').innerHTML = '';
      document.getElementById('import-btn').style.display = 'none';
      scannedCandidates = [];
    }

    function hideScanView() {
      document.getElementById('scan-view').style.display = 'none';
      document.getElementById('project-list-view').style.display = '';
      document.getElementById('project-modal-title').textContent = 'Projects';
    }

    async function scanDirectory() {
      const rootPath = document.getElementById('scan-root-path').value.trim();
      if (!rootPath) return;
      const btn = document.getElementById('scan-btn');
      const results = document.getElementById('scan-results');
      btn.disabled = true;
      btn.textContent = 'Scanning...';
      results.innerHTML = '<div style="color: var(--text-muted);">Scanning directories...</div>';

      try {
        const res = await fetch(`${API}/projects/scan`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            root_path: rootPath,
            git_pull: document.getElementById('scan-git-pull').checked,
            recursive: document.getElementById('scan-recursive').checked
          })
        });
        const data = await res.json();
        if (!res.ok) {
          results.innerHTML = `<div style="color: var(--red);">Error: ${data.error}${data.detail ? ' — ' + data.detail : ''}</div>`;
          return;
        }
        scannedCandidates = data.candidates || [];
        // Filter out directories that are already projects (by path)
        const existingPaths = new Set(projects.map(p => p.path).filter(Boolean));
        scannedCandidates.forEach(c => { c._selected = !existingPaths.has(c.path); c._existing = existingPaths.has(c.path); });
        renderScanResults();
      } catch (err) {
        results.innerHTML = `<div style="color: var(--red);">Scan failed: ${err.message}</div>`;
      } finally {
        btn.disabled = false;
        btn.textContent = 'Scan';
      }
    }

    function renderScanResults() {
      const results = document.getElementById('scan-results');
      if (scannedCandidates.length === 0) {
        results.innerHTML = '<div style="color: var(--text-muted);">No subdirectories found.</div>';
        document.getElementById('import-btn').style.display = 'none';
        return;
      }
      const selectable = scannedCandidates.filter(c => !c._existing);
      const selectedCount = scannedCandidates.filter(c => c._selected).length;

      results.innerHTML = `
        <div style="margin-bottom: 8px; display: flex; justify-content: space-between; align-items: center;">
          <span style="font-size: 0.85rem; color: var(--text-secondary);">Found ${scannedCandidates.length} directories (${selectedCount} selected)</span>
          ${selectable.length > 0 ? `<label style="font-size: 0.8rem; color: var(--text-muted); cursor: pointer;"><input type="checkbox" ${selectedCount === selectable.length ? 'checked' : ''} onchange="toggleAllScan(this.checked)"> Select all</label>` : ''}
        </div>
        <div class="scan-list">${scannedCandidates.map((c, i) => renderScanCard(c, i)).join('')}</div>
      `;
      document.getElementById('import-btn').style.display = selectedCount > 0 ? '' : 'none';
      document.getElementById('import-btn').textContent = `Import ${selectedCount} Project${selectedCount !== 1 ? 's' : ''}`;
    }

    function renderScanCard(c, idx) {
      const disabled = c._existing;
      const checked = c._selected ? 'checked' : '';
      const opacity = disabled ? 'opacity: 0.5;' : '';
      const badge = disabled ? '<span style="font-size: 0.7rem; background: var(--bg-tertiary); color: var(--text-muted); padding: 2px 6px; border-radius: 4px; margin-left: 8px;">already imported</span>' : '';
      const repo = c.repo_url ? `<span style="font-size: 0.75rem; color: var(--text-muted);">&#128279; ${esc(c.repo_url)}</span>` : '';

      return `
        <div class="scan-card" style="${opacity}">
          <div style="display: flex; align-items: flex-start; gap: 10px;">
            <input type="checkbox" ${checked} ${disabled ? 'disabled' : ''} onchange="toggleScanItem(${idx}, this.checked)" style="margin-top: 4px;">
            <div style="flex: 1; min-width: 0;">
              <div style="display: flex; align-items: center; gap: 6px; flex-wrap: wrap;">
                <strong style="font-size: 0.9rem;">${esc(c.name)}</strong>
                ${badge}
              </div>
              ${c.description ? `<div style="font-size: 0.8rem; color: var(--text-secondary); margin-top: 2px;">${esc(c.description)}</div>` : ''}
              <div style="font-size: 0.75rem; color: var(--text-muted); margin-top: 4px;">
                <span>&#128193; ${esc(c.path)}</span>
                ${repo}
              </div>
            </div>
          </div>
        </div>
      `;
    }

    function toggleScanItem(idx, checked) {
      scannedCandidates[idx]._selected = checked;
      renderScanResults();
    }

    function toggleAllScan(checked) {
      scannedCandidates.forEach(c => { if (!c._existing) c._selected = checked; });
      renderScanResults();
    }

    async function importScannedProjects() {
      const toImport = scannedCandidates
        .filter(c => c._selected && !c._existing)
        .map(c => ({ name: c.name, slug: c.slug, path: c.path, description: c.description, repo_url: c.repo_url }));
      if (toImport.length === 0) return;

      const btn = document.getElementById('import-btn');
      btn.disabled = true;
      btn.textContent = 'Importing...';

      try {
        const res = await fetch(`${API}/projects/import`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ projects: toImport })
        });
        const data = await res.json();
        if (res.ok) {
          await loadBoard();
          hideScanView();
          renderProjectList();
        } else {
          alert(`Import failed: ${data.error || 'Unknown error'}`);
        }
      } catch (err) {
        alert(`Import failed: ${err.message}`);
      } finally {
        btn.disabled = false;
        btn.textContent = `Import ${toImport.length} Projects`;
      }
    }

    // --- Helpers ---
    function showToast(msg, opts) {
      opts = opts || {};
      var container = document.getElementById('toast-container');
      if (!container) { container = document.createElement('div'); container.id = 'toast-container'; container.className = 'toast-container'; document.body.appendChild(container); }
      var toast = document.createElement('div');
      toast.className = 'toast ' + (opts.type || '');
      toast.innerHTML = '<span>' + esc(msg) + '</span>';
      container.appendChild(toast);
      setTimeout(function() { toast.remove(); }, opts.duration || 4000);
    }

    function esc(str) {
      if (!str) return '';
      const d = document.createElement('div');
      d.textContent = str;
      return d.innerHTML;
    }

    function priorityLabel(p) {
      return { 1: 'Urgent', 2: 'High', 3: 'Medium', 4: 'Low' }[p] || 'None';
    }

    function formatDate(iso) {
      try {
        return new Date(iso).toLocaleString();
      } catch { return iso; }
    }

    // --- Auto Add & Board settings ---
    async function loadAutoAddSettings() {
      try {
        const res = await fetch(`${API}/settings/auto-add`);
        const data = await res.json();
        var autoEnabled = data.auto_add_enabled === 'true';
        document.getElementById('auto-add-toggle').checked = autoEnabled;
        document.getElementById('max-todo-select').value = data.max_todo_parallel || '3';
        segregateByProject = data.segregate_by_project === 'true';
        document.getElementById('segregate-toggle').checked = segregateByProject;
        // Update auto-add label indicator
        document.getElementById('auto-add-label').textContent = autoEnabled ? 'Auto: On' : 'Auto';
        if (boardData) renderBoard();
      } catch (e) {
        console.error('Failed to load auto-add settings:', e);
      }
    }

    async function handleAutoAddToggle() {
      const enabled = document.getElementById('auto-add-toggle').checked;
      await fetch(`${API}/settings/auto-add`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ auto_add_enabled: enabled ? 'true' : 'false' })
      });
    }

    async function handleMaxTodoChange() {
      const val = document.getElementById('max-todo-select').value;
      await fetch(`${API}/settings/auto-add`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ max_todo_parallel: val })
      });
    }

    async function handleSegregateToggle() {
      segregateByProject = document.getElementById('segregate-toggle').checked;
      await fetch(`${API}/settings/auto-add`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ segregate_by_project: segregateByProject ? 'true' : 'false' })
      });
      renderBoard();
    }

    // --- Keyboard card navigation (#24) ---
    var kbFocusedIdx = -1;

    function getVisibleCards() {
      return Array.from(document.querySelectorAll('.card[data-id]'));
    }

    function setCardFocus(idx) {
      var cards = getVisibleCards();
      if (cards.length === 0) return;
      // Remove old focus
      cards.forEach(function(c) { c.classList.remove('kb-focused'); });
      kbFocusedIdx = Math.max(0, Math.min(idx, cards.length - 1));
      var card = cards[kbFocusedIdx];
      card.classList.add('kb-focused');
      card.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    }

    function clearCardFocus() {
      kbFocusedIdx = -1;
      document.querySelectorAll('.card.kb-focused').forEach(function(c) { c.classList.remove('kb-focused'); });
    }

    document.addEventListener('keydown', (e) => {
      var inInput = ['INPUT','TEXTAREA','SELECT'].includes(document.activeElement.tagName);
      if (e.key === 'Escape') {
        clearCardFocus();
        closeModal();
        closeDetailModal();
        closeProjectModal();
      }
      if (inInput) return;
      // j/k or ArrowDown/ArrowUp = navigate cards
      if (e.key === 'j' || e.key === 'ArrowDown') {
        e.preventDefault();
        setCardFocus(kbFocusedIdx + 1);
        return;
      }
      if (e.key === 'k' || e.key === 'ArrowUp') {
        e.preventDefault();
        setCardFocus(kbFocusedIdx <= 0 ? 0 : kbFocusedIdx - 1);
        return;
      }
      // Enter = open focused card
      if (e.key === 'Enter' && kbFocusedIdx >= 0) {
        var cards = getVisibleCards();
        if (cards[kbFocusedIdx]) {
          var id = cards[kbFocusedIdx].dataset.id;
          window.location.href = '/board/issues/' + id;
        }
        return;
      }
      if (e.key === 'n' && !e.ctrlKey && !e.metaKey) {
        e.preventDefault();
        openCreateModal();
      }
      if (e.key === 'p' && !e.ctrlKey && !e.metaKey) {
        e.preventDefault();
        window.location.href = '/board/projects';
      }
      // r = refresh
      if (e.key === 'r' && !e.ctrlKey && !e.metaKey) {
        e.preventDefault();
        loadBoard();
      }
      // ? = show keyboard help
      if (e.key === '?') {
        showToast('j/k=Navigate  Enter=Open  n=New  p=Projects  r=Refresh  Esc=Close', { duration: 3000 });
      }
    });

    // --- Init ---
    loadBoard();
    loadAutoAddSettings();
    // Auto-refresh every 30 seconds (#30)
    setInterval(loadBoard, 30000);
    """
  end
end

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
    alias SymphonyElixir.Server.UIHelpers

    body = """
      <div class="page-actions-bar">
        <div class="page-actions-left">
          <h2 class="page-title">Kanban Board</h2>
          <select id="project-filter" class="project-select" onchange="handleProjectFilter()">
            <option value="">All Projects</option>
          </select>
        </div>
        <div class="page-actions-right">
          <div class="dropdown" id="auto-add-dropdown">
            <button class="btn btn-ghost" onclick="toggleAutoAddDropdown()">
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
          <button class="btn btn-primary" onclick="openCreateModal()">
            <svg viewBox="0 0 24 24" width="14" height="14" fill="none"
              stroke="currentColor" stroke-width="2">
              <line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/>
            </svg>
            New Issue
          </button>
        </div>
      </div>
    
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
            <div class="form-group">
              <label>Skills <span class="form-hint">(select skills to inject into agent prompt)</span></label>
              <div class="form-skill-pills" id="form-skill-pills"></div>
              <select id="form-add-skill" onchange="formAddSkill(this.value); this.value='';">
                <option value="">+ Add skill or group...</option>
              </select>
            </div>
            <div class="form-group form-checkbox">
              <label>
                <input type="checkbox" id="form-followups" checked>
                Propose follow-up issues
              </label>
            </div>
            <div class="form-group form-checkbox">
              <label>
                <input type="checkbox" id="form-plan-first">
                Plan first (agent plans before implementing)
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
    
      <script>
    #{UIHelpers.esc_js()}
    #{UIHelpers.toast_js()}
    #{UIHelpers.color_maps_js()}
    #{UIHelpers.kanban_drag_drop_js()}
    #{javascript()}
      </script>
    """

    UIHelpers.page_template("Symphony Board", "kanban", css(), body)
  end

  defp css do
    alias SymphonyElixir.Server.UIHelpers

    UIHelpers.form_css() <>
      UIHelpers.modal_css() <>
      UIHelpers.skeleton_css() <>
      UIHelpers.page_actions_css() <>
      UIHelpers.dropdown_css() <>
      ~S"""
      
      body {
        height: 100vh;
        display: flex;
        flex-direction: column;
        overflow: hidden;
      }
      .page-actions-bar { padding: 8px 20px; }
      
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
      .project-group-header .pg-dot {
        width: 8px; height: 8px; border-radius: 50%; background: var(--accent); flex-shrink: 0; }
      
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
      .column-dot { width: 8px; height: 8px; border-radius: 50%;
        background: var(--column-accent, var(--text-muted)); flex-shrink: 0; }
      .column-title { font-size: 0.75rem; font-weight: 600; color: var(--text-secondary);
        text-transform: uppercase; letter-spacing: 0.04em; }
      .column-count {
        font-size: 0.72rem; color: var(--text-primary); font-weight: 600;
        background: var(--bg-tertiary); padding: 1px 7px; border-radius: 10px;
        min-width: 20px; text-align: center;
      }
      /* Column completion bar (#33) */
      .column-progress { height: 2px; background: var(--bg-tertiary);
        border-radius: 1px; margin-top: 4px; overflow: hidden; }
      .column-progress-fill { height: 100%; border-radius: 1px; transition: width 0.3s ease; }
      /* WIP limit (#34) */
      .wip-badge { font-size: 0.65rem; color: var(--text-muted);
        padding: 1px 5px; border-radius: 8px; background: var(--bg-tertiary); }
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
      .card-skills { font-size: 0.6rem; color: var(--purple);
        background: rgba(188,140,255,0.1); padding: 1px 5px; border-radius: 6px; }
      .card-plan-badge { font-size: 0.6rem; padding: 1px 5px; border-radius: 6px; }
      .card-plan-badge.planning { color: var(--orange); background: rgba(255,180,50,0.12); }
      .card-plan-badge.review { color: var(--blue); background: rgba(88,166,255,0.15); font-weight: 600; }
      .card-plan-badge.approved { color: var(--green); background: rgba(63,185,80,0.12); }
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
      .detail-description { font-size: 0.9rem; color: var(--text-secondary);
        line-height: 1.6; margin-bottom: 16px; white-space: pre-wrap; }
      .detail-labels { display: flex; gap: 6px; flex-wrap: wrap; margin-bottom: 12px; }
      .detail-timestamps { display: flex; gap: 16px; color: var(--text-muted); font-size: 0.75rem; }
      
      /* --- Form overrides for board --- */
      .form-checkbox label { display: flex; align-items: center; gap: 8px;
        cursor: pointer; font-size: 13px; color: var(--text-secondary); }
      .form-checkbox input[type="checkbox"] {
        width: 16px; height: 16px; accent-color: var(--purple); cursor: pointer; }
      .form-hint { font-size: 0.7rem; color: var(--text-muted); font-weight: 400; }
      .form-skill-pills { display: flex; flex-wrap: wrap; gap: 4px; margin-bottom: 6px; min-height: 24px; }
      .form-skill-pill {
        display: inline-flex; align-items: center; gap: 3px;
        padding: 2px 8px; border-radius: 10px; font-size: 0.7rem; font-weight: 500;
        background: rgba(188,140,255,0.12); color: var(--purple); border: 1px solid rgba(188,140,255,0.25);
      }
      .form-skill-pill.group { background: rgba(88,166,255,0.12);
        color: var(--accent); border-color: rgba(88,166,255,0.25); }
      .form-skill-pill button {
        background: none; border: none; color: inherit; cursor: pointer;
        font-size: 0.8rem; padding: 0 2px; opacity: 0.6; line-height: 1;
      }
      .form-skill-pill button:hover { opacity: 1; }
      
      /* --- Empty State --- */
      .empty-column {
        display: flex; flex-direction: column; align-items: center; justify-content: center;
        padding: 24px 12px; color: var(--text-muted); font-size: 0.78rem; min-height: 80px;
      }
      .empty-column-icon { width: 28px; height: 28px; margin-bottom: 6px; opacity: 0.3; }
      
      /* --- Quick Add (#26) --- */
      .quick-add { padding: 4px 6px 6px; border-top: 1px solid var(--border-light);
        flex-shrink: 0; background: var(--bg-secondary); }
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
      
      /* --- Project List --- */
      .project-filter { width: 100%; padding: 6px 10px; margin-bottom: 8px;
        border: 1px solid var(--border); border-radius: var(--radius-sm);
        background: var(--bg-primary); color: var(--text-primary); font-size: 0.85rem; }
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
      .project-info h3 { font-size: 0.85rem; font-weight: 600; margin: 0;
        white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
      .project-info .project-desc { font-size: 0.75rem; color: var(--text-secondary);
        margin-top: 1px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
      .project-info .project-meta { font-size: 0.75rem; color: var(--text-muted);
        display: flex; gap: 8px; margin-top: 1px; }
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
        .column { min-width: 100%; max-width: 100%; border-right: none;
          border-bottom: 1px solid var(--border-light); height: auto; }
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
    let _apiLock = false;
    let boardData = null;
    let projects = [];
    let currentDetailIssue = null;
    let draggedCard = null;
    let currentProjectFilter = '';
    let segregateByProject = false;
    
    // Configure shared kanban drag-drop helpers
    window._kanbanOpts = {
      cardSelector: '.card',
      bodySelector: '.column-body',
      getQuickAddExtras: function() {
        var extras = {};
        if (currentProjectFilter) extras.project_id = currentProjectFilter;
        return extras;
      }
    };
    _kCardSel = '.card';
    _kBodySel = '.column-body';
    async function kanbanAfterMutation() { await loadBoard(); }
    let loadPending = false;
    let lastLoadTime = 0;
    let allSkillsCache = [];
    let allGroupsCache = [];
    let formSkillIds = [];
    let formGroupIds = [];
    
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
          Array(5).fill(
            '<div style="flex:1;padding:8px;"><div class="skeleton skeleton-text"></div>' +
            '<div class="skeleton skeleton-card"></div>' +
            '<div class="skeleton skeleton-card"></div></div>'
          ).join('') + '</div>';
      }
    
      try {
        // Preserve scroll positions (#31)
        var scrollPositions = {};
        document.querySelectorAll('.column-body').forEach(function(el) {
          if (el.scrollTop > 0) scrollPositions[el.dataset.state] = el.scrollTop;
        });
    
        const [snapRes, projRes] = await Promise.all([
          fetch(`${API}/snapshot`),
          fetch(`${API}/projects`)
        ]);
        boardData = await snapRes.json();
        const projData = await projRes.json();
        projects = projData.projects || [];
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
    
    const BADGE_CLASSES = {
      'backlog': 'badge-backlog', 'todo': 'badge-todo',
      'in progress': 'badge-in-progress', 'review': 'badge-review',
      'done': 'badge-done', 'cancelled': 'badge-cancelled',
      'archived': 'badge-archived'
    };
    
    // Terminal columns: default collapsed (#17)
    const TERMINAL_STATES = ['Done', 'Archived', 'Cancelled'];
    
    function getColumnColor(state) { return stateColor(state); }
    
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
        '<span class="metric"><span class="metric-dot" style="background:var(--accent)"></span>' +
        '<span class="metric-val">' + active + '</span> active</span>' +
        '<span class="metric"><span class="metric-dot" style="background:var(--yellow)"></span>' +
        '<span class="metric-val">' + todo + '</span> todo</span>' +
        '<span class="metric"><span class="metric-dot" style="background:var(--green)"></span>' +
        '<span class="metric-val">' + done + '</span> done</span>' +
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
        var progressHtml = !isCollapsed
          ? '<div class="column-progress"><div class="column-progress-fill" style="width:' +
            pctFill + '%;background:' + color + '"></div></div>'
          : '';
    
        column.innerHTML = `
          <div class="column-header">
            <div class="column-title-group">
              <span class="column-dot"></span>
              <span class="column-title">${esc(col.state)}</span>
              <span class="column-count">${issues.length}</span>
            </div>
            ${!isCollapsed && issues.length > 0 && ['Backlog','Cancelled','Archived'].includes(col.state)
              ? `<button class="btn-clear-col"
                onclick="event.stopPropagation(); clearColumn('${esc(col.state)}')"
                title="Delete all ${esc(col.state)} issues">
              <svg viewBox="0 0 24 24" width="12" height="12" fill="none"
                stroke="currentColor" stroke-width="2">
                <polyline points="3 6 5 6 21 6"/>
                <path d="M19 6v14a2 2 0 01-2 2H7a2 2 0 01-2-2V6m3 0V4a2 2 0 012-2h4a2 2 0 012 2v2"/>
              </svg>
            </button>` : ''}
            ${!isCollapsed
              ? `<button class="btn-collapse"
                onclick="event.stopPropagation(); toggleColumn('${esc(col.state)}')"
                title="Collapse column">
              <svg viewBox="0 0 24 24" width="14" height="14" fill="none"
                stroke="currentColor" stroke-width="2">
                <polyline points="15 18 9 12 15 6"/>
              </svg>
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
                <svg class="empty-column-icon" viewBox="0 0 24 24"
                  fill="none" stroke="currentColor" stroke-width="1.5">
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
          html += `<div class="project-group-header">` +
            `<span class="pg-dot"></span>${esc(name)} ` +
            `<span style="opacity:0.5;margin-left:auto">${groups[pid].length}</span></div>`;
        }
        html += groups[pid].map(renderCard).join('');
      });
      return html;
    }
    
    
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
        ? `<button class="card-delete"
          onclick="event.stopPropagation(); deleteIssue('${issue.id}', '${esc(issue.identifier)}')"
          title="Delete">&#215;</button>`
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
    
      // Skills indicator
      var skillCount = (issue.skill_ids || []).length + (issue.skill_group_ids || []).length;
      var skillBadge = skillCount > 0
        ? '<span class="card-skills" title="' + skillCount + ' skill(s) assigned">&#9889; ' + skillCount + '</span>'
        : '';
    
      // Plan status badge
      var planBadge = '';
      if (issue.plan_status === 'planning')
        planBadge = '<span class="card-plan-badge planning" title="Planning phase">&#128203; Planning</span>';
      else if (issue.plan_status === 'plan_review')
        planBadge = '<span class="card-plan-badge review" title="Plan awaiting review">&#128203; Plan Ready</span>';
      else if (issue.plan_status === 'approved')
        planBadge = '<span class="card-plan-badge approved"' +
          ' title="Plan approved, executing">&#128203; Executing</span>';
    
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
            ${skillBadge}
            ${planBadge}
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
    
    // Drag & Drop and Quick Add — provided by shared kanban_drag_drop_js()
    
    // --- Create/Edit Modal ---
    function openCreateModal(defaultState) {
      document.getElementById('form-id').value = '';
      document.getElementById('form-title').value = '';
      document.getElementById('form-description').value = '';
      document.getElementById('form-priority').value = '0';
      document.getElementById('form-labels').value = '';
      document.getElementById('form-followups').checked = true;
      document.getElementById('form-plan-first').checked = false;
      document.getElementById('modal-title').textContent = 'New Issue';
      document.getElementById('form-submit').textContent = 'Create Issue';
    
      formSkillIds = [];
      formGroupIds = [];
      renderFormSkillPills();
    
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
      document.getElementById('form-plan-first').checked =
        issue.plan_status === 'planning' || issue.plan_status === 'plan_review';
      document.getElementById('modal-title').textContent = `Edit ${issue.identifier}`;
      document.getElementById('form-submit').textContent = 'Save Changes';
    
      formSkillIds = (issue.skill_ids || []).slice();
      formGroupIds = (issue.skill_group_ids || []).slice();
      renderFormSkillPills();
    
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
    
    // --- Skills in Create/Edit form ---
    async function loadSkillsCache() {
      try {
        var [sr, gr] = await Promise.all([
          fetch(API + '/skills'), fetch(API + '/skill-groups')
        ]);
        if (sr.ok) { var d = await sr.json(); allSkillsCache = d.skills || []; }
        if (gr.ok) { var d = await gr.json(); allGroupsCache = d.skill_groups || []; }
      } catch(e) {}
    }
    
    function populateFormSkillSelect() {
      var sel = document.getElementById('form-add-skill');
      sel.innerHTML = '<option value="">+ Add skill or group...</option>';
      var optSkills = document.createElement('optgroup');
      optSkills.label = 'Skills';
      allSkillsCache.forEach(function(s) {
        if (formSkillIds.indexOf(s.id) === -1) {
          var opt = document.createElement('option');
          opt.value = 'skill:' + s.id;
          opt.textContent = '[' + s.category + '] ' + s.name;
          optSkills.appendChild(opt);
        }
      });
      sel.appendChild(optSkills);
      var optGroups = document.createElement('optgroup');
      optGroups.label = 'Groups';
      allGroupsCache.forEach(function(g) {
        if (formGroupIds.indexOf(g.id) === -1) {
          var opt = document.createElement('option');
          opt.value = 'group:' + g.id;
          opt.textContent = g.name + ' (' + (g.skill_ids || []).length + ' skills)';
          optGroups.appendChild(opt);
        }
      });
      sel.appendChild(optGroups);
    }
    
    function renderFormSkillPills() {
      var container = document.getElementById('form-skill-pills');
      var pills = [];
      formSkillIds.forEach(function(sid) {
        var s = allSkillsCache.find(function(sk) { return sk.id === sid; });
        if (s) pills.push('<span class="form-skill-pill">' + esc(s.name) +
          '<button type="button" onclick="formRemoveSkill(\'' + sid + '\')">&times;</button></span>');
      });
      formGroupIds.forEach(function(gid) {
        var g = allGroupsCache.find(function(gr) { return gr.id === gid; });
        if (g) pills.push('<span class="form-skill-pill group">' + esc(g.name) +
          '<button type="button" onclick="formRemoveGroup(\'' + gid + '\')">&times;</button></span>');
      });
      container.innerHTML = pills.join('');
      populateFormSkillSelect();
    }
    
    function formAddSkill(val) {
      if (!val) return;
      if (val.startsWith('skill:')) {
        var id = val.substring(6);
        if (formSkillIds.indexOf(id) === -1) formSkillIds.push(id);
      } else if (val.startsWith('group:')) {
        var id = val.substring(6);
        if (formGroupIds.indexOf(id) === -1) formGroupIds.push(id);
      }
      renderFormSkillPills();
    }
    
    function formRemoveSkill(sid) {
      formSkillIds = formSkillIds.filter(function(id) { return id !== sid; });
      renderFormSkillPills();
    }
    
    function formRemoveGroup(gid) {
      formGroupIds = formGroupIds.filter(function(id) { return id !== gid; });
      renderFormSkillPills();
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
        propose_followups: document.getElementById('form-followups').checked,
        plan_status: document.getElementById('form-plan-first').checked ? 'planning' : null,
        skill_ids: formSkillIds,
        skill_group_ids: formGroupIds
      };
    
      try {
        var res;
        if (id) {
          res = await fetch(`${API}/issues/${id}`, {
            method: 'PATCH',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
          });
        } else {
          res = await fetch(`${API}/issues`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
          });
        }
        if (!res.ok) {
          const errData = await res.json().catch(() => ({}));
          showToast('Save failed: ' + esc(errData.error || 'unknown error'), { type: 'error' });
          return;
        }
        closeModal();
        await loadBoard();
      } catch (err) {
        console.error('Submit failed:', err);
        showToast('Save failed: ' + esc(err.message || 'network error'), { type: 'error' });
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
              body: JSON.stringify({
                title: issueData.title, state: issueData.state,
                priority: issueData.priority, labels: issueData.labels,
                description: issueData.description, project_id: issueData.project_id
              })
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
      if (!confirm(`Delete all ${colIssues.length} issue${colIssues.length !== 1 ? 's' : ''}` +
        ` in "${state}"? This cannot be undone.`)) return;
      try {
        await Promise.all(colIssues.map(i => fetch(`${API}/issues/${i.id}`, { method: 'DELETE' })));
        await loadBoard();
      } catch (err) {
        console.error('Clear column failed:', err);
      }
    }
    
    // --- Helpers ---
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
    loadSkillsCache();
    // Auto-refresh every 30 seconds (#30)
    setInterval(loadBoard, 30000);
    """
  end
end

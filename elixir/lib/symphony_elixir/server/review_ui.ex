defmodule SymphonyElixir.Server.ReviewUI do
  @moduledoc """
  Cross-project feature completeness review matrix.

  Visualizes products (products spanning multiple projects) as an
  interactive matrix: features as rows, projects as columns, with
  colour-coded status cells. Includes AI-assisted gap detection that
  creates follow-up issues on the board.
  """

  @doc "Render the review matrix HTML page."
  @spec render() :: String.t()
  def render do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Symphony Review</title>
      <style>
    #{css()}
      </style>
    </head>
    <body>
      <header class="topbar">
        <div class="topbar-left">
          <nav class="breadcrumb"><a href="/board">Board</a><span class="sep">/</span></nav>
          <h1>Product Review</h1>
          <select id="product-select" class="prod-select" onchange="selectProduct()">
            <option value="">Select product...</option>
          </select>
        </div>
        <div class="topbar-right">
          <button class="btn btn-ghost" onclick="openNewProductModal()">+ New Product</button>
          <button class="btn btn-accent" id="analyze-btn" onclick="analyzeGaps()" style="display:none">
            <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2"><path d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z"/></svg>
            Analyze Gaps
          </button>
          <div class="legend">
            <span class="legend-item"><span class="status-dot status-done"></span> Done</span>
            <span class="legend-item"><span class="status-dot status-in_progress"></span> In Progress</span>
            <span class="legend-item"><span class="status-dot status-planned"></span> Planned</span>
            <span class="legend-item"><span class="status-dot status-missing"></span> Missing</span>
            <span class="legend-item"><span class="status-dot status-n_a"></span> N/A</span>
          </div>
        </div>
      </header>

      <main class="main" id="main">
        <div class="empty-state" id="empty-state">
          <div class="empty-icon">
            <svg viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/></svg>
          </div>
          <h2>Cross-Project Review</h2>
          <p>Create a product to group projects and track feature completeness across them.</p>
          <button class="btn btn-primary" onclick="openNewProductModal()">Create Product</button>
        </div>

        <div class="matrix-container" id="matrix-container" style="display:none">
          <div class="matrix-header" id="matrix-header"></div>
          <div class="matrix-body" id="matrix-body"></div>
          <div class="matrix-footer" id="matrix-footer"></div>
        </div>
      </main>

      <!-- New Product Modal -->
      <div class="modal-overlay" id="prod-modal" style="display:none">
        <div class="modal">
          <div class="modal-header">
            <h2 id="prod-modal-title">New Product</h2>
            <button class="modal-close" onclick="closeProdModal()">&times;</button>
          </div>
          <div class="modal-body">
            <input type="hidden" id="prod-edit-id">
            <label>Name<input type="text" id="prod-name" placeholder="e.g. B2C Async API"></label>
            <label>Description<textarea id="prod-desc" placeholder="What does this product cover?"></textarea></label>
            <label>Projects</label>
            <div class="project-checklist" id="project-checklist"></div>
          </div>
          <div class="modal-footer">
            <button class="btn btn-ghost" onclick="closeProdModal()">Cancel</button>
            <button class="btn btn-primary" onclick="saveProduct()">Save</button>
          </div>
        </div>
      </div>

      <!-- Add Feature Modal -->
      <div class="modal-overlay" id="feature-modal" style="display:none">
        <div class="modal modal-sm">
          <div class="modal-header">
            <h2 id="feature-modal-title">Add Feature</h2>
            <button class="modal-close" onclick="closeFeatureModal()">&times;</button>
          </div>
          <div class="modal-body">
            <input type="hidden" id="feature-edit-id">
            <label>Feature Name<input type="text" id="feature-name" placeholder="e.g. API Key Management"></label>
            <label>Description<textarea id="feature-desc" placeholder="What should this feature cover?"></textarea></label>
          </div>
          <div class="modal-footer">
            <button class="btn btn-ghost" onclick="closeFeatureModal()">Cancel</button>
            <button class="btn btn-primary" onclick="saveFeature()">Save</button>
          </div>
        </div>
      </div>

      <!-- Generate Features Modal -->
      <div class="modal-overlay" id="generate-modal" style="display:none">
        <div class="modal">
          <div class="modal-header">
            <h2>Generate Features with Agent</h2>
            <button class="modal-close" onclick="closeGenerateModal()">&times;</button>
          </div>
          <div class="modal-body">
            <label>Describe your product and what features you expect
              <textarea id="generate-prompt" rows="5" placeholder="e.g. This is a B2C async API product. It includes a REST API, an API key management service, a customer-facing docs site, and a React frontend. We need features like authentication, rate limiting, error handling, monitoring, documentation..."></textarea>
            </label>
            <div class="ai-hint">This creates an issue on the board. An agent will pick it up, analyze the projects, and propose features as follow-up issues.</div>
          </div>
          <div class="modal-footer">
            <button class="btn btn-ghost" onclick="closeGenerateModal()">Cancel</button>
            <button class="btn btn-primary" id="generate-btn" onclick="generateFeatures()">Create Agent Task</button>
          </div>
        </div>
      </div>

      <!-- Gap Analysis Modal -->
      <div class="modal-overlay" id="gap-modal" style="display:none">
        <div class="modal modal-lg">
          <div class="modal-header">
            <h2>Gap Analysis</h2>
            <button class="modal-close" onclick="closeGapModal()">&times;</button>
          </div>
          <div class="modal-body">
            <div id="gap-results"></div>
          </div>
          <div class="modal-footer">
            <button class="btn btn-ghost" onclick="closeGapModal()">Close</button>
            <button class="btn btn-primary" id="create-issues-btn" onclick="createGapIssues()">Create Issues for Selected Gaps</button>
          </div>
        </div>
      </div>

      <script>
    #{js()}
      </script>
    </body>
    </html>
    """
  end

  defp css do
    alias SymphonyElixir.Server.UIHelpers
    UIHelpers.base_css() <> UIHelpers.topbar_css() <> UIHelpers.button_css() <>
    UIHelpers.form_css() <> UIHelpers.modal_css() <>
      ~S"""

      body {
        height: 100vh;
        display: flex;
        flex-direction: column;
        overflow: hidden;
      }

      .topbar { flex-wrap: wrap; gap: 8px; }

      .prod-select {
        background: var(--bg-tertiary);
        color: var(--text-secondary);
        border: 1px solid var(--border);
        border-radius: 6px;
        padding: 6px 10px;
        font-size: 0.85rem;
        min-width: 200px;
      }

      .legend {
        display: flex;
        gap: 12px;
        font-size: 0.75rem;
        color: var(--text-muted);
      }
      .legend-item { display: flex; align-items: center; gap: 4px; }

      .status-dot {
        width: 10px;
        height: 10px;
        border-radius: 3px;
        display: inline-block;
      }
      .status-done { background: var(--green); }
      .status-in_progress { background: var(--accent); }
      .status-planned { background: var(--yellow); }
      .status-missing { background: var(--red); }
      .status-n_a { background: #484f58; }

      /* Review-specific button overrides */
      .btn-accent {
        background: rgba(188,140,255,0.15);
        color: var(--purple);
        border: 1px solid rgba(188,140,255,0.3);
      }
      .btn-accent:hover { background: rgba(188,140,255,0.25); }

      /* Main content */
      .main {
        flex: 1;
        overflow: auto;
        padding: 24px;
      }

      .empty-state {
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        height: 60vh;
        color: var(--text-muted);
        gap: 16px;
        text-align: center;
      }
      .empty-state h2 { color: var(--text-secondary); font-size: 1.2rem; }
      .empty-state p { max-width: 400px; line-height: 1.5; }
      .empty-icon { opacity: 0.3; }

      /* Matrix */
      .matrix-container {
        min-width: fit-content;
      }

      .matrix-header {
        display: flex;
        align-items: flex-end;
        justify-content: space-between;
        margin-bottom: 16px;
        gap: 16px;
      }
      .matrix-header h2 {
        font-size: 1.1rem;
        font-weight: 600;
      }
      .matrix-header .prod-desc {
        color: var(--text-muted);
        font-size: 0.85rem;
        margin-top: 4px;
      }
      .matrix-actions {
        display: flex;
        gap: 8px;
        flex-shrink: 0;
      }

      .score-bar {
        display: flex;
        align-items: center;
        gap: 12px;
        margin-bottom: 20px;
        padding: 12px 16px;
        background: var(--bg-secondary);
        border: 1px solid var(--border);
        border-radius: var(--radius);
      }
      .score-label {
        font-size: 0.8rem;
        color: var(--text-muted);
        font-weight: 500;
      }
      .score-progress {
        flex: 1;
        height: 8px;
        background: var(--bg-tertiary);
        border-radius: 4px;
        overflow: hidden;
      }
      .score-fill {
        height: 100%;
        border-radius: 4px;
        transition: width 0.3s ease;
      }
      .score-value {
        font-size: 1rem;
        font-weight: 700;
        min-width: 50px;
        text-align: right;
      }

      /* Table */
      .matrix-table {
        width: 100%;
        border-collapse: separate;
        border-spacing: 0;
        background: var(--bg-secondary);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        overflow: hidden;
      }
      .matrix-table th, .matrix-table td {
        padding: 10px 14px;
        text-align: center;
        border-bottom: 1px solid var(--border-light);
      }
      .matrix-table th {
        background: var(--bg-tertiary);
        font-size: 0.75rem;
        font-weight: 600;
        text-transform: uppercase;
        letter-spacing: 0.04em;
        color: var(--text-muted);
        position: sticky;
        top: 0;
        z-index: 2;
      }
      .matrix-table th.feature-col {
        text-align: left;
        min-width: 200px;
      }
      .matrix-table th.project-col {
        min-width: 120px;
      }
      .matrix-table th.score-col {
        min-width: 80px;
      }
      .matrix-table td.feature-cell {
        text-align: left;
        font-weight: 500;
        font-size: 0.85rem;
      }
      .matrix-table td.feature-cell .feature-desc {
        font-size: 0.72rem;
        color: var(--text-muted);
        font-weight: 400;
        margin-top: 2px;
      }
      .matrix-table tr:last-child td { border-bottom: none; }
      .matrix-table tr:hover td { background: rgba(255,255,255,0.02); }

      /* Status cells */
      .status-cell {
        cursor: pointer;
        position: relative;
        transition: all var(--transition);
      }
      .status-cell:hover {
        background: var(--bg-hover) !important;
      }
      .status-badge {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 32px;
        height: 32px;
        border-radius: 6px;
        font-size: 1rem;
        transition: transform 0.15s;
      }
      .status-cell:hover .status-badge { transform: scale(1.15); }
      .status-badge.done { background: rgba(63,185,80,0.15); }
      .status-badge.in_progress { background: rgba(88,166,255,0.15); }
      .status-badge.planned { background: rgba(210,153,34,0.15); }
      .status-badge.missing { background: rgba(248,81,73,0.15); }
      .status-badge.n_a { background: rgba(72,79,88,0.25); }

      .score-cell {
        font-weight: 700;
        font-size: 0.85rem;
      }

      /* Footer score row */
      .matrix-table tfoot td {
        background: var(--bg-tertiary);
        font-weight: 600;
        font-size: 0.8rem;
        color: var(--text-muted);
        border-top: 2px solid var(--border);
        border-bottom: none;
      }

      /* Feature row actions */
      .feature-actions {
        display: inline-flex;
        gap: 4px;
        margin-left: 8px;
        opacity: 0;
        transition: opacity var(--transition);
      }
      .matrix-table tr:hover .feature-actions { opacity: 1; }
      .feature-action-btn {
        background: none;
        border: none;
        color: var(--text-muted);
        cursor: pointer;
        padding: 2px;
        font-size: 0.7rem;
        border-radius: 3px;
      }
      .feature-action-btn:hover { color: var(--text-primary); background: var(--bg-hover); }

      /* Add feature row */
      .add-feature-row td {
        border-bottom: none;
      }
      .add-feature-btn {
        background: none;
        border: 1px dashed var(--border);
        color: var(--text-muted);
        padding: 8px 16px;
        border-radius: var(--radius-sm);
        cursor: pointer;
        font-size: 0.8rem;
        transition: all var(--transition);
        width: 100%;
      }
      .add-feature-btn:hover {
        border-color: var(--accent);
        color: var(--accent);
        background: rgba(88,166,255,0.05);
      }

      /* Modals */
      /* Review modal overrides — shared base from UIHelpers */
      .modal-overlay { display: flex; }
      .modal { width: 480px; }
      .modal-sm { width: 400px; }
      .modal-lg { width: 640px; }
      .modal-header { padding: 16px 20px; border-bottom: 1px solid var(--border); }
      .modal-close {
        background: none; border: none; color: var(--text-muted);
        font-size: 1.3rem; cursor: pointer; padding: 4px;
      }
      .modal-close:hover { color: var(--text-primary); }
      .modal-body { padding: 20px; }
      .modal-body label {
        display: block; font-size: 0.8rem; color: var(--text-muted);
        font-weight: 500; margin-bottom: 12px;
      }
      .modal-body input[type="text"],
      .modal-body textarea {
        display: block; width: 100%; margin-top: 4px; padding: 8px 10px;
        background: var(--bg-tertiary); border: 1px solid var(--border);
        border-radius: var(--radius-sm); color: var(--text-primary);
        font-size: 0.85rem; font-family: inherit;
      }
      .modal-body textarea { min-height: 80px; resize: vertical; }
      .modal-body input:focus, .modal-body textarea:focus { outline: none; border-color: var(--accent); }
      .modal-footer {
        display: flex;
        justify-content: flex-end;
        gap: 8px;
        padding: 12px 20px;
        border-top: 1px solid var(--border);
      }

      /* Project checklist in modal */
      .project-checklist {
        max-height: 200px;
        overflow-y: auto;
        border: 1px solid var(--border);
        border-radius: var(--radius-sm);
        padding: 8px;
        margin-top: 4px;
      }
      .project-check-item {
        display: flex;
        align-items: center;
        gap: 8px;
        padding: 6px 4px;
        border-radius: 4px;
        cursor: pointer;
        font-size: 0.85rem;
      }
      .project-check-item:hover { background: var(--bg-hover); }
      .project-check-item input { accent-color: var(--accent); }

      /* Gap analysis results */
      .gap-list {
        display: flex;
        flex-direction: column;
        gap: 8px;
      }
      .gap-item {
        display: flex;
        align-items: flex-start;
        gap: 10px;
        padding: 10px 12px;
        background: var(--bg-tertiary);
        border: 1px solid var(--border);
        border-radius: var(--radius-sm);
      }
      .gap-item input { margin-top: 3px; accent-color: var(--accent); }
      .gap-info { flex: 1; }
      .gap-feature { font-weight: 600; font-size: 0.85rem; }
      .gap-project { font-size: 0.75rem; color: var(--text-muted); margin-top: 2px; }
      .gap-reason { font-size: 0.75rem; color: var(--yellow); margin-top: 4px; }
      .gap-empty {
        text-align: center;
        color: var(--green);
        padding: 24px;
        font-size: 0.9rem;
      }
      .gap-summary {
        display: flex;
        justify-content: space-between;
        padding: 10px 0;
        border-bottom: 1px solid var(--border);
        margin-bottom: 12px;
        font-size: 0.85rem;
        color: var(--text-muted);
      }

      /* AI hint text */
      .ai-hint {
        font-size: 0.75rem;
        color: var(--text-muted);
        margin-top: 8px;
        font-style: italic;
      }

      /* Check button in feature row */
      .check-btn {
        background: rgba(188,140,255,0.1);
        border: 1px solid rgba(188,140,255,0.2);
        color: var(--purple);
        padding: 3px 8px;
        border-radius: 4px;
        font-size: 0.68rem;
        cursor: pointer;
        transition: all var(--transition);
        white-space: nowrap;
      }
      .check-btn:hover {
        background: rgba(188,140,255,0.25);
        border-color: var(--purple);
      }
      .check-btn:disabled {
        opacity: 0.5;
        cursor: not-allowed;
      }
      .check-btn.checking {
        animation: pulse 1.5s ease-in-out infinite;
      }
      @keyframes pulse {
        0%, 100% { opacity: 1; }
        50% { opacity: 0.5; }
      }

      /* Spinner for generating */
      .spinner {
        display: inline-block;
        width: 14px;
        height: 14px;
        border: 2px solid var(--text-muted);
        border-top-color: transparent;
        border-radius: 50%;
        animation: spin 0.8s linear infinite;
        vertical-align: middle;
        margin-right: 6px;
      }
      @keyframes spin { to { transform: rotate(360deg); } }
      """
  end

  defp js do
    SymphonyElixir.Server.UIHelpers.esc_js() <>
      ~S"""

      const API = '/board/api';
      let allProducts = [];
      let allProjects = [];
      let currentProd = null;

      const STATUS_ORDER = ['missing', 'planned', 'in_progress', 'done', 'n_a'];
      const STATUS_ICONS = {
        done: '\u2705',
        in_progress: '\uD83D\uDD35',
        planned: '\uD83D\uDFE1',
        missing: '\uD83D\uDD34',
        n_a: '\u2B1C'
      };
      const STATUS_LABELS = {
        done: 'Done',
        in_progress: 'In Progress',
        planned: 'Planned',
        missing: 'Missing',
        n_a: 'N/A'
      };

      async function init() {
        await Promise.all([loadProducts(), loadProjects()]);
        populateProdSelect();

        // Auto-select if only one product
        if (allProducts.length === 1) {
          document.getElementById('product-select').value = allProducts[0].id;
          selectProduct();
        }
      }

      async function loadProducts() {
        var res = await fetch(API + '/products');
        var data = await res.json();
        allProducts = data.products || [];
      }

      async function loadProjects() {
        var res = await fetch(API + '/projects');
        var data = await res.json();
        allProjects = data.projects || [];
      }

      function populateProdSelect() {
        var sel = document.getElementById('product-select');
        sel.innerHTML = '<option value="">Select product...</option>';
        allProducts.forEach(function(c) {
          sel.innerHTML += '<option value="' + c.id + '">' + esc(c.name) + ' (' + (c.features || []).length + ' features)</option>';
        });
      }

      async function selectProduct() {
        var id = document.getElementById('product-select').value;
        if (!id) {
          currentProd = null;
          document.getElementById('empty-state').style.display = '';
          document.getElementById('matrix-container').style.display = 'none';
          document.getElementById('analyze-btn').style.display = 'none';
          return;
        }
        var res = await fetch(API + '/products/' + id);
        currentProd = await res.json();
        document.getElementById('empty-state').style.display = 'none';
        document.getElementById('matrix-container').style.display = '';
        document.getElementById('analyze-btn').style.display = '';
        renderMatrix();
      }

      function getProjectById(id) {
        return allProjects.find(function(p) { return p.id === id; }) || { id: id, name: id };
      }

      function computeScore(statuses, projectIds) {
        var applicable = projectIds.filter(function(pid) {
          return (statuses[pid] || 'missing') !== 'n_a';
        });
        if (applicable.length === 0) return 100;
        var done = applicable.filter(function(pid) {
          return statuses[pid] === 'done';
        }).length;
        return Math.round((done / applicable.length) * 100);
      }

      function computeProjectScore(features, projectId) {
        var applicable = features.filter(function(f) {
          return (f.statuses[projectId] || 'missing') !== 'n_a';
        });
        if (applicable.length === 0) return 100;
        var done = applicable.filter(function(f) {
          return f.statuses[projectId] === 'done';
        }).length;
        return Math.round((done / applicable.length) * 100);
      }

      function scoreColor(pct) {
        if (pct === 0) return 'var(--text-muted)';
        if (pct >= 80) return 'var(--green)';
        if (pct >= 50) return 'var(--yellow)';
        return 'var(--red)';
      }

      function renderMatrix() {
        if (!currentProd) return;
        var prod = currentProd;
        var pids = prod.project_ids || [];
        var features = prod.features || [];

        // Header
        var header = document.getElementById('matrix-header');
        header.innerHTML =
          '<div>' +
            '<h2>' + esc(prod.name) + '</h2>' +
            (prod.description ? '<div class="prod-desc">' + esc(prod.description) + '</div>' : '') +
          '</div>' +
          '<div class="matrix-actions">' +
            '<button class="btn btn-accent btn-sm" onclick="openGenerateModal()" title="Use AI to generate features from a description"><span class="spinner" style="display:none" id="gen-spinner"></span>Generate Features</button>' +
            '<button class="btn btn-ghost btn-sm" onclick="openEditProductModal()">Edit</button>' +
            '<button class="btn btn-danger btn-sm" onclick="deleteCurrentProduct()">Delete</button>' +
          '</div>';

        // Overall score
        var totalApplicable = 0;
        var totalDone = 0;
        features.forEach(function(f) {
          pids.forEach(function(pid) {
            var s = f.statuses[pid] || 'missing';
            if (s !== 'n_a') {
              totalApplicable++;
              if (s === 'done') totalDone++;
            }
          });
        });
        var overallPct = totalApplicable > 0 ? Math.round((totalDone / totalApplicable) * 100) : 100;

        // Table
        var body = document.getElementById('matrix-body');
        var html = '';

        // Score bar
        html += '<div class="score-bar">' +
          '<span class="score-label">Overall Completeness</span>' +
          '<div class="score-progress"><div class="score-fill" style="width:' + overallPct + '%;background:' + scoreColor(overallPct) + '"></div></div>' +
          '<span class="score-value" style="color:' + scoreColor(overallPct) + '">' + overallPct + '%</span>' +
        '</div>';

        // Table
        html += '<table class="matrix-table"><thead><tr>';
        html += '<th class="feature-col">Feature</th>';
        pids.forEach(function(pid) {
          var p = getProjectById(pid);
          html += '<th class="project-col">' + esc(p.name) + '</th>';
        });
        html += '<th class="score-col">Score</th>';
        html += '<th class="score-col"></th>';
        html += '</tr></thead><tbody>';

        if (features.length === 0) {
          html += '<tr><td colspan="' + (pids.length + 3) + '" style="text-align:center;padding:24px;color:var(--text-muted)">No features defined yet. Add one below.</td></tr>';
        }

        features.forEach(function(f) {
          html += '<tr>';
          html += '<td class="feature-cell">' +
            esc(f.name) +
            (f.description ? '<div class="feature-desc">' + esc(f.description) + '</div>' : '') +
            '<span class="feature-actions">' +
              '<button class="feature-action-btn" onclick="editFeature(\'' + f.id + '\')" title="Edit">&#9998;</button>' +
              '<button class="feature-action-btn" onclick="deleteFeature(\'' + f.id + '\')" title="Delete">&times;</button>' +
            '</span>' +
          '</td>';

          pids.forEach(function(pid) {
            var status = f.statuses[pid] || 'missing';
            html += '<td class="status-cell" onclick="cycleStatus(\'' + f.id + '\',\'' + pid + '\',\'' + status + '\')">' +
              '<span class="status-badge ' + status + '" title="' + STATUS_LABELS[status] + ' — click to change">' + STATUS_ICONS[status] + '</span>' +
            '</td>';
          });

          var rowScore = computeScore(f.statuses, pids);
          html += '<td class="score-cell" style="color:' + scoreColor(rowScore) + '">' + rowScore + '%</td>';
          html += '<td><button class="check-btn" id="check-' + f.id + '" onclick="checkFeature(\'' + f.id + '\')" title="AI checks if this feature is implemented">Check</button></td>';
          html += '</tr>';
        });

        // Add feature row
        html += '<tr class="add-feature-row"><td colspan="' + (pids.length + 3) + '"><button class="add-feature-btn" onclick="openAddFeatureModal()">+ Add Feature</button></td></tr>';

        html += '</tbody>';

        // Footer with per-project scores
        html += '<tfoot><tr><td style="text-align:left;font-weight:600">Project Score</td>';
        pids.forEach(function(pid) {
          var pScore = computeProjectScore(features, pid);
          html += '<td style="color:' + scoreColor(pScore) + ';font-weight:700">' + pScore + '%</td>';
        });
        html += '<td></td><td></td></tr></tfoot>';

        html += '</table>';
        body.innerHTML = html;

        // Footer
        document.getElementById('matrix-footer').innerHTML = '';
      }

      async function cycleStatus(featureId, projectId, current) {
        var idx = STATUS_ORDER.indexOf(current);
        var next = STATUS_ORDER[(idx + 1) % STATUS_ORDER.length];

        await fetch(API + '/products/' + currentProd.id + '/features/' + featureId + '/status', {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ project_id: projectId, status: next })
        });

        var res = await fetch(API + '/products/' + currentProd.id);
        currentProd = await res.json();
        renderMatrix();
      }

      // --- Product CRUD ---

      function openNewProductModal() {
        document.getElementById('prod-modal-title').textContent = 'New Product';
        document.getElementById('prod-edit-id').value = '';
        document.getElementById('prod-name').value = '';
        document.getElementById('prod-desc').value = '';
        renderProjectChecklist([]);
        document.getElementById('prod-modal').style.display = '';
        document.getElementById('prod-name').focus();
      }

      function openEditProductModal() {
        if (!currentProd) return;
        document.getElementById('prod-modal-title').textContent = 'Edit Product';
        document.getElementById('prod-edit-id').value = currentProd.id;
        document.getElementById('prod-name').value = currentProd.name || '';
        document.getElementById('prod-desc').value = currentProd.description || '';
        renderProjectChecklist(currentProd.project_ids || []);
        document.getElementById('prod-modal').style.display = '';
        document.getElementById('prod-name').focus();
      }

      function closeProdModal() {
        document.getElementById('prod-modal').style.display = 'none';
      }

      function renderProjectChecklist(selectedIds) {
        var container = document.getElementById('project-checklist');
        if (allProjects.length === 0) {
          container.innerHTML = '<div style="color:var(--text-muted);padding:8px;font-size:0.8rem">No projects yet. Create projects on the Board first.</div>';
          return;
        }
        container.innerHTML = allProjects.map(function(p) {
          var checked = selectedIds.indexOf(p.id) !== -1 ? 'checked' : '';
          return '<label class="project-check-item"><input type="checkbox" value="' + p.id + '" ' + checked + '> ' + esc(p.name) + (p.description ? ' <span style="color:var(--text-muted);font-size:0.75rem">— ' + esc(p.description) + '</span>' : '') + '</label>';
        }).join('');
      }

      async function saveProduct() {
        var editId = document.getElementById('prod-edit-id').value;
        var name = document.getElementById('prod-name').value.trim();
        if (!name) { document.getElementById('prod-name').focus(); return; }

        var desc = document.getElementById('prod-desc').value.trim();
        var checks = document.querySelectorAll('#project-checklist input[type=checkbox]:checked');
        var projectIds = Array.from(checks).map(function(c) { return c.value; });

        var payload = { name: name, description: desc || null, project_ids: projectIds };

        if (editId) {
          await fetch(API + '/products/' + editId, {
            method: 'PATCH',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
          });
        } else {
          await fetch(API + '/products', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
          });
        }

        closeProdModal();
        await loadProducts();
        populateProdSelect();

        if (editId) {
          document.getElementById('product-select').value = editId;
        } else if (allProducts.length > 0) {
          document.getElementById('product-select').value = allProducts[allProducts.length - 1].id;
        }
        selectProduct();
      }

      async function deleteCurrentProduct() {
        if (!currentProd) return;
        if (!confirm('Delete product "' + currentProd.name + '"?')) return;

        await fetch(API + '/products/' + currentProd.id, { method: 'DELETE' });
        currentProd = null;
        await loadProducts();
        populateProdSelect();
        document.getElementById('product-select').value = '';
        selectProduct();
      }

      // --- Feature CRUD ---

      function openAddFeatureModal() {
        document.getElementById('feature-modal-title').textContent = 'Add Feature';
        document.getElementById('feature-edit-id').value = '';
        document.getElementById('feature-name').value = '';
        document.getElementById('feature-desc').value = '';
        document.getElementById('feature-modal').style.display = '';
        document.getElementById('feature-name').focus();
      }

      function editFeature(fid) {
        var f = currentProd.features.find(function(x) { return x.id === fid; });
        if (!f) return;
        document.getElementById('feature-modal-title').textContent = 'Edit Feature';
        document.getElementById('feature-edit-id').value = fid;
        document.getElementById('feature-name').value = f.name || '';
        document.getElementById('feature-desc').value = f.description || '';
        document.getElementById('feature-modal').style.display = '';
        document.getElementById('feature-name').focus();
      }

      function closeFeatureModal() {
        document.getElementById('feature-modal').style.display = 'none';
      }

      async function saveFeature() {
        var editId = document.getElementById('feature-edit-id').value;
        var name = document.getElementById('feature-name').value.trim();
        if (!name) { document.getElementById('feature-name').focus(); return; }

        var desc = document.getElementById('feature-desc').value.trim();
        var payload = { name: name, description: desc || null };

        if (editId) {
          await fetch(API + '/products/' + currentProd.id + '/features/' + editId, {
            method: 'PATCH',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
          });
        } else {
          await fetch(API + '/products/' + currentProd.id + '/features', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
          });
        }

        closeFeatureModal();
        var res = await fetch(API + '/products/' + currentProd.id);
        currentProd = await res.json();
        renderMatrix();
      }

      async function deleteFeature(fid) {
        if (!confirm('Delete this feature?')) return;
        await fetch(API + '/products/' + currentProd.id + '/features/' + fid, { method: 'DELETE' });
        var res = await fetch(API + '/products/' + currentProd.id);
        currentProd = await res.json();
        renderMatrix();
      }

      // --- Gap Analysis ---

      var lastGaps = [];

      async function analyzeGaps() {
        if (!currentProd) return;
        var btn = document.getElementById('analyze-btn');
        btn.textContent = 'Analyzing...';
        btn.disabled = true;

        try {
          var res = await fetch(API + '/products/' + currentProd.id + '/analyze-gaps', { method: 'POST' });
          var data = await res.json();
          lastGaps = data.gaps || [];
          renderGapModal();
          document.getElementById('gap-modal').style.display = '';
        } catch (e) {
          alert('Gap analysis failed: ' + e.message);
        } finally {
          btn.innerHTML = '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2"><path d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z"/></svg> Analyze Gaps';
          btn.disabled = false;
        }
      }

      function renderGapModal() {
        var html = '';
        if (lastGaps.length === 0) {
          html = '<div class="gap-empty">\u2705 No gaps found! All features are covered across all projects.</div>';
          document.getElementById('create-issues-btn').style.display = 'none';
        } else {
          html += '<div class="gap-summary"><span>' + lastGaps.length + ' gap(s) found</span><label><input type="checkbox" onchange="toggleAllGaps(this)" checked> Select All</label></div>';
          html += '<div class="gap-list">';
          lastGaps.forEach(function(g, idx) {
            html += '<div class="gap-item">' +
              '<input type="checkbox" class="gap-check" data-idx="' + idx + '" checked>' +
              '<div class="gap-info">' +
                '<div class="gap-feature">' + esc(g.feature_name) + '</div>' +
                '<div class="gap-project">Project: ' + esc(g.project_name) + '</div>' +
                '<div class="gap-reason">' + esc(g.reason) + '</div>' +
              '</div>' +
            '</div>';
          });
          html += '</div>';
          document.getElementById('create-issues-btn').style.display = '';
        }
        document.getElementById('gap-results').innerHTML = html;
      }

      function toggleAllGaps(master) {
        document.querySelectorAll('.gap-check').forEach(function(cb) {
          cb.checked = master.checked;
        });
      }

      function closeGapModal() {
        document.getElementById('gap-modal').style.display = 'none';
      }

      async function createGapIssues() {
        var checks = document.querySelectorAll('.gap-check:checked');
        if (checks.length === 0) { alert('No gaps selected.'); return; }

        var selected = Array.from(checks).map(function(cb) {
          return lastGaps[parseInt(cb.dataset.idx)];
        });

        var btn = document.getElementById('create-issues-btn');
        btn.textContent = 'Creating ' + selected.length + ' issue(s)...';
        btn.disabled = true;

        try {
          var res = await fetch(API + '/products/' + currentProd.id + '/create-gap-issues', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ gaps: selected })
          });
          var data = await res.json();
          var created = data.created || [];

          // Update statuses to "planned" for the created gaps
          for (var i = 0; i < selected.length; i++) {
            var gap = selected[i];
            await fetch(API + '/products/' + currentProd.id + '/features/' + gap.feature_id + '/status', {
              method: 'PATCH',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ project_id: gap.project_id, status: 'planned' })
            });
          }

          closeGapModal();
          alert('Created ' + created.length + ' issue(s) on the board. Statuses updated to Planned.');

          // Reload product
          var res2 = await fetch(API + '/products/' + currentProd.id);
          currentProd = await res2.json();
          renderMatrix();
        } catch (e) {
          alert('Failed to create issues: ' + e.message);
        } finally {
          btn.textContent = 'Create Issues for Selected Gaps';
          btn.disabled = false;
        }
      }

      // --- Generate Features (creates agent task) ---

      function openGenerateModal() {
        if (!currentProd) return;
        document.getElementById('generate-prompt').value = '';
        document.getElementById('generate-modal').style.display = '';
        document.getElementById('generate-prompt').focus();
      }

      function closeGenerateModal() {
        document.getElementById('generate-modal').style.display = 'none';
      }

      async function generateFeatures() {
        var prompt = document.getElementById('generate-prompt').value.trim();
        if (!prompt) { document.getElementById('generate-prompt').focus(); return; }

        var btn = document.getElementById('generate-btn');
        btn.innerHTML = '<span class="spinner"></span> Creating...';
        btn.disabled = true;

        try {
          var res = await fetch(API + '/products/' + currentProd.id + '/generate-features', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ prompt: prompt })
          });
          var data = await res.json();

          if (data.error) {
            alert('Error: ' + (data.message || data.error));
            return;
          }

          closeGenerateModal();
          var issue = data.issue;
          alert(issue.identifier + ' created on the board.\n\nThe agent will pick it up, analyze the product, and propose features as follow-up issues.\n\nCheck the board for progress.');
        } catch (e) {
          alert('Failed: ' + e.message);
        } finally {
          btn.innerHTML = 'Create Agent Task';
          btn.disabled = false;
        }
      }

      // --- Check Feature (creates agent tasks per project) ---

      async function checkFeature(featureId) {
        if (!currentProd) return;

        var feature = currentProd.features.find(function(f) { return f.id === featureId; });
        if (!feature) return;

        // Count how many projects will be checked (skip done/n_a)
        var toCheck = (currentProd.project_ids || []).filter(function(pid) {
          var s = feature.statuses[pid] || 'missing';
          return s !== 'done' && s !== 'n_a';
        });

        if (toCheck.length === 0) {
          alert('All projects are already done or N/A for this feature.');
          return;
        }

        if (!confirm('This will create ' + toCheck.length + ' issue(s) on the board — one per project to check.\n\nAgents will verify if "' + feature.name + '" is implemented and propose follow-ups for gaps.\n\nContinue?')) {
          return;
        }

        var btn = document.getElementById('check-' + featureId);
        if (btn) {
          btn.classList.add('checking');
          btn.textContent = 'Creating...';
          btn.disabled = true;
        }

        try {
          var res = await fetch(API + '/products/' + currentProd.id + '/features/' + featureId + '/check', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
          });
          var data = await res.json();

          if (data.error) {
            alert('Error: ' + (data.message || data.error));
            return;
          }

          // Reload product (statuses updated to in_progress)
          var res2 = await fetch(API + '/products/' + currentProd.id);
          currentProd = await res2.json();
          renderMatrix();

          var issues = data.issues || [];
          var ids = issues.map(function(i) { return i.identifier; }).join(', ');
          alert('Created ' + issues.length + ' check issue(s): ' + ids + '\n\nAgents will pick these up and report findings. Check the board for results.');
        } catch (e) {
          alert('Check failed: ' + e.message);
        } finally {
          var btn2 = document.getElementById('check-' + featureId);
          if (btn2) {
            btn2.classList.remove('checking');
            btn2.textContent = 'Check';
            btn2.disabled = false;
          }
        }
      }

      // --- Keyboard shortcuts ---
      document.addEventListener('keydown', function(e) {
        if (e.key === 'Escape') {
          closeProdModal();
          closeFeatureModal();
          closeGapModal();
          closeGenerateModal();
        }
      });

      init();
      """
  end
end

# credo:disable-for-this-file Credo.Check.Readability.MaxLineLength
defmodule SymphonyElixir.Server.PipelineUI do
  @moduledoc """
  Pipeline designer and execution monitor UI.
  
  - render_list/0: Pipeline list page at /pipeline
  - render_designer/1: Visual canvas designer for a specific pipeline
  """

  alias SymphonyElixir.Server.UIHelpers

  # ── Pipeline List Page ──────────────────────

  @spec render_list() :: String.t()
  def render_list do
    body = """
      <div class="page-header">
        <h2>Pipelines</h2>
        <button class="btn btn-primary" onclick="createPipeline()">+ New Pipeline</button>
      </div>
      <div id="gates-panel-container"></div>
      <div class="pipeline-grid" id="pipeline-grid"></div>
      <script>
    #{UIHelpers.esc_js()}
    #{UIHelpers.toast_js()}
    #{list_js()}
      </script>
    """

    UIHelpers.page_template("Symphony Pipelines", "pipeline", list_css(), body)
  end

  defp list_css do
    ~S"""
    
    .page-header {
      display: flex; align-items: center; justify-content: space-between;
      padding: 16px 24px; border-bottom: 1px solid var(--border);
    }
    .page-header h2 { font-size: 1.1rem; font-weight: 600; }
    
    .pipeline-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
      gap: 16px; padding: 24px;
    }
    
    .pipeline-card {
      background: var(--bg-secondary);
      border: 1px solid var(--border);
      border-radius: var(--radius);
      padding: 20px;
      cursor: pointer;
      transition: border-color var(--transition), box-shadow var(--transition);
    }
    .pipeline-card:hover {
      border-color: var(--accent);
      box-shadow: 0 0 0 1px var(--accent);
    }
    .pipeline-card-name {
      font-size: 1rem; font-weight: 600; color: var(--text-primary);
      margin-bottom: 4px;
    }
    .pipeline-card-desc {
      font-size: 0.85rem; color: var(--text-muted);
      margin-bottom: 12px;
      overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
    }
    .pipeline-card-meta {
      display: flex; align-items: center; gap: 12px;
      font-size: 0.8rem; color: var(--text-muted);
    }
    .pipeline-card-meta .node-count {
      background: var(--bg-tertiary); padding: 2px 8px;
      border-radius: 10px; font-size: 0.75rem;
    }
    .pipeline-card-actions {
      display: flex; gap: 6px; margin-top: 12px;
    }
    .run-badge {
      display: flex; align-items: center; gap: 6px; font-size: 0.72rem; font-weight: 600;
      padding: 4px 10px; border-radius: 4px; margin-bottom: 8px;
    }
    .run-dot { width: 6px; height: 6px; border-radius: 50%; flex-shrink: 0; }
    .run-detail { font-weight: 400; color: var(--text-muted); margin-left: auto; }
    .run-badge-running { background: rgba(88,166,255,0.12); color: var(--accent); }
    .run-badge-running .run-dot { background: var(--accent); animation: pulse 2s infinite; }
    .run-badge-paused { background: rgba(210,153,34,0.12); color: var(--yellow); }
    .run-badge-paused .run-dot { background: var(--yellow); }
    
    .mini-preview {
      height: 48px; margin-bottom: 12px;
      border-radius: 4px; overflow: hidden;
      background: var(--bg-tertiary);
    }
    .mini-preview svg { width: 100%; height: 100%; }
    
    .empty-state {
      grid-column: 1 / -1;
      text-align: center; padding: 60px 20px;
      color: var(--text-muted);
    }
    .empty-state h3 { font-size: 1.1rem; margin-bottom: 8px; color: var(--text-secondary); }
    
    /* Waiting gates panel */
    .gates-panel {
      margin: 0 24px; padding: 16px;
      background: var(--bg-secondary); border: 1px solid var(--border);
      border-radius: var(--radius);
    }
    .gates-panel-header {
      display: flex; align-items: center; justify-content: space-between;
      margin-bottom: 12px;
    }
    .gates-panel-header h3 { font-size: 0.95rem; font-weight: 600; }
    .gates-panel-header .gate-count {
      background: var(--yellow); color: #000; font-size: 0.75rem; font-weight: 700;
      padding: 2px 8px; border-radius: 10px;
    }
    .gate-table { width: 100%; border-collapse: collapse; font-size: 0.85rem; }
    .gate-table th {
      text-align: left; padding: 6px 8px; color: var(--text-muted);
      font-weight: 500; border-bottom: 1px solid var(--border);
    }
    .gate-table td { padding: 6px 8px; border-bottom: 1px solid var(--border); }
    .gate-table tr:hover { background: var(--bg-hover); }
    .gate-check { width: 20px; }
    .gate-state-badge {
      font-size: 0.72rem; padding: 2px 8px; border-radius: 4px; font-weight: 600;
    }
    .gate-state-waiting { background: rgba(210,153,34,0.15); color: var(--yellow); }
    .gate-state-on_hold { background: rgba(249,117,131,0.15); color: #f97583; }
    .batch-bar {
      display: flex; align-items: center; gap: 8px; margin-top: 10px;
      padding: 8px 0; border-top: 1px solid var(--border);
    }
    .batch-bar .selected-count { font-size: 0.8rem; color: var(--text-muted); margin-right: auto; }
    """
  end

  defp list_js do
    ~S"""
    let pipelines = [];
    let activeRuns = {};
    
    async function loadPipelines() {
      const [pRes, rRes] = await Promise.all([
        fetch('/board/api/pipelines'),
        fetch('/board/api/pipeline-runs/active')
      ]);
      const pData = await pRes.json();
      const rData = await rRes.json();
      pipelines = pData.pipelines || [];
      activeRuns = {};
      (rData.runs || []).forEach(function(r) { activeRuns[r.pipeline_id] = r; });
      renderGrid();
    }
    
    function runStatusBadge(pipelineId) {
      var run = activeRuns[pipelineId];
      if (!run) return '';
      var cls = 'run-badge-' + run.status;
      var label = run.status === 'running' ? 'Running' : run.status.charAt(0).toUpperCase() + run.status.slice(1);
      // Count completed vs total nodes
      var states = run.node_states || {};
      var total = Object.keys(states).length;
      var done = Object.values(states).filter(function(s) { return s === 'completed'; }).length;
      var waiting = Object.values(states).filter(function(s) { return s === 'waiting_gate'; }).length;
      var detail = done + '/' + total + ' nodes';
      if (waiting > 0) detail += ', ' + waiting + ' waiting';
      return '<div class="run-badge ' + cls + '" title="' + detail + '">' +
        '<span class="run-dot"></span> ' + label +
        ' <span class="run-detail">' + detail + '</span></div>';
    }
    
    function renderGrid() {
      const grid = document.getElementById('pipeline-grid');
      if (pipelines.length === 0) {
        grid.innerHTML = `
          <div class="empty-state">
            <h3>No pipelines yet</h3>
            <p>Create your first pipeline to orchestrate issues through process loops.</p>
          </div>`;
        return;
      }
      grid.innerHTML = pipelines.map(p => {
        const nodeCount = (p.nodes || []).length;
        const edgeCount = (p.edges || []).length;
        const desc = p.description ? esc(p.description) : 'No description';
        return `
          <div class="pipeline-card" onclick="openPipeline('${p.id}')">
            ${runStatusBadge(p.id)}
            <div class="mini-preview">${renderMiniSvg(p)}</div>
            <div class="pipeline-card-name">${esc(p.name)}</div>
            <div class="pipeline-card-desc">${desc}</div>
            <div class="pipeline-card-meta">
              <span class="node-count">${nodeCount} nodes</span>
              <span>${edgeCount} connections</span>
            </div>
            <div class="pipeline-card-actions">
              <button class="btn btn-sm btn-ghost"
                onclick="event.stopPropagation(); duplicatePipeline('${p.id}')">Duplicate</button>
              <button class="btn btn-sm btn-ghost" style="color:var(--red)"
                onclick="event.stopPropagation(); deletePipeline('${p.id}')">Delete</button>
            </div>
          </div>`;
      }).join('');
    }
    
    function renderMiniSvg(pipeline) {
      const nodes = pipeline.nodes || [];
      if (nodes.length === 0) return '';
      const minX = Math.min(...nodes.map(n => n.position.x));
      const minY = Math.min(...nodes.map(n => n.position.y));
      const maxX = Math.max(...nodes.map(n => n.position.x)) + 200;
      const maxY = Math.max(...nodes.map(n => n.position.y)) + 60;
      const w = maxX - minX + 40;
      const h = maxY - minY + 40;
    
      const colors = {
        'issue': '#58a6ff', 'human_gate': '#d29922', 'quality_gate': '#bc8cff',
        'loop': '#d18616', 'kb_sync': '#3fb950', 'integration': '#8b949e',
        'start': '#58a6ff', 'end': '#3fb950'
      };
    
      let svg = `<svg viewBox="${minX - 20} ${minY - 20} ${w} ${h}" preserveAspectRatio="xMidYMid meet">`;
    
      // edges
      const edges = pipeline.edges || [];
      const nodeMap = {};
      nodes.forEach(n => nodeMap[n.id] = n);
      edges.forEach(e => {
        const s = nodeMap[e.source_node_id];
        const t = nodeMap[e.target_node_id];
        if (s && t) {
          svg += `<line x1="${s.position.x + 100}" y1="${s.position.y + 30}"` +
            ` x2="${t.position.x + 100}" y2="${t.position.y + 30}" stroke="#30363d" stroke-width="2"/>`;
        }
      });
    
      // nodes
      nodes.forEach(n => {
        const c = colors[n.type] || '#8b949e';
        if (n.type === 'start' || n.type === 'end') {
          svg += `<circle cx="${n.position.x + 100}" cy="${n.position.y + 30}" r="8" fill="${c}" opacity="0.8"/>`;
        } else {
          svg += `<rect x="${n.position.x}" y="${n.position.y}"` +
            ` width="200" height="48" rx="6" fill="${c}" opacity="0.15" stroke="${c}" stroke-width="1.5"/>`;
        }
      });
    
      svg += '</svg>';
      return svg;
    }
    
    async function createPipeline() {
      const res = await fetch('/board/api/pipelines', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({ name: 'New Pipeline' })
      });
      const pipeline = await res.json();
      window.location.href = '/board/pipeline/' + pipeline.id;
    }
    
    function openPipeline(id) {
      window.location.href = '/board/pipeline/' + id;
    }
    
    async function duplicatePipeline(id) {
      const src = pipelines.find(p => p.id === id);
      if (!src) return;
      const res = await fetch('/board/api/pipelines', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          name: src.name + ' (Copy)',
          description: src.description,
          nodes: src.nodes,
          edges: src.edges,
          settings: src.settings
        })
      });
      if (res.ok) {
        showToast('Pipeline duplicated', { type: 'success' });
        loadPipelines();
      } else {
        showToast('Failed to duplicate pipeline', { type: 'error' });
      }
    }
    
    async function deletePipeline(id) {
      if (!confirm('Delete this pipeline?')) return;
      const res = await fetch('/board/api/pipelines/' + id, { method: 'DELETE' });
      if (res.ok) showToast('Pipeline deleted', { type: 'success' });
      else showToast('Failed to delete pipeline', { type: 'error' });
      loadPipelines();
    }
    
    loadPipelines();
    loadWaitingGates();
    setInterval(loadWaitingGates, 5000);
    
    let waitingGates = [];
    
    async function loadWaitingGates() {
      try {
        const res = await fetch('/board/api/pipeline-runs/waiting-gates');
        const data = await res.json();
        waitingGates = data.gates || [];
        renderGatesPanel();
      } catch(e) { /* ignore polling errors */ }
    }
    
    function renderGatesPanel() {
      const container = document.getElementById('gates-panel-container');
      if (waitingGates.length === 0) {
        container.innerHTML = '';
        return;
      }
      const typeLabels = { human_gate: 'Human', quality_gate: 'Quality', kb_sync: 'KB Sync' };
      const rows = waitingGates.map(function(g, i) {
        const stateClass = 'gate-state-' + g.state.replace('_', '_');
        const stateLabel = g.state === 'waiting_gate' ? 'Waiting' : 'On Hold';
        return '<tr>' +
          '<td class="gate-check"><input type="checkbox" class="gate-cb" data-idx="' + i + '"></td>' +
          '<td>' + esc(g.pipeline_name) + '</td>' +
          '<td>' + esc(g.label || g.node_type) + '</td>' +
          '<td>' + (typeLabels[g.node_type] || g.node_type) + '</td>' +
          '<td><span class="gate-state-badge ' + stateClass + '">' + stateLabel + '</span></td>' +
          '<td>' + g.attempts + '</td>' +
          '<td><a href="/pipeline/' + g.pipeline_id +
            '" style="color:var(--accent);text-decoration:none">Open</a></td>' +
          '</tr>';
      }).join('');
    
      container.innerHTML = '<div class="gates-panel">' +
        '<div class="gates-panel-header"><h3>Waiting Gates</h3>' +
        '<span class="gate-count">' + waitingGates.length + '</span></div>' +
        '<table class="gate-table">' +
        '<tr><th class="gate-check">' +
        '<input type="checkbox" id="gate-select-all" onchange="toggleAllGates(this.checked)"></th>' +
        '<th>Pipeline</th><th>Gate</th><th>Type</th><th>State</th><th>Attempts</th><th></th></tr>' +
        rows + '</table>' +
        '<div class="batch-bar">' +
        '<span class="selected-count" id="gate-selected-count">0 selected</span>' +
        '<textarea id="batch-gate-feedback" rows="1" placeholder="Feedback (optional)"' +
        ' style="flex:1;background:var(--bg-tertiary);border:1px solid var(--border);' +
        'border-radius:6px;color:var(--text-primary);padding:6px;font-size:0.8rem;resize:none"></textarea>' +
        '<button class="btn btn-sm" style="background:var(--green);color:#fff"' +
        ' onclick="batchGateAction(\'approve\')">Approve</button>' +
        '<button class="btn btn-sm" style="background:var(--red);color:#fff"' +
        ' onclick="batchGateAction(\'reject\')">Reject</button>' +
        '<button class="btn btn-sm btn-ghost" onclick="batchGateAction(\'hold\')">Hold</button>' +
        '</div></div>';
    
      document.querySelectorAll('.gate-cb').forEach(function(cb) {
        cb.addEventListener('change', updateGateSelectedCount);
      });
    }
    
    function toggleAllGates(checked) {
      document.querySelectorAll('.gate-cb').forEach(function(cb) { cb.checked = checked; });
      updateGateSelectedCount();
    }
    
    function updateGateSelectedCount() {
      const count = document.querySelectorAll('.gate-cb:checked').length;
      const el = document.getElementById('gate-selected-count');
      if (el) el.textContent = count + ' selected';
    }
    
    async function batchGateAction(action) {
      const checked = document.querySelectorAll('.gate-cb:checked');
      if (checked.length === 0) { showToast('Select at least one gate', { type: 'warning' }); return; }
      const feedback = (document.getElementById('batch-gate-feedback') || {}).value || '';
      let ok = 0, fail = 0;
      for (const cb of checked) {
        const g = waitingGates[parseInt(cb.dataset.idx)];
        if (!g) continue;
        try {
          const res = await fetch('/board/api/pipelines/' + g.pipeline_id +
            '/runs/' + g.run_id + '/gate/' + g.node_id, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ action: action, feedback: feedback })
          });
          if (res.ok) ok++; else fail++;
        } catch(e) { fail++; }
      }
      showToast(ok + ' gate(s) ' + action + 'd' + (fail > 0 ? ', ' + fail + ' failed' : ''),
        { type: fail > 0 ? 'warning' : 'success' });
      loadWaitingGates();
      loadPipelines();
    }
    """
  end

  # ── Pipeline Designer Page ──────────────────────

  @spec render_designer(map()) :: String.t()
  def render_designer(pipeline) do
    pipeline_json = Jason.encode!(pipeline)

    body = """
      <!-- Floating palette -->
      <div class="palette" id="palette">
        <div class="palette-item" draggable="true" data-type="start" title="Start">
          <svg viewBox="0 0 16 16" width="16" height="16"><circle cx="8" cy="8" r="6" fill="#58a6ff"/></svg>
        </div>
        <div class="palette-item" draggable="true" data-type="issue" title="Issue / Task"
          data-help='{"title":"Issue Node","what":"Creates an issue and dispatches an AI agent to work on it. Configure with a template title, description, and skills.","why":"The workhorse of pipelines — each issue node is one unit of AI work.","connects":"Issues, Skills, Orchestrator"}'>
          <svg viewBox="0 0 16 16" width="16" height="16">
            <rect x="2" y="2" width="12" height="12" rx="2" fill="#58a6ff"/></svg>
        </div>
        <div class="palette-item" draggable="true" data-type="human_gate" title="Human Gate"
          data-help='{"title":"Human Gate","what":"Pauses the pipeline for human review. Shows predecessor outputs and lets you approve, reject, or hold. Set review mode: Code, Plan, or Findings.","why":"Quality control — review AI output before the pipeline continues. Reject sends feedback back.","connects":"Pipeline flow, Issues (predecessors)"}'>
          <svg viewBox="0 0 16 16" width="16" height="16"><polygon points="8,1 15,8 8,15 1,8" fill="#d29922"/></svg>
        </div>
        <div class="palette-item" draggable="true" data-type="quality_gate" title="Quality Gate"
          data-help='{"title":"Quality Gate","what":"Runs automated checks (tests, lint, types) and auto-approves if they pass. Falls back to manual review on failure.","why":"Automated quality enforcement — catch regressions without manual intervention.","connects":"Pipeline flow, Check Commands, CI/CD"}'>
          <svg viewBox="0 0 16 16" width="16" height="16"><polygon points="8,1 15,8 8,15 1,8" fill="#bc8cff"/></svg>
        </div>
        <div class="palette-item" draggable="true" data-type="loop" title="Loop"
          data-help='{"title":"Loop Node","what":"Repeats a section of the pipeline until a condition is met or max retries reached.","why":"Iterative refinement — keep running scan→fix cycles until quality targets are met.","connects":"Pipeline flow, Loop condition"}'>
          <svg viewBox="0 0 16 16" width="16" height="16">
            <path d="M4 8a4 4 0 0 1 8 0" stroke="#d18616" stroke-width="2" fill="none"/>
            <path d="M10 6l2 2-2 2" stroke="#d18616" stroke-width="2" fill="none"/></svg>
        </div>
        <div class="palette-item" draggable="true" data-type="kb_sync" title="KB Sync"
          data-help='{"title":"KB Sync Node","what":"Collects outputs from predecessor issues and merges them into the Knowledge Base. Uses LLM to intelligently merge, not overwrite.","why":"Preserve what agents learn. After extraction or feature work, sync findings back to the KB for future runs.","connects":"Knowledge Base, Issues, Products"}'>
          <svg viewBox="0 0 16 16" width="16" height="16">
            <rect x="2" y="2" width="12" height="12" rx="2" fill="#3fb950"/></svg>
        </div>
        <div class="palette-item" draggable="true" data-type="integration" title="Integration"
          data-help='{"title":"Integration Node","what":"Connects to external services: GitLab CI pipelines, webhooks, or other APIs. Runs and waits for completion.","why":"Trigger real CI/CD pipelines, deploy steps, or external validations as part of your workflow.","connects":"GitLab, CI/CD, External APIs"}'>
          <svg viewBox="0 0 16 16" width="16" height="16">
            <rect x="2" y="2" width="12" height="12" rx="2" fill="#8b949e"/></svg>
        </div>
        <div class="palette-item" draggable="true" data-type="end" title="End">
          <svg viewBox="0 0 16 16" width="16" height="16"><circle cx="8" cy="8" r="6" fill="#3fb950"/></svg>
        </div>
      </div>
    
      <!-- Canvas -->
      <div class="canvas-viewport" id="viewport">
        <div class="canvas-transform" id="canvas-transform">
          <svg class="edge-layer" id="edge-layer"></svg>
          <div class="node-layer" id="node-layer"></div>
        </div>
      </div>
    
      <!-- Minimap -->
      <div class="minimap" id="minimap">
        <canvas id="minimap-canvas" width="160" height="100"></canvas>
        <div class="minimap-viewport" id="minimap-vp"></div>
      </div>
    
      <!-- Floating controls bottom-left -->
      <div class="zoom-controls">
        <button class="btn btn-sm btn-ghost" onclick="zoomOut()">-</button>
        <span id="zoom-level">100%</span>
        <button class="btn btn-sm btn-ghost" onclick="zoomIn()">+</button>
        <button class="btn btn-sm btn-ghost" onclick="zoomFit()">Fit</button>
      </div>
    
      <!-- Floating actions bottom-right -->
      <div class="canvas-actions">
        <button class="btn btn-sm btn-ghost" onclick="toggleRunHistory()"
          id="history-btn" title="Run History">&#128337; History</button>
        <button class="btn btn-sm btn-ghost" onclick="toggleExecution()" id="run-btn">&#9654; Run</button>
        <button class="btn btn-sm btn-primary" onclick="savePipeline()">Save</button>
      </div>
    
      <!-- Run history panel -->
      <div id="run-history-panel" class="run-history-panel" style="display:none">
        <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:12px">
          <h3 style="font-size:0.95rem;font-weight:600">Run History</h3>
          <button class="btn btn-sm btn-ghost" onclick="toggleRunHistory()" title="Close">&times;</button>
        </div>
        <div id="run-history-list"></div>
      </div>
    
      <!-- Pipeline name / breadcrumb top-left below topbar -->
      <div class="canvas-breadcrumb">
        <a href="/board/pipeline" class="btn btn-ghost btn-sm">&larr; Pipelines</a>
        <input id="pipeline-name" class="pipeline-name-input"
          value="#{UIHelpers.esc(pipeline.name)}" onchange="markDirty()">
        <span style="color:var(--border);font-size:0.9rem">/</span>
        <input id="pipeline-desc" class="pipeline-desc-input"
          placeholder="Add description..."
          value="#{UIHelpers.esc(pipeline.description || "")}" onchange="markDirty()">
        <span style="color:var(--border);font-size:0.9rem">/</span>
        <select id="pipeline-product" class="pipeline-product-select" onchange="markDirty()">
          <option value="">No product</option>
        </select>
        <button class="btn btn-ghost btn-sm" onclick="toggleHelpModal()"
          title="Keyboard shortcuts" style="margin-left:auto">?</button>
      </div>
    
      <!-- Help modal -->
      <div class="modal-overlay" id="help-modal" style="display:none"
        onclick="if(event.target===this)closeHelpModal()">
        <div class="modal" style="max-width:440px">
          <div class="modal-header">
            <h3>Keyboard Shortcuts</h3>
            <button class="btn-icon" onclick="closeHelpModal()">&times;</button>
          </div>
          <div class="modal-body" style="font-size:0.85rem">
            <table style="width:100%;border-collapse:collapse">
              <tr><td style="padding:4px 0;color:var(--text-muted)">Save</td>
                <td style="text-align:right"><kbd>Ctrl+S</kbd></td></tr>
              <tr><td style="padding:4px 0;color:var(--text-muted)">Undo</td>
                <td style="text-align:right"><kbd>Ctrl+Z</kbd></td></tr>
              <tr><td style="padding:4px 0;color:var(--text-muted)">Redo</td>
                <td style="text-align:right"><kbd>Ctrl+Y</kbd> / <kbd>Ctrl+Shift+Z</kbd></td></tr>
              <tr><td style="padding:4px 0;color:var(--text-muted)">Delete node</td>
                <td style="text-align:right"><kbd>Delete</kbd> / <kbd>Backspace</kbd></td></tr>
              <tr><td style="padding:4px 0;color:var(--text-muted)">Deselect / Close</td>
                <td style="text-align:right"><kbd>Escape</kbd></td></tr>
              <tr><td style="padding:4px 0;color:var(--text-muted)">Show help</td>
                <td style="text-align:right"><kbd>?</kbd></td></tr>
            </table>
            <div style="margin-top:12px;padding-top:12px;border-top:1px solid var(--border);color:var(--text-muted)">
              <strong style="color:var(--text-primary)">Mouse</strong><br>
              Drag from palette &rarr; add node<br>
              Drag port &rarr; connect nodes<br>
              Double-click node &rarr; configure<br>
              Middle-click / Ctrl+drag &rarr; pan<br>
              Scroll &rarr; zoom
            </div>
          </div>
        </div>
      </div>
    
      <!-- Create Issue modal (shared) -->
    #{UIHelpers.create_issue_modal_html(prefix: "ci", on_submit: "submitCreateIssue", on_cancel: "closeCreateIssueModal", submit_label: "Create &amp; Link", z_index: 1010, ai_draft: true, show_skills_picker: true)}
    
      <!-- Config modal -->
      <div class="modal-overlay" id="config-modal" style="display:none" onclick="if(event.target===this)closeConfig()">
        <div class="modal" style="max-width:520px">
          <div class="modal-header">
            <h3 id="config-title">Configure Node</h3>
            <button class="btn-icon" onclick="closeConfig()">&times;</button>
          </div>
          <div class="modal-body" id="config-body"></div>
          <div class="modal-footer">
            <button class="btn btn-ghost" onclick="closeConfig()">Cancel</button>
            <button class="btn btn-primary" onclick="applyConfig()">Apply</button>
          </div>
        </div>
      </div>
    
      <script>
    #{UIHelpers.esc_js()}
    #{UIHelpers.toast_js()}
    #{UIHelpers.color_maps_js()}
    const PIPELINE_DATA = #{pipeline_json};
    #{designer_js()}
      </script>
    """

    title = "#{UIHelpers.esc(pipeline.name)} — Symphony Pipeline"
    UIHelpers.page_template(title, "pipeline", designer_css(), body)
  end

  defp designer_css do
    UIHelpers.form_css() <>
      UIHelpers.modal_css() <>
      UIHelpers.ai_draft_css() <>
      UIHelpers.skill_picker_css() <>
      UIHelpers.integration_help_css() <>
      ~S"""
      
      body { overflow: hidden; height: 100vh; display: flex; flex-direction: column; }
      
      /* Floating palette */
      .palette {
        position: fixed; top: 60px; left: 50%; transform: translateX(-50%);
        z-index: 100; display: flex; gap: 4px;
        background: var(--bg-secondary); border: 1px solid var(--border);
        border-radius: 24px; padding: 6px 12px;
        box-shadow: var(--shadow);
      }
      .palette-item {
        position: relative;
        width: 36px; height: 36px; display: flex; align-items: center; justify-content: center;
        border-radius: 8px; cursor: grab; transition: background var(--transition);
      }
      .palette-item:hover { background: var(--bg-hover); }
      .palette-item:active { cursor: grabbing; }
      .palette-item[data-type]::after {
        content: attr(title);
        position: absolute; top: 44px; left: 50%; transform: translateX(-50%);
        font-size: 0.7rem; color: var(--text-muted); white-space: nowrap;
        background: var(--bg-secondary); padding: 2px 6px; border-radius: 4px;
        border: 1px solid var(--border); opacity: 0; pointer-events: none;
        transition: opacity 150ms;
      }
      .palette-item:hover::after { opacity: 1; }
      
      /* Canvas viewport */
      .canvas-viewport {
        flex: 1; overflow: hidden; position: relative;
        background: var(--bg-primary);
        background-image: radial-gradient(circle, var(--border) 1px, transparent 1px);
        background-size: 24px 24px;
      }
      .canvas-transform {
        position: absolute; top: 0; left: 0;
        transform-origin: 0 0;
        width: 0; height: 0;
      }
      
      /* Edge layer (SVG) */
      .edge-layer {
        position: absolute; top: 0; left: 0;
        width: 10000px; height: 10000px;
        pointer-events: none;
        overflow: visible;
      }
      .edge-layer path { pointer-events: stroke; cursor: pointer; }
      .edge-layer path:hover { stroke: var(--accent) !important; stroke-width: 3 !important; }
      .edge-path { stroke: #58687a; stroke-width: 2; fill: none; opacity: 0.7; }
      .edge-path-reject { stroke: var(--red); stroke-width: 2; fill: none; stroke-dasharray: 6 4; opacity: 0.7; }
      .edge-arrow { fill: #58687a; }
      
      /* Temp connection line while dragging */
      .temp-edge { stroke: var(--accent); stroke-width: 2; fill: none; stroke-dasharray: 6 3; }
      
      /* Node layer */
      .node-layer { position: absolute; top: 0; left: 0; }
      
      /* Pipeline node */
      .p-node {
        position: absolute; width: 200px;
        background: var(--bg-secondary);
        border: 2px solid var(--border); border-radius: 10px;
        cursor: move; user-select: none;
        transition: box-shadow 150ms;
      }
      .p-node:hover { box-shadow: 0 0 0 1px var(--accent); }
      .p-node.selected { border-color: var(--accent); box-shadow: 0 0 0 2px rgba(88,166,255,0.3); }
      .p-node-top { height: 4px; border-radius: 8px 8px 0 0; }
      .p-node-body { padding: 8px 12px; }
      .p-node-type { font-size: 0.7rem; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.5px; }
      .p-node-label { font-size: 0.85rem; font-weight: 500; color: var(--text-primary);
        margin-top: 2px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
      .p-node-meta { font-size: 0.75rem; color: var(--text-muted); margin-top: 4px; }
      
      /* Start/End special nodes */
      .p-node-terminal {
        position: absolute; width: 40px; height: 40px;
        border-radius: 50%; cursor: move; user-select: none;
        display: flex; align-items: center; justify-content: center;
        font-size: 0.7rem; font-weight: 600; color: #fff;
        transition: box-shadow 150ms;
      }
      .p-node-terminal:hover { box-shadow: 0 0 0 3px rgba(88,166,255,0.3); }
      .p-node-terminal.selected { box-shadow: 0 0 0 3px rgba(88,166,255,0.5); }
      
      /* Ports */
      .port {
        position: absolute; width: 10px; height: 10px;
        border-radius: 50%; background: var(--border);
        cursor: crosshair; z-index: 2;
        transition: background 150ms, transform 150ms;
        opacity: 0;
      }
      .p-node:hover .port, .p-node-terminal:hover .port, .port.active { opacity: 1; }
      .port:hover { background: var(--accent); transform: scale(1.4); }
      .port-out { right: -5px; top: 50%; margin-top: -5px; }
      .port-in { left: -5px; top: 50%; margin-top: -5px; }
      .port-reject { bottom: -5px; left: 50%; margin-left: -5px; background: var(--red); }
      
      /* Floating mini-toolbar above selected node */
      .node-toolbar {
        position: absolute; top: -36px; left: 50%; transform: translateX(-50%);
        display: flex; gap: 2px;
        background: var(--bg-secondary); border: 1px solid var(--border);
        border-radius: 6px; padding: 2px; box-shadow: var(--shadow);
        white-space: nowrap;
      }
      .node-toolbar button { font-size: 0.75rem; padding: 3px 8px; }
      
      /* Floating controls */
      .zoom-controls {
        position: fixed; bottom: 16px; left: 16px; z-index: 100;
        display: flex; align-items: center; gap: 4px;
        background: var(--bg-secondary); border: 1px solid var(--border);
        border-radius: 8px; padding: 4px 8px;
        font-size: 0.8rem; color: var(--text-muted);
      }
      .canvas-actions {
        position: fixed; bottom: 16px; right: 16px; z-index: 100;
        display: flex; gap: 6px;
      }
      .canvas-breadcrumb {
        position: fixed; top: 54px; left: 12px; z-index: 101;
        display: flex; align-items: center; gap: 8px;
      }
      .pipeline-name-input {
        background: transparent; border: 1px solid transparent;
        color: var(--text-primary); font-size: 0.9rem; font-weight: 600;
        padding: 4px 8px; border-radius: 6px;
        transition: border-color var(--transition);
      }
      .pipeline-name-input:hover { border-color: var(--border); }
      .pipeline-name-input:focus { border-color: var(--accent); outline: none; }
      .pipeline-desc-input {
        background: transparent; border: 1px solid transparent;
        color: var(--text-muted); font-size: 0.8rem;
        padding: 4px 8px; border-radius: 6px; min-width: 180px; max-width: 300px;
        transition: border-color var(--transition);
      }
      .pipeline-desc-input:hover { border-color: var(--border); }
      .pipeline-desc-input:focus { border-color: var(--accent); outline: none; color: var(--text-primary); }
      .pipeline-product-select {
        background: transparent; border: 1px solid transparent;
        color: var(--text-muted); font-size: 0.78rem;
        padding: 3px 6px; border-radius: 6px; cursor: pointer;
        transition: border-color var(--transition);
      }
      .pipeline-product-select:hover { border-color: var(--border); }
      .pipeline-product-select:focus { border-color: var(--accent); outline: none; color: var(--text-primary); }
      
      /* Execution overlay styles */
      .p-node.exec-completed { border-color: var(--green); box-shadow: 0 0 8px rgba(63,185,80,0.3); }
      .p-node.exec-running { border-color: var(--accent); animation: pulse-node 2s infinite; }
      .p-node.exec-waiting { border-color: var(--yellow); animation: pulse-gate 2s infinite; }
      .p-node.exec-failed { border-color: var(--red); box-shadow: 0 0 8px rgba(248,81,73,0.3); }
      .p-node.exec-on-hold { border-color: #f97583; animation: pulse-hold 2.5s infinite; }
      .p-node.exec-skipped { border-color: var(--text-muted); opacity: 0.5; }
      .p-node-terminal.exec-completed { box-shadow: 0 0 8px rgba(63,185,80,0.5); }
      
      @keyframes pulse-node {
        0%, 100% { box-shadow: 0 0 0 0 rgba(88,166,255,0.4); }
        50% { box-shadow: 0 0 0 8px rgba(88,166,255,0); }
      }
      @keyframes pulse-gate {
        0%, 100% { box-shadow: 0 0 0 0 rgba(210,153,34,0.4); }
        50% { box-shadow: 0 0 0 8px rgba(210,153,34,0); }
      }
      @keyframes pulse-hold {
        0%, 100% { box-shadow: 0 0 0 0 rgba(249,117,131,0.4); }
        50% { box-shadow: 0 0 0 8px rgba(249,117,131,0); }
      }
      
      /* Execution sidebar */
      .exec-sidebar {
        position: fixed; top: 48px; right: 0; bottom: 0; width: 480px;
        background: rgba(22,27,34,0.95); border-left: 1px solid var(--border);
        z-index: 110; transform: translateX(100%);
        transition: transform 250ms ease; overflow-y: auto; padding: 16px;
      }
      .exec-sidebar.open { transform: translateX(0); }
      .exec-sidebar h3 { font-size: 0.95rem; margin-bottom: 12px; }
      .gate-action { margin-top: 12px; display: flex; gap: 6px; }
      .gate-feedback { width: 100%; margin-top: 8px; background: var(--bg-tertiary);
        border: 1px solid var(--border); border-radius: 6px; color: var(--text-primary);
        padding: 8px; font-size: 0.85rem; resize: vertical; min-height: 60px; }
      
      /* Gate prompt banner */
      .gate-prompt-banner {
        margin-top: 12px; padding: 10px 12px;
        background: linear-gradient(135deg, rgba(56,139,253,0.08), rgba(56,139,253,0.03));
        border: 1px solid rgba(56,139,253,0.3); border-radius: 8px;
      }
      
      /* Accordion styles */
      .accordion-header {
        font-size: 0.78rem; font-weight: 500; color: var(--text-secondary);
        cursor: pointer; padding: 6px 8px; border-radius: 4px;
        background: var(--bg-secondary); border: 1px solid var(--border);
        list-style: none; user-select: none;
      }
      .accordion-header::-webkit-details-marker { display: none; }
      .accordion-header::before {
        content: '\\25B6'; display: inline-block; margin-right: 6px;
        font-size: 0.6rem; transition: transform 150ms ease;
      }
      details[open] > .accordion-header::before { transform: rotate(90deg); }
      .accordion-body {
        padding: 8px 10px; font-size: 0.8rem; color: var(--text-secondary);
        border-left: 2px solid var(--border); margin-left: 4px; margin-top: 4px;
      }
      
      /* Issue accordion */
      .issue-accordion { margin-bottom: 6px; }
      .issue-accordion > .accordion-header {
        font-size: 0.8rem; padding: 8px 10px;
      }
      
      /* Report sections inside accordions */
      .report-section {
        margin-top: 8px; padding: 8px; background: var(--bg-tertiary);
        border-radius: 6px; border: 1px solid var(--border);
      }
      .report-section-title {
        font-size: 0.7rem; text-transform: uppercase; letter-spacing: 0.5px;
        color: var(--text-muted); margin-bottom: 4px; font-weight: 600;
      }
      .report-content {
        font-size: 0.78rem; line-height: 1.5; color: var(--text-secondary);
        max-height: 300px; overflow-y: auto;
      }
      
      /* Plan review content */
      .plan-review-content {
        font-size: 0.82rem; line-height: 1.6; color: var(--text-secondary);
        padding: 12px; background: var(--bg-tertiary);
        border: 1px solid var(--border); border-radius: 6px;
        max-height: 600px; overflow-y: auto;
      }
      .plan-review-content h2, .plan-review-content h3 { color: var(--text-primary); }
      .plan-review-content code {
        background: var(--bg-secondary); padding: 1px 4px;
        border-radius: 3px; font-size: 0.76rem;
      }
      
      /* Finding cards */
      .finding-card {
        padding: 8px 10px; background: var(--bg-secondary);
        border: 1px solid var(--border); border-radius: 6px;
        margin-bottom: 6px; transition: opacity 200ms ease;
      }
      .finding-card[data-decision="rejected"] {
        border-color: rgba(248,81,73,0.3);
      }
      .finding-card[data-decision="accepted"] {
        border-color: rgba(63,185,80,0.3);
      }
      .finding-header {
        display: flex; align-items: flex-start; gap: 8px;
      }
      .finding-actions {
        display: flex; gap: 4px; flex-shrink: 0;
      }
      .finding-btn {
        width: 28px; height: 28px; border-radius: 4px;
        border: 1px solid var(--border); background: var(--bg-tertiary);
        color: var(--text-muted); cursor: pointer; font-size: 0.85rem;
        display: flex; align-items: center; justify-content: center;
        transition: all 150ms ease;
      }
      .finding-btn:hover { border-color: var(--text-secondary); }
      .finding-accept.active {
        background: rgba(63,185,80,0.15); border-color: var(--green);
        color: var(--green);
      }
      .finding-reject.active {
        background: rgba(248,81,73,0.15); border-color: var(--red);
        color: var(--red);
      }
      
      /* Minimap */
      .minimap {
        position: fixed; bottom: 56px; left: 16px; z-index: 99;
        width: 160px; height: 100px;
        background: var(--bg-secondary); border: 1px solid var(--border);
        border-radius: 6px; overflow: hidden;
      }
      .minimap canvas { width: 100%; height: 100%; display: block; }
      .minimap-viewport {
        position: absolute; border: 1.5px solid var(--accent);
        border-radius: 2px; pointer-events: none;
        background: rgba(88,166,255,0.06);
      }
      
      /* Kbd styling */
      kbd {
        background: var(--bg-tertiary); border: 1px solid var(--border);
        border-radius: 4px; padding: 1px 6px; font-size: 0.8rem;
        font-family: inherit; color: var(--text-primary);
      }
      
      /* Edge animation during execution */
      .edge-flow { animation: dash-flow 1s linear infinite; }
      @keyframes dash-flow {
        from { stroke-dashoffset: 20; }
        to { stroke-dashoffset: 0; }
      }
      
      /* Run history panel */
      .run-history-panel {
        position: fixed; top: 48px; right: 0; bottom: 0; width: 340px;
        background: rgba(22,27,34,0.97); border-left: 1px solid var(--border);
        z-index: 115; overflow-y: auto; padding: 16px;
      }
      .rh-item {
        padding: 10px 12px; border: 1px solid var(--border);
        border-radius: 6px; margin-bottom: 8px; cursor: default;
        background: var(--bg-secondary);
      }
      .rh-item-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 4px; }
      .rh-status {
        font-size: 0.72rem; font-weight: 600; padding: 2px 8px; border-radius: 10px;
      }
      .rh-status-completed { background: rgba(63,185,80,0.15); color: var(--green); }
      .rh-status-failed { background: rgba(248,81,73,0.15); color: var(--red); }
      .rh-status-cancelled { background: rgba(139,148,158,0.15); color: var(--text-muted); }
      .rh-status-running { background: rgba(88,166,255,0.12); color: var(--accent); }
      .rh-status-paused { background: rgba(210,153,34,0.12); color: var(--yellow); }
      .rh-time { font-size: 0.75rem; color: var(--text-muted); }
      .rh-nodes { font-size: 0.78rem; color: var(--text-secondary); margin-top: 4px; }
      .rh-gates { margin-top: 6px; }
      .rh-gate {
        font-size: 0.72rem; padding: 4px 8px;
        background: var(--bg-tertiary); border-radius: 4px; margin-top: 3px;
        color: var(--text-secondary);
      }
      .rh-empty { text-align: center; padding: 24px; color: var(--text-muted); font-size: 0.85rem; }
      """
  end

  defp designer_js do
    state_js() <>
      render_js() <>
      pan_zoom_js() <>
      node_interaction_js() <>
      palette_js() <>
      config_modal_js() <>
      UIHelpers.create_issue_modal_js("ci") <>
      UIHelpers.skill_picker_js() <>
      UIHelpers.load_skills_js() <>
      modal_utils_js() <>
      save_js() <>
      execution_js() <>
      help_and_utils_js() <>
      product_and_history_js() <>
      init_js()
  end

  defp state_js do
    ~S"""
    // ══════════════════════════════════
    // State
    // ══════════════════════════════════
    let pipeline = JSON.parse(JSON.stringify(PIPELINE_DATA));
    let nodes = pipeline.nodes || [];
    let edges = pipeline.edges || [];
    let selectedNodeId = null;
    let dirty = false;
    let scale = 1;
    let panX = 200, panY = 100;
    let isPanning = false;
    let panStartX, panStartY, panStartPanX, panStartPanY;
    let dragNode = null, dragOffX = 0, dragOffY = 0, dragUndoPushed = false;
    let connectFrom = null; // {nodeId, port}
    let execMode = false;
    let activeRun = null;
    let pollTimer = null;
    // allSkills, allSkillGroups loaded via UIHelpers.load_skills_js()
    
    // Undo/redo stack
    let undoStack = [];
    let redoStack = [];
    const MAX_UNDO = 50;
    
    function pushUndo() {
      undoStack.push(JSON.stringify({ nodes, edges }));
      if (undoStack.length > MAX_UNDO) undoStack.shift();
      redoStack = [];
    }
    
    function undo() {
      if (undoStack.length === 0) return;
      redoStack.push(JSON.stringify({ nodes, edges }));
      const state = JSON.parse(undoStack.pop());
      nodes = state.nodes;
      edges = state.edges;
      markDirty();
      render();
    }
    
    function redo() {
      if (redoStack.length === 0) return;
      undoStack.push(JSON.stringify({ nodes, edges }));
      const state = JSON.parse(redoStack.pop());
      nodes = state.nodes;
      edges = state.edges;
      markDirty();
      render();
    }
    
    const NODE_COLORS = {
      'issue': '#58a6ff', 'human_gate': '#d29922', 'quality_gate': '#bc8cff',
      'loop': '#d18616', 'kb_sync': '#3fb950', 'integration': '#8b949e',
      'start': '#58a6ff', 'end': '#3fb950'
    };
    const NODE_LABELS = {
      'issue': 'Issue / Task', 'human_gate': 'Human Gate', 'quality_gate': 'Quality Gate',
      'loop': 'Loop', 'kb_sync': 'KB Sync', 'integration': 'Integration',
      'start': 'Start', 'end': 'End'
    };
    
    const viewport = document.getElementById('viewport');
    const transform = document.getElementById('canvas-transform');
    const edgeLayer = document.getElementById('edge-layer');
    const nodeLayer = document.getElementById('node-layer');
    
    """
  end

  defp render_js do
    ~S"""
    // ══════════════════════════════════
    // Render
    // ══════════════════════════════════
    function render() {
      applyTransform();
      renderNodes();
      renderEdges();
      if (typeof renderMinimap === 'function') renderMinimap();
    }
    
    function applyTransform() {
      transform.style.transform = `translate(${panX}px, ${panY}px) scale(${scale})`;
      document.getElementById('zoom-level').textContent = Math.round(scale * 100) + '%';
    }
    
    function renderNodes() {
      nodeLayer.innerHTML = '';
      nodes.forEach(n => {
        const color = NODE_COLORS[n.type] || '#8b949e';
        if (n.type === 'start' || n.type === 'end') {
          const el = document.createElement('div');
          el.className = 'p-node-terminal' + (n.id === selectedNodeId ? ' selected' : '');
          el.style.left = n.position.x + 'px';
          el.style.top = n.position.y + 'px';
          el.style.background = color;
          el.dataset.nodeId = n.id;
          el.textContent = n.type === 'start' ? 'S' : 'E';
    
          // Ports
          if (n.type === 'start') {
            el.innerHTML += '<div class="port port-out" data-node="' + n.id + '" data-port="output"></div>';
          } else {
            el.innerHTML += '<div class="port port-in" data-node="' + n.id + '" data-port="input"></div>';
          }
    
          addExecClass(el, n.id);
          nodeLayer.appendChild(el);
        } else {
          const el = document.createElement('div');
          el.className = 'p-node' + (n.id === selectedNodeId ? ' selected' : '');
          el.style.left = n.position.x + 'px';
          el.style.top = n.position.y + 'px';
          el.dataset.nodeId = n.id;
    
          let meta = '';
          if (n.type === 'issue' && n.issue_id) meta = '<div class="p-node-meta">Linked issue</div>';
          if (n.type === 'loop') meta =
            '<div class="p-node-meta">Max retries: ' + (n.loop_max_retries || '∞') + '</div>';
          if (n.type === 'integration') meta = '<div class="p-node-meta">' + integrationNodeMeta(n) + '</div>';
    
          el.innerHTML = `
            <div class="p-node-top" style="background:${color}"></div>
            <div class="p-node-body">
              <div class="p-node-type">${NODE_LABELS[n.type] || n.type}</div>
              <div class="p-node-label">${esc(n.label || NODE_LABELS[n.type])}</div>
              ${meta}
            </div>
            <div class="port port-in" data-node="${n.id}" data-port="input"></div>
            <div class="port port-out" data-node="${n.id}" data-port="output"></div>
            ${(n.type === 'human_gate' || n.type === 'quality_gate')
              ? '<div class="port port-reject" data-node="' + n.id + '" data-port="reject"></div>' : ''}
          `;
    
          // Selected toolbar
          if (n.id === selectedNodeId && !execMode) {
            el.innerHTML += `
              <div class="node-toolbar">
                <button class="btn btn-sm btn-ghost"
                  onclick="event.stopPropagation(); openConfig('${n.id}')">Configure</button>
                <button class="btn btn-sm btn-ghost"
                  onclick="event.stopPropagation(); duplicateNode('${n.id}')">Duplicate</button>
                <button class="btn btn-sm btn-ghost" style="color:var(--red)"
                  onclick="event.stopPropagation(); deleteNode('${n.id}')">Delete</button>
              </div>`;
          }
    
          addExecClass(el, n.id);
          nodeLayer.appendChild(el);
        }
      });
    }
    
    function addExecClass(el, nodeId) {
      if (!execMode || !activeRun) return;
      const state = (activeRun.node_states || {})[nodeId];
      if (state === 'completed') el.classList.add('exec-completed');
      else if (state === 'running') el.classList.add('exec-running');
      else if (state === 'waiting_gate') el.classList.add('exec-waiting');
      else if (state === 'failed') el.classList.add('exec-failed');
      else if (state === 'on_hold') el.classList.add('exec-on-hold');
      else if (state === 'skipped') el.classList.add('exec-skipped');
    }
    
    function renderEdges() {
      edgeLayer.innerHTML = '';
      const nodeMap = {};
      nodes.forEach(n => nodeMap[n.id] = n);
    
      edges.forEach(e => {
        const src = nodeMap[e.source_node_id];
        const tgt = nodeMap[e.target_node_id];
        if (!src || !tgt) return;
    
        const isTerminalSrc = src.type === 'start' || src.type === 'end';
        const isTerminalTgt = tgt.type === 'start' || tgt.type === 'end';
    
        let sx, sy, tx, ty;
        if (e.source_port === 'reject') {
          sx = src.position.x + 100;
          sy = src.position.y + 70; // bottom port
        } else if (isTerminalSrc) {
          sx = src.position.x + 40;
          sy = src.position.y + 20;
        } else {
          sx = src.position.x + 200;
          sy = src.position.y + 35;
        }
    
        if (isTerminalTgt) {
          tx = tgt.position.x;
          ty = tgt.position.y + 20;
        } else {
          tx = tgt.position.x;
          ty = tgt.position.y + 35;
        }
    
        // Smooth cubic Bezier curve
        const dx = tx - sx;
        const dy = ty - sy;
        const cpOffset = Math.min(Math.abs(dx) * 0.5, 120);
        const path = `M${sx},${sy} C${sx + cpOffset},${sy} ${tx - cpOffset},${ty} ${tx},${ty}`;
    
        const cls = e.source_port === 'reject' ? 'edge-path-reject' : 'edge-path';
        const pathEl = document.createElementNS('http://www.w3.org/2000/svg', 'path');
        pathEl.setAttribute('d', path);
        pathEl.setAttribute('class', cls);
        pathEl.dataset.edgeId = e.id;
    
        if (execMode && activeRun) {
          const srcState = activeRun.node_states[e.source_node_id];
          if (srcState === 'completed') {
            pathEl.style.stroke = '#3fb950';
            pathEl.style.opacity = '1';
            pathEl.style.strokeDasharray = '8 4';
            pathEl.classList.add('edge-flow');
          }
        }
    
        pathEl.addEventListener('click', (ev) => {
          ev.stopPropagation();
          if (!execMode) {
            pushUndo();
            const removedEdge = e;
            edges = edges.filter(x => x.id !== removedEdge.id);
            markDirty();
            render();
            showToast('Connection deleted', { type: 'success',
              undo: function() { edges.push(removedEdge); undo(); } });
          }
        });
    
        edgeLayer.appendChild(pathEl);
    
        // Arrowhead — arrives horizontally from the last Bezier control point
        const angle = dx >= 0 ? 0 : Math.PI;
        const arrowSize = 6;
        const ax = tx;
        const ay = ty;
        const arrow = document.createElementNS('http://www.w3.org/2000/svg', 'polygon');
        const p1x = ax - arrowSize * Math.cos(angle - 0.5);
        const p1y = ay - arrowSize * Math.sin(angle - 0.5);
        const p2x = ax - arrowSize * Math.cos(angle + 0.5);
        const p2y = ay - arrowSize * Math.sin(angle + 0.5);
        arrow.setAttribute('points', `${ax},${ay} ${p1x},${p1y} ${p2x},${p2y}`);
        arrow.setAttribute('class', 'edge-arrow');
        if (e.source_port === 'reject') arrow.style.fill = 'var(--red)';
        edgeLayer.appendChild(arrow);
      });
    }
    
    """
  end

  defp pan_zoom_js do
    ~S"""
    // ══════════════════════════════════
    // Pan & Zoom
    // ══════════════════════════════════
    viewport.addEventListener('mousedown', e => {
      if (e.target === viewport || e.target === transform || e.target === edgeLayer) {
        if (e.button === 0) {
          selectedNodeId = null;
          render();
        }
        // Middle mouse or left-click on empty space for panning
        if (e.button === 1 || e.button === 0) {
          isPanning = true;
          panStartX = e.clientX;
          panStartY = e.clientY;
          panStartPanX = panX;
          panStartPanY = panY;
          if (e.button === 1) viewport.style.cursor = 'grabbing';
        }
      }
    });
    
    window.addEventListener('mousemove', e => {
      if (isPanning) {
        const dx = e.clientX - panStartX;
        const dy = e.clientY - panStartY;
        // Only start visual panning after a small threshold (avoids jerky click-to-deselect)
        if (Math.abs(dx) > 3 || Math.abs(dy) > 3) {
          viewport.style.cursor = 'grabbing';
        }
        panX = panStartPanX + dx;
        panY = panStartPanY + dy;
        applyTransform();
      }
      if (dragNode) {
        if (!dragUndoPushed) { pushUndo(); dragUndoPushed = true; }
        const x = (e.clientX - panX) / scale - dragOffX;
        const y = (e.clientY - panY) / scale - dragOffY;
        const node = nodes.find(n => n.id === dragNode);
        if (node) {
          node.position.x = Math.round(x / 12) * 12;
          node.position.y = Math.round(y / 12) * 12;
          render();
        }
      }
      if (connectFrom) {
        updateTempEdge(e.clientX, e.clientY);
      }
    });
    
    window.addEventListener('mouseup', e => {
      if (isPanning) {
        isPanning = false;
        viewport.style.cursor = '';
      }
      if (dragNode) {
        dragNode = null;
        markDirty();
      }
      if (connectFrom) {
        removeTempEdge();
        connectFrom = null;
      }
    });
    
    viewport.addEventListener('wheel', e => {
      e.preventDefault();
      const rect = viewport.getBoundingClientRect();
      const mx = e.clientX - rect.left;
      const my = e.clientY - rect.top;
      const oldScale = scale;
      const delta = e.deltaY > 0 ? 0.9 : 1.1;
      scale = Math.max(0.2, Math.min(3, scale * delta));
      panX = mx - (mx - panX) * (scale / oldScale);
      panY = my - (my - panY) * (scale / oldScale);
      applyTransform();
      renderEdges();
    }, { passive: false });
    
    function zoomIn() { scale = Math.min(3, scale * 1.2); applyTransform(); renderEdges(); }
    function zoomOut() { scale = Math.max(0.2, scale / 1.2); applyTransform(); renderEdges(); }
    function zoomFit() {
      if (nodes.length === 0) { scale = 1; panX = 200; panY = 100; applyTransform(); renderEdges(); return; }
      const xs = nodes.map(n => n.position.x);
      const ys = nodes.map(n => n.position.y);
      const minX = Math.min(...xs) - 50;
      const minY = Math.min(...ys) - 50;
      const maxX = Math.max(...xs) + 250;
      const maxY = Math.max(...ys) + 120;
      const w = maxX - minX;
      const h = maxY - minY;
      const vw = viewport.clientWidth;
      const vh = viewport.clientHeight;
      scale = Math.min(vw / w, vh / h, 1.5);
      panX = (vw - w * scale) / 2 - minX * scale;
      panY = (vh - h * scale) / 2 - minY * scale;
      applyTransform();
      renderEdges();
    }
    
    """
  end

  defp node_interaction_js do
    ~S"""
    // ══════════════════════════════════
    // Node interaction (drag, select, connect)
    // ══════════════════════════════════
    nodeLayer.addEventListener('mousedown', e => {
      const port = e.target.closest('.port');
      if (port) {
        e.stopPropagation();
        const nodeId = port.dataset.node;
        const portType = port.dataset.port;
        if (portType === 'output' || portType === 'reject') {
          connectFrom = { nodeId, port: portType };
          createTempEdge(e.clientX, e.clientY);
        }
        return;
      }
    
      // Ignore mousedown on toolbar buttons — let onclick fire instead
      if (e.target.closest('.node-toolbar')) {
        e.stopPropagation();
        return;
      }
    
      const nodeEl = e.target.closest('.p-node, .p-node-terminal');
      if (nodeEl && !execMode) {
        e.stopPropagation();
        const nodeId = nodeEl.dataset.nodeId;
        selectedNodeId = nodeId;
        dragNode = nodeId;
        dragUndoPushed = false;
        const node = nodes.find(n => n.id === nodeId);
        if (node) {
          dragOffX = (e.clientX - panX) / scale - node.position.x;
          dragOffY = (e.clientY - panY) / scale - node.position.y;
        }
        render();
      } else if (nodeEl && execMode) {
        e.stopPropagation();
        selectedNodeId = nodeEl.dataset.nodeId;
        render();
        showExecSidebar(nodeEl.dataset.nodeId);
      }
    });
    
    nodeLayer.addEventListener('mouseup', e => {
      if (connectFrom) {
        const port = e.target.closest('.port');
        if (port && port.dataset.port === 'input') {
          const targetNodeId = port.dataset.node;
          if (targetNodeId !== connectFrom.nodeId) {
            // Check for duplicate edge
            const exists = edges.some(ed =>
              ed.source_node_id === connectFrom.nodeId &&
              ed.target_node_id === targetNodeId &&
              ed.source_port === connectFrom.port
            );
            if (!exists) {
              pushUndo();
              edges.push({
                id: generateId(),
                source_node_id: connectFrom.nodeId,
                target_node_id: targetNodeId,
                source_port: connectFrom.port,
                label: connectFrom.port === 'reject' ? 'reject' : null
              });
              markDirty();
              render();
            }
          }
        }
        removeTempEdge();
        connectFrom = null;
      }
    });
    
    nodeLayer.addEventListener('dblclick', e => {
      const nodeEl = e.target.closest('.p-node, .p-node-terminal');
      if (nodeEl && !execMode) {
        openConfig(nodeEl.dataset.nodeId);
      }
    });
    
    // ══════════════════════════════════
    // Temp edge for connection drawing
    // ══════════════════════════════════
    let tempLine = null;
    function clientToCanvas(cx, cy) {
      const rect = viewport.getBoundingClientRect();
      return {
        x: (cx - rect.left - panX) / scale,
        y: (cy - rect.top - panY) / scale
      };
    }
    
    function createTempEdge(cx, cy) {
      tempLine = document.createElementNS('http://www.w3.org/2000/svg', 'line');
      tempLine.setAttribute('class', 'temp-edge');
      const node = nodes.find(n => n.id === connectFrom.nodeId);
      if (!node) return;
      let sx, sy;
      if (connectFrom.port === 'reject') {
        sx = node.position.x + 100;
        sy = node.position.y + 70;
      } else if (node.type === 'start' || node.type === 'end') {
        sx = node.position.x + 40;
        sy = node.position.y + 20;
      } else {
        sx = node.position.x + 200;
        sy = node.position.y + 35;
      }
      tempLine.setAttribute('x1', sx);
      tempLine.setAttribute('y1', sy);
      const pos = clientToCanvas(cx, cy);
      tempLine.setAttribute('x2', pos.x);
      tempLine.setAttribute('y2', pos.y);
      edgeLayer.appendChild(tempLine);
    }
    
    function updateTempEdge(cx, cy) {
      if (tempLine) {
        const pos = clientToCanvas(cx, cy);
        tempLine.setAttribute('x2', pos.x);
        tempLine.setAttribute('y2', pos.y);
      }
    }
    
    function removeTempEdge() {
      if (tempLine) { tempLine.remove(); tempLine = null; }
    }
    
    """
  end

  defp palette_js do
    ~S"""
    // ══════════════════════════════════
    // Palette drag-and-drop
    // ══════════════════════════════════
    document.querySelectorAll('.palette-item').forEach(item => {
      item.addEventListener('dragstart', e => {
        e.dataTransfer.setData('node-type', item.dataset.type);
        e.dataTransfer.effectAllowed = 'copy';
      });
    });
    
    viewport.addEventListener('dragover', e => { e.preventDefault(); e.dataTransfer.dropEffect = 'copy'; });
    viewport.addEventListener('drop', e => {
      e.preventDefault();
      const type = e.dataTransfer.getData('node-type');
      if (!type) return;
      const rect = viewport.getBoundingClientRect();
      const x = (e.clientX - rect.left - panX) / scale;
      const y = (e.clientY - rect.top - panY) / scale;
      addNode(type, Math.round(x / 12) * 12, Math.round(y / 12) * 12);
    });
    
    function addNode(type, x, y) {
      pushUndo();
      const id = generateId();
      const node = {
        id,
        type,
        issue_id: null,
        label: NODE_LABELS[type] || type,
        config: {},
        position: { x, y },
        loop_max_retries: type === 'loop' ? 5 : null,
        loop_condition: null
      };
      nodes.push(node);
    
      // Auto-connect: if a node is selected and has a free output port, connect it to the new node
      autoConnect(id, type);
    
      selectedNodeId = id;
      markDirty();
      render();
    }
    
    function autoConnect(newNodeId, newType) {
      // Don't auto-connect TO a start node or FROM an end node
      if (newType === 'start') return;
    
      // Find the best source node to connect from:
      // 1. The currently selected node (if it has a free output)
      // 2. Otherwise, the last node in the chain with a free output
      let sourceId = null;
    
      if (selectedNodeId) {
        const selNode = nodes.find(n => n.id === selectedNodeId);
        if (selNode && selNode.type !== 'end' && !hasOutgoingEdge(selectedNodeId, 'output')) {
          sourceId = selectedNodeId;
        }
      }
    
      if (!sourceId) {
        // Find nodes with free output ports (no outgoing 'output' edge), prefer start node first
        const freeNodes = nodes.filter(n =>
          n.id !== newNodeId &&
          n.type !== 'end' &&
          !hasOutgoingEdge(n.id, 'output')
        );
        // Prefer start node, then most recently added
        const startNode = freeNodes.find(n => n.type === 'start');
        sourceId = startNode ? startNode.id : (freeNodes.length > 0 ? freeNodes[freeNodes.length - 1].id : null);
      }
    
      if (sourceId) {
        edges.push({
          id: generateId(),
          source_node_id: sourceId,
          target_node_id: newNodeId,
          source_port: 'output',
          label: null
        });
      }
    }
    
    function hasOutgoingEdge(nodeId, port) {
      return edges.some(e => e.source_node_id === nodeId && e.source_port === port);
    }
    
    function deleteNode(nodeId) {
      pushUndo();
      nodes = nodes.filter(n => n.id !== nodeId);
      edges = edges.filter(e => e.source_node_id !== nodeId && e.target_node_id !== nodeId);
      if (selectedNodeId === nodeId) selectedNodeId = null;
      markDirty();
      render();
    }
    
    function duplicateNode(nodeId) {
      pushUndo();
      const orig = nodes.find(n => n.id === nodeId);
      if (!orig) return;
      const id = generateId();
      nodes.push({
        ...JSON.parse(JSON.stringify(orig)),
        id,
        position: { x: orig.position.x + 30, y: orig.position.y + 30 }
      });
      selectedNodeId = id;
      markDirty();
      render();
    }
    
    """
  end

  defp config_modal_js do
    ~S"""
    // ══════════════════════════════════
    // Configuration modal
    // ══════════════════════════════════
    let configNodeId = null;
    
    function openConfig(nodeId) {
      const node = nodes.find(n => n.id === nodeId);
      if (!node) return;
      configNodeId = nodeId;
      document.getElementById('config-title').textContent = 'Configure: ' + (NODE_LABELS[node.type] || node.type);
      const body = document.getElementById('config-body');
    
      let html = `
        <div class="form-group">
          <label>Label</label>
          <input id="cfg-label" value="${esc(node.label)}">
        </div>`;
    
      if (node.type === 'issue') {
        var cfg = node.config || {};
        html += `
          <div class="form-group">
            <label>Linked Issue ID
              <span style="font-weight:400;color:var(--text-muted)">(leave empty for template mode)</span></label>
            <input id="cfg-issue-id" value="${esc(node.issue_id || '')}" placeholder="Select or enter issue ID">
            <div id="issue-picker" style="margin-top:4px"></div>
          </div>
          <div style="border-top:1px solid var(--border);margin:12px 0;padding-top:8px">
            <div style="font-size:0.8rem;color:var(--text-muted);margin-bottom:8px">
              <strong>Template mode:</strong> If no issue is linked, the pipeline auto-creates one
              from this template at runtime — scoped to the pipeline's product.
            </div>
            <div class="form-group">
              <label>Template Title</label>
              <input id="cfg-tpl-title" value="${esc(cfg.title || '')}" placeholder="e.g., Extract Domain Rules">
            </div>
            <div class="form-group">
              <label>Template Description</label>
              <textarea id="cfg-tpl-desc" rows="3"
                placeholder="Task description for the agent...">${esc(cfg.description || '')}</textarea>
            </div>
            <div class="form-group">
              <label>Template Labels
                <span style="font-weight:400;color:var(--text-muted)">(comma-separated)</span></label>
              <input id="cfg-tpl-labels"
                value="${esc((cfg.labels || []).join(', '))}" placeholder="e.g., extract-logic, research">
            </div>
          </div>
          <div style="border-top:1px solid var(--border);margin:12px 0;padding-top:12px">
            <button class="btn btn-ghost" type="button"
              onclick="openCreateIssueModal()" style="width:100%">+ Create new issue</button>
          </div>`;
      }
    
      if (node.type === 'loop') {
        html += `
          <div class="form-group">
            <label>Max Retries</label>
            <input id="cfg-max-retries" type="number" value="${node.loop_max_retries || 5}" min="1" max="100">
          </div>
          <div class="form-group">
            <label>Loop Condition</label>
            <input id="cfg-loop-cond" value="${esc(node.loop_condition || '')}" placeholder="e.g., all checks pass">
          </div>`;
      }
    
      if (node.type === 'human_gate') {
        const autoTimeout = (node.config || {}).auto_approve_timeout_ms || '';
        const autoCond = (node.config || {}).auto_approve_condition || '';
        const webhookUrl = (node.config || {}).auto_approve_webhook_url || '';
        const reviewMode = (node.config || {}).review_mode || '';
        html += `
          <div class="form-group">
            <label>Review Mode</label>
            <select id="cfg-review-mode">
              <option value="" ${reviewMode === '' ? 'selected' : ''}>Default</option>
              <option value="code_review" ${reviewMode === 'code_review' ? 'selected' : ''}>Code Review</option>
              <option value="plan_review" ${reviewMode === 'plan_review' ? 'selected' : ''}>Plan Review</option>
              <option value="findings_review" ${reviewMode === 'findings_review' ? 'selected' : ''}>Findings Review</option>
            </select>
          </div>
          <div class="form-group">
            <label>Review Instructions</label>
            <textarea id="cfg-instructions" rows="3">${esc((node.config || {}).instructions || '')}</textarea>
          </div>
          <div class="form-group">
            <label>Auto-approve Timeout (ms, blank = manual only)</label>
            <input id="cfg-auto-timeout" type="number" value="${autoTimeout}"
              min="0" step="1000" placeholder="e.g. 300000 = 5 min">
          </div>
          <div class="form-group">
            <label>Auto-approve Condition</label>
            <select id="cfg-auto-cond">
              <option value="" ${autoCond === '' ? 'selected' : ''}>(None — manual only)</option>
              <option value="all_predecessors_completed"
                ${autoCond === 'all_predecessors_completed' ? 'selected' : ''}>All predecessors completed</option>
            </select>
          </div>
          <div class="form-group">
            <label>Webhook URL (POST, 2xx = approve)</label>
            <input id="cfg-webhook-url" value="${esc(webhookUrl)}" placeholder="https://...">
          </div>`;
      }
    
      if (node.type === 'quality_gate') {
        const checks = (node.config || {}).checks || ['tests', 'lint', 'types'];
        const checkCmds = (node.config || {}).check_commands || {};
        const checkCmdsStr = Object.entries(checkCmds).map(([k, v]) => k + ':' + v).join('\n');
        const autoTimeout = (node.config || {}).auto_approve_timeout_ms || '';
        const autoCond = (node.config || {}).auto_approve_condition || '';
        const webhookUrl = (node.config || {}).auto_approve_webhook_url || '';
        html += `
          <div class="form-group">
            <label>Quality Checks (comma-separated)</label>
            <input id="cfg-checks" value="${checks.join(', ')}">
          </div>
          <div class="form-group">
            <label>Check Commands (one per line: name:command)</label>
            <textarea id="cfg-check-cmds" rows="3"
              placeholder="tests:mix test\nlint:mix credo">${esc(checkCmdsStr)}</textarea>
          </div>
          <div class="form-group">
            <label>Auto-approve Timeout (ms, blank = manual only)</label>
            <input id="cfg-qg-auto-timeout" type="number" value="${autoTimeout}" min="0" step="1000" placeholder="e.g. 300000 = 5 min">
          </div>
          <div class="form-group">
            <label>Auto-approve Condition</label>
            <select id="cfg-qg-auto-cond">
              <option value="" ${autoCond === '' ? 'selected' : ''}>(None — manual only)</option>
              <option value="all_predecessors_completed" ${autoCond === 'all_predecessors_completed' ? 'selected' : ''}>All predecessors completed</option>
            </select>
          </div>
          <div class="form-group">
            <label>Webhook URL (POST, 2xx = approve)</label>
            <input id="cfg-qg-webhook-url" value="${esc(webhookUrl)}" placeholder="https://...">
          </div>`;
      }
    
      if (node.type === 'kb_sync') {
        const kbType = (node.config || {}).kb_type || '';
        const kbVaultPath = (node.config || {}).vault_path || '';
        const kbSubfolder = (node.config || {}).subfolder || '';
        html += `
          <div class="form-group">
            <label>KB Type</label>
            <select id="cfg-kb-type">
              <option value="" ${kbType === '' ? 'selected' : ''}>(Use Settings default)</option>
              <option value="local" ${kbType === 'local' ? 'selected' : ''}>Local Storage</option>
              <option value="obsidian" ${kbType === 'obsidian' ? 'selected' : ''}>Obsidian Vault</option>
              <option value="confluence" ${kbType === 'confluence' ? 'selected' : ''}>Confluence</option>
            </select>
          </div>
          <div class="form-group">
            <label>Vault Path (blank = Settings default)</label>
            <input id="cfg-kb-vault-path" value="${esc(kbVaultPath)}" placeholder="Leave blank for default">
          </div>
          <div class="form-group">
            <label>Subfolder (blank = Settings default)</label>
            <input id="cfg-kb-subfolder" value="${esc(kbSubfolder)}" placeholder="Leave blank for default">
          </div>`;
      }
    
      if (node.type === 'integration') {
        const intType = (node.config || {}).integration_type || 'jira';
        const intAction = (node.config || {}).action || '';
        const ac = (node.config || {}).action_config || {};
        const maxRetries = (node.config || {}).max_retries || 3;
        html += `
          <div class="form-group">
            <label>Integration Type</label>
            <select id="cfg-int-type" onchange="updateIntegrationFields()">
              <option value="jira" ${intType === 'jira' ? 'selected' : ''}>Jira</option>
              <option value="gitlab_ci" ${intType === 'gitlab_ci' ? 'selected' : ''}>GitLab CI</option>
              <option value="confluence" ${intType === 'confluence' ? 'selected' : ''}>Confluence</option>
            </select>
          </div>
          <div id="cfg-int-help"></div>
          <div id="cfg-int-fields"></div>
          <div class="form-group">
            <label>Max Retries on Failure</label>
            <input id="cfg-int-retries" type="number" value="${maxRetries}" min="0" max="20">
          </div>`;
        // Defer field rendering until modal is in DOM
        setTimeout(function() { updateIntegrationFields(esc(intAction), ac); }, 0);
      }
    
      body.innerHTML = html;
      document.getElementById('config-modal').style.display = 'flex';
      if (node.type === 'issue') loadIssuePicker();
    }
    
    function closeConfig() {
      document.getElementById('config-modal').style.display = 'none';
      configNodeId = null;
    }
    
    function applyConfig() {
      const node = nodes.find(n => n.id === configNodeId);
      if (!node) { closeConfig(); return; }
    
      node.label = document.getElementById('cfg-label').value;
    
      if (node.type === 'issue') {
        node.issue_id = document.getElementById('cfg-issue-id').value || null;
        var tplTitle = document.getElementById('cfg-tpl-title').value.trim();
        if (tplTitle) {
          node.config = node.config || {};
          node.config.title = tplTitle;
          node.config.description = document.getElementById('cfg-tpl-desc').value.trim();
          node.config.labels = document.getElementById('cfg-tpl-labels').value.split(',').map(function(s) { return s.trim(); }).filter(Boolean);
        } else {
          if (node.config) { delete node.config.title; delete node.config.description; delete node.config.labels; }
        }
      }
      if (node.type === 'loop') {
        node.loop_max_retries = parseInt(document.getElementById('cfg-max-retries').value) || 5;
        node.loop_condition = document.getElementById('cfg-loop-cond').value || null;
      }
      if (node.type === 'human_gate') {
        node.config = node.config || {};
        node.config.review_mode = document.getElementById('cfg-review-mode').value || null;
        node.config.instructions = document.getElementById('cfg-instructions').value;
        var hgTimeout = document.getElementById('cfg-auto-timeout').value;
        node.config.auto_approve_timeout_ms = hgTimeout ? parseInt(hgTimeout) : null;
        node.config.auto_approve_condition = document.getElementById('cfg-auto-cond').value || null;
        node.config.auto_approve_webhook_url = document.getElementById('cfg-webhook-url').value || null;
      }
      if (node.type === 'quality_gate') {
        node.config = node.config || {};
        node.config.checks = document.getElementById('cfg-checks').value.split(',').map(s => s.trim()).filter(Boolean);
        // Parse check_commands from "name:command" lines
        var cmdsText = document.getElementById('cfg-check-cmds').value.trim();
        var checkCmds = {};
        if (cmdsText) {
          cmdsText.split('\n').forEach(function(line) {
            var idx = line.indexOf(':');
            if (idx > 0) checkCmds[line.slice(0, idx).trim()] = line.slice(idx + 1).trim();
          });
        }
        node.config.check_commands = checkCmds;
        var qgTimeout = document.getElementById('cfg-qg-auto-timeout').value;
        node.config.auto_approve_timeout_ms = qgTimeout ? parseInt(qgTimeout) : null;
        node.config.auto_approve_condition = document.getElementById('cfg-qg-auto-cond').value || null;
        node.config.auto_approve_webhook_url = document.getElementById('cfg-qg-webhook-url').value || null;
      }
      if (node.type === 'kb_sync') {
        node.config = node.config || {};
        node.config.kb_type = document.getElementById('cfg-kb-type').value;
        node.config.vault_path = document.getElementById('cfg-kb-vault-path').value;
        node.config.subfolder = document.getElementById('cfg-kb-subfolder').value;
      }
    
      if (node.type === 'integration') {
        node.config = node.config || {};
        node.config.integration_type = document.getElementById('cfg-int-type').value;
        node.config.action = readIntegrationAction();
        node.config.action_config = readIntegrationActionConfig();
        node.config.max_retries = parseInt(document.getElementById('cfg-int-retries').value) || 3;
      }
    
      markDirty();
      render();
      closeConfig();
    }
    
    async function loadIssuePicker() {
      const res = await fetch('/board/api/issues');
      const data = await res.json();
      const issues = data.issues || [];
      const picker = document.getElementById('issue-picker');
      if (!picker) return;
      picker.style.maxHeight = '160px';
      picker.style.overflowY = 'auto';
      const currentIssueId = document.getElementById('cfg-issue-id').value;
      picker.innerHTML = issues.slice(0, 30).map(i => {
        const active = i.id === currentIssueId ? 'border-color:var(--accent);' : '';
        return `<button class="btn btn-sm btn-ghost" style="margin:2px;${active}" onclick="document.getElementById('cfg-issue-id').value='${i.id}'; document.querySelectorAll('#issue-picker .btn').forEach(b=>b.style.borderColor=''); this.style.borderColor='var(--accent)'">${esc(i.identifier)}: ${esc(i.title).substring(0,40)}</button>`;
      }).join('');
    }
    
    // --- Integration node canvas metadata ---
    function integrationNodeMeta(n) {
      var cfg = n.config || {};
      var type = cfg.integration_type || 'jira';
      var action = cfg.action || '';
      var typeLabels = { jira: 'Jira', gitlab_ci: 'GitLab CI', confluence: 'Confluence' };
      var label = typeLabels[type] || type;
      if (!action) return label;
      var actionLabels = {
        create: 'Create', update: 'Update', transition: 'Transition', sync_status: 'Sync',
        trigger: 'Trigger', poll: 'Poll', get_status: 'Status',
        create_page: 'Create', update_page: 'Update', get_page: 'Read'
      };
      var detail = actionLabels[action] || action;
      var extra = '';
      var ac = cfg.action_config || {};
      if (type === 'jira' && (action === 'create' || action === 'update')) extra = ac.issue_type || '';
      if (type === 'gitlab_ci' && action === 'trigger') extra = ac.ref || '';
      return label + ' · ' + detail + (extra ? ' → ' + esc(extra) : '');
    }
    
    // --- Integration node dynamic config forms ---
    
    const INTEGRATION_META = {
      jira: {
        help: 'Creates, updates, or transitions Jira issues. Credentials are configured in <a href="/board/settings">Settings</a>.',
        actions: ['create', 'update', 'transition', 'sync_status'],
        actionLabels: { create: 'Create Issue', update: 'Update Issue', transition: 'Transition Issue', sync_status: 'Sync Status' },
        fields: function(action, ac) {
          var h = '';
          if (action === 'create' || action === 'update') {
            h += '<div class="form-group"><label>Issue Type</label><select id="cfg-int-issue-type">' +
              ['Task','Story','Bug','Epic'].map(function(t) { return '<option value="' + t + '"' + ((ac.issue_type||'Task')===t?' selected':'') + '>' + t + '</option>'; }).join('') +
              '</select></div>';
            h += '<div class="form-group"><label>Field Mapping (JSON)</label><textarea id="cfg-int-field-mapping" rows="3" placeholder=\'{"summary":"title","description":"description"}\'>' + esc(JSON.stringify(ac.field_mapping||{},null,2)) + '</textarea><small style="color:var(--text-muted);font-size:0.72rem">Maps Symphony fields to Jira fields.</small></div>';
          }
          if (action === 'transition') {
            h += '<div class="form-group"><label>Jira Key</label><input id="cfg-int-jira-key" value="' + esc(ac.jira_key||'') + '" placeholder="PROJ-123 or leave blank for auto"></div>';
            h += '<div class="form-group"><label>Transition ID</label><input id="cfg-int-transition-id" value="' + esc(ac.transition_id||'') + '" placeholder="e.g. 31"></div>';
          }
          if (action === 'sync_status') {
            h += '<div class="form-group"><label>Jira Key</label><input id="cfg-int-jira-key" value="' + esc(ac.jira_key||'') + '" placeholder="PROJ-123"></div>';
          }
          return h;
        },
        read: function(action) {
          var c = {};
          if (action === 'create' || action === 'update') {
            c.issue_type = (document.getElementById('cfg-int-issue-type')||{}).value || 'Task';
            try { c.field_mapping = JSON.parse((document.getElementById('cfg-int-field-mapping')||{}).value||'{}'); } catch(e) { c.field_mapping = {}; }
          }
          if (action === 'transition') {
            c.jira_key = (document.getElementById('cfg-int-jira-key')||{}).value||'';
            c.transition_id = (document.getElementById('cfg-int-transition-id')||{}).value||'';
          }
          if (action === 'sync_status') {
            c.jira_key = (document.getElementById('cfg-int-jira-key')||{}).value||'';
          }
          return c;
        }
      },
      gitlab_ci: {
        help: 'Triggers a GitLab CI pipeline and waits for completion. Use as a quality gate. Credentials are configured in <a href="/board/settings">Settings</a>.',
        actions: ['trigger', 'poll', 'get_status'],
        actionLabels: { trigger: 'Trigger & Poll', poll: 'Poll Status', get_status: 'Get Status' },
        fields: function(action, ac) {
          var h = '';
          h += '<div class="form-group"><label>Branch / Ref</label><input id="cfg-int-ref" value="' + esc(ac.ref||'') + '" placeholder="main (uses Settings default if blank)"></div>';
          if (action === 'trigger') {
            h += '<div class="form-group"><label>Pipeline Variables (JSON)</label><textarea id="cfg-int-variables" rows="3" placeholder=\'{"DEPLOY_ENV":"staging"}\'>' + esc(JSON.stringify(ac.variables||{},null,2)) + '</textarea><small style="color:var(--text-muted);font-size:0.72rem">Key-value pairs passed to the CI pipeline.</small></div>';
          }
          if (action === 'poll' || action === 'get_status') {
            h += '<div class="form-group"><label>Pipeline ID</label><input id="cfg-int-pipeline-id" value="' + esc(ac.pipeline_id||'') + '" placeholder="Auto from trigger, or enter manually"></div>';
          }
          return h;
        },
        read: function(action) {
          var c = {};
          c.ref = (document.getElementById('cfg-int-ref')||{}).value||'';
          if (action === 'trigger') {
            try { c.variables = JSON.parse((document.getElementById('cfg-int-variables')||{}).value||'{}'); } catch(e) { c.variables = {}; }
          }
          if (action === 'poll' || action === 'get_status') {
            c.pipeline_id = (document.getElementById('cfg-int-pipeline-id')||{}).value||'';
          }
          return c;
        }
      },
      confluence: {
        help: 'Creates or updates Confluence pages for documentation. Credentials are configured in <a href="/board/settings">Settings</a>.',
        actions: ['create_page', 'update_page', 'get_page'],
        actionLabels: { create_page: 'Create Page', update_page: 'Update Page', get_page: 'Get Page' },
        fields: function(action, ac) {
          var h = '';
          if (action === 'create_page') {
            h += '<div class="form-group"><label>Parent Page ID</label><input id="cfg-int-parent-page" value="' + esc(ac.parent_page_id||'') + '" placeholder="Blank = Settings default"></div>';
          }
          if (action === 'update_page' || action === 'get_page') {
            h += '<div class="form-group"><label>Page ID</label><input id="cfg-int-page-id" value="' + esc(ac.page_id||'') + '" placeholder="Confluence page ID"></div>';
          }
          return h;
        },
        read: function(action) {
          var c = {};
          if (action === 'create_page') {
            c.parent_page_id = (document.getElementById('cfg-int-parent-page')||{}).value||'';
          }
          if (action === 'update_page' || action === 'get_page') {
            c.page_id = (document.getElementById('cfg-int-page-id')||{}).value||'';
          }
          return c;
        }
      }
    };
    
    function updateIntegrationFields(savedAction, savedConfig) {
      var type = document.getElementById('cfg-int-type').value;
      var meta = INTEGRATION_META[type];
      if (!meta) return;
    
      var helpEl = document.getElementById('cfg-int-help');
      var fieldsEl = document.getElementById('cfg-int-fields');
    
      // Help box
      helpEl.innerHTML = '<div class="integration-help">' + meta.help + '</div>';
    
      // Action dropdown + action-specific fields
      var ac = savedConfig || {};
      var currentAction = savedAction || meta.actions[0];
      var h = '<div class="form-group"><label>Action</label><select id="cfg-int-action" onchange="updateIntegrationFields()">';
      meta.actions.forEach(function(a) {
        h += '<option value="' + a + '"' + (currentAction === a ? ' selected' : '') + '>' + (meta.actionLabels[a]||a) + '</option>';
      });
      h += '</select></div>';
    
      var selectedAction = currentAction;
      h += meta.fields(selectedAction, ac);
    
      fieldsEl.innerHTML = h;
    }
    
    function readIntegrationAction() {
      var el = document.getElementById('cfg-int-action');
      return el ? el.value : '';
    }
    
    function readIntegrationActionConfig() {
      var type = document.getElementById('cfg-int-type').value;
      var action = readIntegrationAction();
      var meta = INTEGRATION_META[type];
      return meta ? meta.read(action) : {};
    }
    """
  end

  defp modal_utils_js do
    ~S"""
    loadAllSkills();
    
    function ciAiDraftApply(draft) {
      var skillIds = draft.skill_ids || [];
      if (skillIds.length > 0) {
        renderSkillPicker('ci-skills', skillIds, []);
        document.getElementById('ci-skills').style.display = '';
      }
    }
    
    async function openCreateIssueModal() {
      ciReset();
      renderSkillPicker('ci-skills', [], []);
      document.getElementById('ci-skills').style.display = 'none';
      await Promise.all([ciPopulateStates(), ciPopulateProducts(), ciPopulateProjects()]);
      document.getElementById('ci-modal').style.display = 'flex';
      setTimeout(() => document.getElementById('ci-title').focus(), 100);
    }
    
    function closeCreateIssueModal() {
      document.getElementById('ci-modal').style.display = 'none';
    }
    
    async function submitCreateIssue(e) {
      e.preventDefault();
      const d = ciCollectData();
      if (!d.title) return;
      const skills = getSelectedSkills('ci-skills');
      const data = Object.assign({}, d, {
        priority: parseInt(d.priority) || 0,
        labels: (d.labels || '').split(',').map(l => l.trim()).filter(Boolean),
        skill_ids: skills.skill_ids,
        skill_group_ids: skills.skill_group_ids
      });
    
      const res = await fetch('/board/api/issues', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data)
      });
      if (!res.ok) { showToast('Failed to create issue', { type: 'error' }); return; }
      const issue = await res.json();
      showToast('Issue created: ' + issue.identifier, { type: 'success' });
    
      // Link to the config modal's issue field
      const idField = document.getElementById('cfg-issue-id');
      if (idField) idField.value = issue.id;
    
      // Update node label if still default
      const labelField = document.getElementById('cfg-label');
      if (labelField) {
        const node = nodes.find(n => n.id === configNodeId);
        if (node && node.label === (NODE_LABELS['issue'] || 'Issue')) {
          labelField.value = issue.title;
        }
      }
    
      closeCreateIssueModal();
      await loadIssuePicker();
    }
    
    """
  end

  defp save_js do
    ~S"""
    // ══════════════════════════════════
    // Save
    // ══════════════════════════════════
    function markDirty() { dirty = true; }
    
    window.addEventListener('beforeunload', e => {
      if (dirty) { e.preventDefault(); e.returnValue = ''; }
    });
    
    async function savePipeline() {
      const name = document.getElementById('pipeline-name').value;
      const description = document.getElementById('pipeline-desc').value;
      const product_id = document.getElementById('pipeline-product').value || null;
      const res = await fetch('/board/api/pipelines/' + pipeline.id, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, description, product_id, nodes, edges, settings: pipeline.settings })
      });
      if (res.ok) {
        dirty = false;
        document.title = name + ' — Symphony Pipeline';
        showToast('Pipeline saved', { type: 'success' });
      } else {
        const err = await res.json().catch(() => ({}));
        if (err.error === 'pipeline_running') {
          showToast('Cannot edit graph while pipeline is running', { type: 'error' });
        } else {
          showToast('Failed to save pipeline', { type: 'error' });
        }
      }
    }
    
    // Auto-save on Ctrl+S
    document.addEventListener('keydown', e => {
      const inInput = document.activeElement.tagName === 'INPUT' || document.activeElement.tagName === 'TEXTAREA';
      if ((e.ctrlKey || e.metaKey) && e.key === 's') {
        e.preventDefault();
        savePipeline();
      }
      if ((e.ctrlKey || e.metaKey) && e.key === 'z' && !e.shiftKey && !inInput) {
        e.preventDefault();
        undo();
      }
      if ((e.ctrlKey || e.metaKey) && (e.key === 'y' || (e.shiftKey && (e.key === 'z' || e.key === 'Z'))) && !inInput) {
        e.preventDefault();
        redo();
      }
      if (e.key === 'Delete' || e.key === 'Backspace') {
        if (selectedNodeId && !execMode && !inInput) {
          deleteNode(selectedNodeId);
        }
      }
      if (e.key === 'Escape') {
        selectedNodeId = null;
        closeConfig();
        closeHelpModal();
        render();
      }
      if (e.key === '?' && !inInput) {
        toggleHelpModal();
      }
    });
    
    """
  end

  defp execution_js do
    ~S"""
    // ══════════════════════════════════
    // Execution mode
    // ══════════════════════════════════
    async function toggleExecution() {
      if (execMode) {
        // Cancel the active run on the server if still running
        if (activeRun && activeRun.id && !['completed', 'failed', 'cancelled'].includes(activeRun.status)) {
          try {
            await fetch('/board/api/pipelines/' + pipeline.id + '/runs/' + activeRun.id + '/cancel', { method: 'POST' });
          } catch(e) { /* ignore */ }
        }
        // Stop execution mode
        execMode = false;
        activeRun = null;
        if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
        window._gateContextLoadedFor = null;
        window._sidebarNodeState = null;
        document.getElementById('run-btn').innerHTML = '&#9654; Run';
        document.querySelector('.exec-sidebar')?.classList.remove('open');
        document.getElementById('palette').style.display = 'flex';
        render();
        return;
      }
    
      // Save first
      if (dirty) await savePipeline();
    
      // Show product picker dialog
      showRunProductPicker();
    }
    
    async function showRunProductPicker() {
      // Fetch products and projects in parallel
      var [productsRes, projectsRes] = await Promise.all([
        fetch('/board/api/products'),
        fetch('/board/api/projects')
      ]);
      var productsData = productsRes.ok ? await productsRes.json() : {};
      var products = productsData.products || [];
      var projectsData = projectsRes.ok ? await projectsRes.json() : {};
      var projects = projectsData.projects || [];
    
      // If pipeline has a default product, pre-select it
      var defaultProductId = pipeline.product_id || '';
    
      // If nothing to pick from, still show modal for description input
    
    
      // Build modal
      var overlay = document.createElement('div');
      overlay.id = 'run-product-overlay';
      overlay.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,0.6);z-index:9999;display:flex;align-items:center;justify-content:center';
    
      var selectStyle = 'width:100%;padding:8px;background:var(--bg-tertiary);color:var(--text-primary);border:1px solid var(--border);border-radius:6px;font-size:0.9rem;margin-bottom:16px';
    
      var productOpts = '<option value="">(No product — select a project instead)</option>' +
        products.map(function(p) {
          var sel = p.id === defaultProductId ? ' selected' : '';
          return '<option value="' + p.id + '"' + sel + '>' + esc(p.name) + '</option>';
        }).join('');
    
      var projectOpts = '<option value="">(No project — generic run)</option>' +
        projects.map(function(p) {
          return '<option value="' + p.id + '">' + esc(p.name) + (p.path ? ' — ' + esc(p.path) : '') + '</option>';
        }).join('');
    
      var textareaStyle = 'width:100%;padding:8px;background:var(--bg-tertiary);color:var(--text-primary);border:1px solid var(--border);border-radius:6px;font-size:0.85rem;margin-bottom:16px;resize:vertical;font-family:inherit';
    
      overlay.innerHTML = '<div style="background:var(--bg-secondary);border:1px solid var(--border);border-radius:12px;padding:24px;min-width:400px;max-width:560px">' +
        '<h3 style="margin:0 0 16px 0;color:var(--text-primary);font-size:1rem">Start Pipeline Run</h3>' +
        '<label style="display:block;margin-bottom:4px;color:var(--text-secondary);font-size:0.85rem">' + (pipeline.name.indexOf('UI') >= 0 ? 'Describe the UI you want' : 'What needs to be done?') + '</label>' +
        '<textarea id="run-input-description" rows="5" style="' + textareaStyle + '" placeholder="' + (pipeline.name.indexOf('UI') >= 0 ?
          'Describe the UI style, mood, and layout you want...\\n\\nE.g.: Build a dark glassmorphism dashboard with neon accent colors, 3D card tilt effects, asymmetric grid layout, and bold typography. Think futuristic terminal meets luxury brand.'
          : 'Describe the feature, bug fix, or task...\\n\\nE.g.: Add three new boolean fields (anonymize_name, anonymize_email, anonymize_phone) to the tenant model. These come in at the start of the ETL pipeline and control whether PII is stripped before loading.'
        ) + '"></textarea>' +
        '<label style="display:block;margin-bottom:4px;color:var(--text-secondary);font-size:0.85rem">Product</label>' +
        '<select id="run-product-select" style="' + selectStyle + '" onchange="window._onRunProductChange()">' + productOpts + '</select>' +
        '<div id="run-project-row">' +
        '<label style="display:block;margin-bottom:4px;color:var(--text-secondary);font-size:0.85rem">Project</label>' +
        '<select id="run-project-select" style="' + selectStyle + '">' + projectOpts + '</select>' +
        '</div>' +
        '<div style="display:flex;gap:8px;justify-content:flex-end">' +
        '<button class="btn btn-sm btn-ghost" onclick="document.getElementById(\'run-product-overlay\').remove()">Cancel</button>' +
        '<button class="btn btn-sm btn-primary" onclick="confirmRunStart()">Start Run</button>' +
        '</div></div>';
    
      document.body.appendChild(overlay);
    
      // Toggle project row visibility based on product selection
      window._onRunProductChange = function() {
        var productSel = document.getElementById('run-product-select');
        var projectRow = document.getElementById('run-project-row');
        if (productSel.value) {
          projectRow.style.display = 'none';
        } else {
          projectRow.style.display = 'block';
        }
      };
      // Set initial visibility
      window._onRunProductChange();
    
      overlay.addEventListener('click', function(e) { if (e.target === overlay) overlay.remove(); });
    }
    
    async function confirmRunStart() {
      var productSelect = document.getElementById('run-product-select');
      var projectSelect = document.getElementById('run-project-select');
      var descInput = document.getElementById('run-input-description');
      var productId = productSelect ? productSelect.value : null;
      var projectId = (!productId && projectSelect) ? projectSelect.value : null;
      var inputDescription = descInput ? descInput.value.trim() : '';
      var overlay = document.getElementById('run-product-overlay');
      if (overlay) overlay.remove();
      startRunWithScope(productId || null, projectId || null, inputDescription || null);
    }
    
    async function startRunWithScope(productId, projectId, inputDescription) {
      var body = {};
      if (productId) body.product_id = productId;
      if (projectId) body.project_id = projectId;
      if (inputDescription) body.input_description = inputDescription;
    
      const res = await fetch('/board/api/pipelines/' + pipeline.id + '/run', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
      });
      if (!res.ok) {
        var err = await res.json().catch(function() { return {}; });
        showToast(err.error === 'already_running' ? 'Pipeline already has an active run' : 'Failed to start run', { type: 'error' });
        return;
      }
      activeRun = await res.json();
      var scope = productId ? '' : (projectId ? ' (project)' : ' (no scope)');
      showToast('Pipeline run started' + scope, { type: 'success' });
    
      // Create exec sidebar BEFORE entering exec mode
      if (!document.getElementById('exec-sidebar')) {
        const sidebar = document.createElement('div');
        sidebar.className = 'exec-sidebar';
        sidebar.id = 'exec-sidebar';
        document.body.appendChild(sidebar);
      }
    
      execMode = true;
      document.getElementById('run-btn').innerHTML = '&#9632; Stop';
      document.getElementById('palette').style.display = 'none';
    
      render();
      pollTimer = setInterval(pollRunStatus, 2000);
    }
    
    async function pollRunStatus() {
      if (!activeRun) return;
      try {
        const res = await fetch('/board/api/pipelines/' + pipeline.id + '/runs/' + activeRun.id);
        if (res.ok) {
          activeRun = await res.json();
          render();
          if (activeRun.status === 'completed' || activeRun.status === 'failed' || activeRun.status === 'cancelled') {
            clearInterval(pollTimer);
            pollTimer = null;
          }
          // Update sidebar if open — but only if node state changed
          if (selectedNodeId) {
            var newState = (activeRun.node_states || {})[selectedNodeId] || 'pending';
            if (newState !== window._sidebarNodeState) {
              window._sidebarNodeState = newState;
              window._gateContextLoadedFor = null;
              showExecSidebar(selectedNodeId);
            }
          }
        }
      } catch(e) {}
    }
    
    function closeExecSidebar() {
      const sidebar = document.getElementById('exec-sidebar');
      if (sidebar) sidebar.classList.remove('open');
      selectedNodeId = null;
      window._gateContextLoadedFor = null;
      window._sidebarNodeState = null;
      render();
    }
    
    function showExecSidebar(nodeId) {
      const sidebar = document.getElementById('exec-sidebar');
      if (!sidebar || !activeRun) return;
      sidebar.classList.add('open');
    
      const node = nodes.find(n => n.id === nodeId);
      if (!node) { sidebar.innerHTML = ''; return; }
    
      const state = (activeRun.node_states || {})[nodeId] || 'pending';
      window._sidebarNodeState = state;
      const attempts = (activeRun.node_attempts || {})[nodeId] || 0;
      const color = NODE_COLORS[node.type] || '#8b949e';
    
      let html = `
        <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:4px">
          <h3 style="border-left:3px solid ${color}; padding-left:8px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; max-width:400px; margin:0">${esc(node.label)}</h3>
          <button class="btn-icon" onclick="closeExecSidebar()" title="Close">&times;</button>
        </div>
        <div style="margin-top:8px; font-size:0.85rem; color:var(--text-muted)">
          State: <strong style="color:var(--text-primary)">${state}</strong><br>
          Attempts: ${attempts}
        </div>`;
    
      // Gate actions: Approve/Reject/Hold
      if ((state === 'waiting_gate' || state === 'on_hold') && (node.type === 'human_gate' || node.type === 'quality_gate')) {
        html += '<div class="gate-action">';
        if (state === 'on_hold') {
          html += '<button class="btn btn-sm btn-primary" onclick="gateDecision(\'' + nodeId + '\', \'approve\')">Resume & Approve</button>';
          html += '<button class="btn btn-sm btn-ghost" style="color:var(--red)" onclick="gateDecision(\'' + nodeId + '\', \'reject\')">Resume & Reject</button>';
          html += '<div style="margin-top:6px;font-size:0.75rem;color:var(--yellow)">Gate is on hold</div>';
        } else {
          html += '<button class="btn btn-sm btn-primary" onclick="gateDecision(\'' + nodeId + '\', \'approve\')">Approve</button>';
          html += '<button class="btn btn-sm btn-ghost" style="color:var(--red)" onclick="gateDecision(\'' + nodeId + '\', \'reject\')">Reject</button>';
          html += '<button class="btn btn-sm btn-ghost" style="color:var(--yellow)" onclick="gateDecision(\'' + nodeId + '\', \'hold\')">Hold</button>';
        }
        html += '</div>';
        html += '<textarea class="gate-feedback" id="gate-feedback" placeholder="Feedback (will be injected into issue on reject)" rows="3"></textarea>';
      }
    
      if (state === 'waiting_gate' && node.type === 'kb_sync') {
        html += '<div class="gate-action">';
        html += '<button class="btn btn-sm btn-primary" onclick="kbSyncSendAndApprove(\'' + nodeId + '\')">Send to KB</button>';
        html += '<button class="btn btn-sm btn-ghost" onclick="gateDecision(\'' + nodeId + '\', \'approve\')">Skip</button>';
        html += '</div>';
        html += '<div style="margin-top:8px;font-size:0.8rem;color:var(--text-muted)">Send predecessor issue reports to Knowledge Base, or skip to continue.</div>';
      }
    
      // Issue node — link to issue
      if (node.type === 'issue') {
        var issueId = node.issue_id || ((activeRun.node_issue_ids || {})[nodeId]);
        if (issueId) {
          html += '<div style="margin-top:12px"><a href="/board/issues/' + issueId + '" class="btn btn-sm btn-ghost" style="text-decoration:none">View Issue</a></div>';
          if (state === 'running') {
            html += '<div style="margin-top:4px;font-size:0.8rem;color:var(--text-muted)">Issue dispatched. Waiting for completion...</div>';
          }
        }
      }
    
      // Force-complete button for stuck/failed nodes
      if (state === 'failed' || state === 'running' || state === 'on_hold') {
        html += '<div style="margin-top:12px;padding-top:8px;border-top:1px solid var(--border)">';
        html += '<button class="btn btn-sm btn-ghost" style="color:var(--yellow)" onclick="forceCompleteNode(\'' + nodeId + '\')">Force Complete</button>';
        html += '<div style="font-size:0.72rem;color:var(--text-muted);margin-top:4px">Skip this node and advance the pipeline.</div>';
        html += '</div>';
      }
    
      // Load gate context asynchronously for gate nodes (only once per node)
      sidebar.innerHTML = html;
      if ((node.type === 'human_gate' || node.type === 'quality_gate') && (state === 'waiting_gate' || state === 'on_hold')) {
        if (window._gateContextLoadedFor !== nodeId) {
          window._gateContextLoadedFor = nodeId;
          loadGateContext(nodeId);
        }
      } else {
        window._gateContextLoadedFor = null;
      }
    }
    
    function renderMarkdown(text) {
      if (!text) return '';
      return esc(text)
        .replace(/^### (.+)$/gm, '<h4 style="margin:8px 0 4px;font-size:0.82rem;color:var(--text-primary)">$1</h4>')
        .replace(/^## (.+)$/gm, '<h3 style="margin:10px 0 4px;font-size:0.88rem;color:var(--text-primary)">$1</h3>')
        .replace(/^# (.+)$/gm, '<h2 style="margin:12px 0 6px;font-size:0.95rem;color:var(--text-primary)">$1</h2>')
        .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
        .replace(/`([^`]+)`/g, '<code style="background:var(--bg-tertiary);padding:1px 4px;border-radius:3px;font-size:0.78rem">$1</code>')
        .replace(/^- (.+)$/gm, '<div style="padding-left:12px">&#8226; $1</div>')
        .replace(/^(\d+)\. (.+)$/gm, '<div style="padding-left:12px">$1. $2</div>')
        .replace(/\n/g, '<br>');
    }
    
    async function loadGateContext(nodeId) {
      try {
        var res = await fetch('/board/api/pipelines/' + pipeline.id + '/runs/' + activeRun.id + '/gate-context/' + nodeId);
        if (!res.ok) return;
        var ctx = await res.json();
        var sidebar = document.getElementById('exec-sidebar');
        if (!sidebar) return;
    
        var contextHtml = '';
        var mode = ctx.review_mode || 'default';
    
        // Gate prompt banner — always shown
        if (ctx.gate_prompt) {
          contextHtml += '<div class="gate-prompt-banner">';
          contextHtml += '<div style="font-size:0.7rem;text-transform:uppercase;letter-spacing:0.5px;color:var(--accent);margin-bottom:4px">Decision Required</div>';
          contextHtml += '<div style="font-size:0.85rem;color:var(--text-primary);line-height:1.4">' + esc(ctx.gate_prompt) + '</div>';
          contextHtml += '</div>';
        }
    
        // Instructions — always available but collapsible when prompt exists
        if (ctx.instructions) {
          if (ctx.gate_prompt) {
            contextHtml += '<details style="margin-top:8px">';
            contextHtml += '<summary class="accordion-header">Review Instructions</summary>';
            contextHtml += '<div class="accordion-body">' + esc(ctx.instructions) + '</div>';
            contextHtml += '</details>';
          } else {
            contextHtml += '<div class="gate-prompt-banner">';
            contextHtml += '<div style="font-size:0.7rem;text-transform:uppercase;letter-spacing:0.5px;color:var(--text-muted);margin-bottom:4px">Review Instructions</div>';
            contextHtml += '<div style="font-size:0.85rem;color:var(--text-primary);line-height:1.4">' + esc(ctx.instructions) + '</div>';
            contextHtml += '</div>';
          }
        }
    
        // Mode-specific content
        if (mode === 'plan_review') {
          contextHtml += renderPlanReview(ctx);
        } else if (mode === 'code_review') {
          contextHtml += renderCodeReview(ctx);
        } else if (mode === 'findings_review') {
          contextHtml += renderFindingsReview(ctx);
        } else {
          contextHtml += renderDefaultReview(ctx);
        }
    
        // Feedback history thread — always shown
        contextHtml += renderFeedbackHistory(ctx);
    
        if (contextHtml) {
          var contextDiv = document.createElement('div');
          contextDiv.innerHTML = contextHtml;
          sidebar.appendChild(contextDiv);
        }
    
        if (mode === 'findings_review' || mode === 'default') {
          updateFindingsSummary();
        }
      } catch(e) {}
    }
    
    // ── Plan Review: show rendered implementation plan ──
    function renderPlanReview(ctx) {
      var html = '';
      if (!ctx.predecessor_issues || ctx.predecessor_issues.length === 0) {
        html += '<div style="padding:12px;color:var(--text-muted);font-size:0.82rem">Waiting for plan...</div>';
        return html;
      }
      ctx.predecessor_issues.forEach(function(issue) {
        // Plan is in result_text (agent output)
        var planText = issue.result_text || '';
        if (!planText && issue.reports) {
          // Fallback: check reports for plan content
          issue.reports.forEach(function(r) { if (r.content && !planText) planText = r.content; });
        }
        if (planText) {
          html += '<div style="margin-top:10px">';
          html += '<div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:6px">';
          html += '<strong style="font-size:0.75rem;color:var(--text-muted)">' + esc(issue.identifier) + ' — ' + esc(issue.title) + '</strong>';
          html += '<a href="' + esc(issue.url) + '" class="btn btn-sm btn-ghost" style="font-size:0.68rem;text-decoration:none">Full Issue</a>';
          html += '</div>';
          html += '<div class="plan-review-content">' + renderMarkdown(planText) + '</div>';
          html += '</div>';
        }
      });
      if (!html) {
        html += '<div style="padding:12px;color:var(--text-muted);font-size:0.82rem">No plan content found in predecessor issues.</div>';
      }
      return html;
    }
    
    // ── Code Review: show change summaries and reports ──
    function renderCodeReview(ctx) {
      var html = '';
      if (!ctx.predecessor_issues || ctx.predecessor_issues.length === 0) {
        html += '<div style="padding:12px;color:var(--text-muted);font-size:0.82rem">Waiting for implementation...</div>';
        return html;
      }
      ctx.predecessor_issues.forEach(function(issue) {
        var stateColor = issue.state === 'Done' ? 'var(--green)' : issue.state === 'Review' ? 'var(--yellow)' : 'var(--text-muted)';
        html += '<div style="margin-top:10px">';
        html += '<div style="display:flex;align-items:center;gap:8px;margin-bottom:6px">';
        html += '<strong style="font-size:0.75rem;color:var(--accent)">' + esc(issue.identifier) + '</strong>';
        html += '<span style="font-size:0.8rem;color:var(--text-primary)">' + esc(issue.title) + '</span>';
        html += '<span style="color:' + stateColor + ';font-size:0.68rem">' + esc(issue.state) + '</span>';
        html += '<a href="' + esc(issue.url) + '" class="btn btn-sm btn-ghost" style="font-size:0.68rem;text-decoration:none;margin-left:auto">Full Issue</a>';
        html += '</div>';
    
        // Agent result — typically contains change summary
        if (issue.result_text) {
          html += '<div class="report-section">';
          html += '<div class="report-section-title">Changes Summary</div>';
          html += '<div class="report-content">' + renderMarkdown(issue.result_text) + '</div>';
          html += '</div>';
        }
    
        // Report files — rendered as markdown
        if (issue.reports && issue.reports.length > 0) {
          issue.reports.forEach(function(report) {
            html += '<div class="report-section">';
            html += '<div class="report-section-title">' + esc(report.name) + '</div>';
            html += '<div class="report-content">' + renderMarkdown(report.content) + '</div>';
            html += '</div>';
          });
        }
        html += '</div>';
      });
      return html;
    }
    
    // ── Findings Review: per-finding accept/reject cards ──
    function renderFindingsReview(ctx) {
      var html = '';
      var allFindings = collectFindings(ctx);
    
      if (allFindings.length === 0) {
        // Fallback: check predecessor issue reports for findings info
        if (ctx.predecessor_issues && ctx.predecessor_issues.length > 0) {
          html += '<div style="padding:12px;color:var(--text-muted);font-size:0.82rem">No structured findings. Scan result:</div>';
          ctx.predecessor_issues.forEach(function(issue) {
            if (issue.result_text) {
              html += '<div class="report-section">';
              html += '<div class="report-section-title">' + esc(issue.identifier) + ' — ' + esc(issue.title) + '</div>';
              html += '<div class="report-content">' + renderMarkdown(issue.result_text) + '</div>';
              html += '</div>';
            }
          });
        } else {
          html += '<div style="padding:12px;color:var(--text-muted);font-size:0.82rem">No findings from scan.</div>';
        }
        return html;
      }
    
      html += renderFindingCards(allFindings);
      return html;
    }
    
    // ── Default: show everything (backwards compatible) ──
    function renderDefaultReview(ctx) {
      var html = '';
    
      // Quality checks
      if (ctx.checks && ctx.checks.length > 0) {
        html += '<div style="margin-top:8px;font-size:0.82rem">';
        html += '<strong style="font-size:0.72rem;color:var(--text-muted);display:block;margin-bottom:4px">Quality Checks</strong>';
        ctx.checks.forEach(function(c) {
          html += '<span style="display:inline-block;padding:2px 6px;margin:2px;background:var(--bg-secondary);border:1px solid var(--border);border-radius:4px;font-size:0.75rem">' + esc(c) + '</span>';
        });
        html += '</div>';
      }
    
      // Predecessor issues — expandable accordions
      if (ctx.predecessor_issues && ctx.predecessor_issues.length > 0) {
        html += '<div style="margin-top:10px">';
        html += '<strong style="font-size:0.72rem;color:var(--text-muted);display:block;margin-bottom:6px">Predecessor Issues (' + ctx.predecessor_issues.length + ')</strong>';
        ctx.predecessor_issues.forEach(function(issue, idx) {
          html += renderIssueAccordion(issue, idx);
        });
        html += '</div>';
      }
    
      // Findings
      var allFindings = collectFindings(ctx);
      if (allFindings.length > 0) {
        html += renderFindingCards(allFindings);
      }
    
      return html;
    }
    
    // ── Shared: collect findings from predecessor outputs ──
    function collectFindings(ctx) {
      var allFindings = [];
      if (ctx.predecessor_outputs) {
        Object.keys(ctx.predecessor_outputs).forEach(function(predId) {
          var output = ctx.predecessor_outputs[predId];
          if (output && output.findings && Array.isArray(output.findings)) {
            output.findings.forEach(function(f) { allFindings.push(f); });
          }
        });
      }
      return allFindings;
    }
    
    // ── Shared: render finding cards with accept/reject buttons ──
    function renderFindingCards(findings) {
      var html = '<div style="margin-top:12px">';
      html += '<div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:6px">';
      html += '<strong style="font-size:0.72rem;color:var(--text-muted)">Findings (' + findings.length + ')</strong>';
      html += '<span style="display:flex;gap:4px"><button class="btn btn-sm btn-ghost" style="font-size:0.68rem;color:var(--green)" onclick="setAllFindings(true)">Accept All</button><button class="btn btn-sm btn-ghost" style="font-size:0.68rem;color:var(--red)" onclick="setAllFindings(false)">Reject All</button></span>';
      html += '</div>';
      findings.forEach(function(f) {
        var sevColor = f.severity === 'critical' ? 'var(--red)' : f.severity === 'high' ? '#f0883e' : f.severity === 'medium' ? 'var(--yellow)' : 'var(--text-muted)';
        var fid = esc(f.id);
        html += '<div class="finding-card" data-finding-id="' + fid + '" data-decision="accepted">';
        html += '<div class="finding-header">';
        html += '<div style="flex:1;min-width:0">';
        html += '<span style="color:' + sevColor + ';font-weight:600;font-size:0.68rem;text-transform:uppercase;letter-spacing:0.3px">' + esc(f.severity || 'info') + '</span> ';
        html += '<span style="font-weight:500;font-size:0.82rem">' + esc(f.title) + '</span>';
        html += '</div>';
        html += '<div class="finding-actions">';
        html += '<button class="finding-btn finding-accept active" onclick="setFindingDecision(\'' + fid + '\', true)" title="Accept">&#10003;</button>';
        html += '<button class="finding-btn finding-reject" onclick="setFindingDecision(\'' + fid + '\', false)" title="Reject">&#10007;</button>';
        html += '</div></div>';
        if (f.description) html += '<div style="font-size:0.75rem;color:var(--text-secondary);margin-top:4px;padding:0 4px">' + esc(f.description) + '</div>';
        if (f.files && f.files.length > 0) html += '<div style="font-size:0.68rem;color:var(--text-muted);margin-top:2px;padding:0 4px">' + f.files.map(esc).join(', ') + '</div>';
        if (f.fix_hint) html += '<div style="font-size:0.68rem;color:var(--green);margin-top:2px;padding:0 4px">Fix: ' + esc(f.fix_hint) + '</div>';
        html += '</div>';
      });
      html += '<div id="findings-summary" style="margin-top:8px;font-size:0.75rem;color:var(--text-muted)"></div>';
      html += '</div>';
      return html;
    }
    
    // ── Shared: render an issue as an expandable accordion ──
    function renderIssueAccordion(issue, idx) {
      var stateColor = issue.state === 'Done' ? 'var(--green)' : issue.state === 'Review' ? 'var(--yellow)' : 'var(--text-muted)';
      var hasContent = issue.result_text || (issue.reports && issue.reports.length > 0) || issue.description;
      var html = '';
    
      if (hasContent) {
        html += '<details class="issue-accordion"' + (idx === 0 ? ' open' : '') + '>';
        html += '<summary class="accordion-header">';
        html += '<span style="color:var(--accent);font-weight:500">' + esc(issue.identifier) + '</span> ';
        html += esc(issue.title);
        html += ' <span style="color:' + stateColor + ';font-size:0.72rem">' + esc(issue.state) + '</span>';
        if (issue.reports && issue.reports.length > 0) html += ' <span style="font-size:0.65rem;color:var(--green)">&#128196; ' + issue.reports.length + '</span>';
        html += '</summary>';
        html += '<div class="accordion-body">';
        if (issue.description) {
          html += '<div class="report-section"><div class="report-section-title">Description</div>';
          html += '<div class="report-content">' + renderMarkdown(issue.description) + '</div></div>';
        }
        if (issue.result_text) {
          html += '<div class="report-section"><div class="report-section-title">Agent Result</div>';
          html += '<div class="report-content">' + renderMarkdown(issue.result_text) + '</div></div>';
        }
        if (issue.reports && issue.reports.length > 0) {
          issue.reports.forEach(function(report) {
            html += '<div class="report-section"><div class="report-section-title">' + esc(report.name) + '</div>';
            html += '<div class="report-content">' + renderMarkdown(report.content) + '</div></div>';
          });
        }
        html += '<div style="margin-top:6px"><a href="' + esc(issue.url) + '" class="btn btn-sm btn-ghost" style="font-size:0.72rem;text-decoration:none">Open Full Issue</a></div>';
        html += '</div></details>';
      } else {
        html += '<div style="padding:6px 8px;background:var(--bg-secondary);border:1px solid var(--border);border-radius:4px;margin-bottom:4px;font-size:0.8rem">';
        html += '<a href="' + esc(issue.url) + '" style="color:var(--accent);text-decoration:none;font-weight:500">' + esc(issue.identifier) + '</a> ';
        html += esc(issue.title);
        html += ' <span style="color:' + stateColor + ';font-size:0.72rem">' + esc(issue.state) + '</span>';
        html += '</div>';
      }
      return html;
    }
    
    // ── Shared: render feedback history ──
    function renderFeedbackHistory(ctx) {
      var html = '';
      if (ctx.feedback_history && ctx.feedback_history.length > 0) {
        html += '<details style="margin-top:10px"' + (ctx.feedback_history.length <= 3 ? ' open' : '') + '>';
        html += '<summary class="accordion-header">Decision History (' + ctx.feedback_history.length + ')</summary>';
        html += '<div class="accordion-body" style="padding:4px 0">';
        ctx.feedback_history.forEach(function(d) {
          var actionColor = d.action === 'approve' ? 'var(--green)' : d.action === 'reject' ? 'var(--red)' : 'var(--yellow)';
          html += '<div style="padding:4px 8px;border-left:2px solid ' + actionColor + ';margin-bottom:4px;font-size:0.78rem">';
          html += '<span style="color:' + actionColor + ';font-weight:500">' + esc(d.action) + '</span>';
          if (d.decided_at) html += ' <span style="font-size:0.68rem;color:var(--text-muted)">' + new Date(d.decided_at).toLocaleString() + '</span>';
          if (d.feedback) html += '<div style="margin-top:2px;color:var(--text-secondary)">' + esc(d.feedback) + '</div>';
          html += '</div>';
        });
        html += '</div></details>';
      }
      return html;
    }
    
    async function forceCompleteNode(nodeId) {
      if (!activeRun) return;
      if (!confirm('Force-complete this node? The current state will be overridden.')) return;
      try {
        var res = await fetch('/board/api/pipelines/' + pipeline.id + '/runs/' + activeRun.id + '/force-complete/' + nodeId, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' }
        });
        if (res.ok) {
          showToast('Node force-completed', { type: 'success' });
          pollRunStatus();
        } else {
          showToast('Force-complete failed', { type: 'error' });
        }
      } catch(e) {
        showToast('Force-complete failed: ' + e.message, { type: 'error' });
      }
    }
    
    function setFindingDecision(findingId, accepted) {
      var card = document.querySelector('.finding-card[data-finding-id="' + findingId + '"]');
      if (!card) return;
      card.dataset.decision = accepted ? 'accepted' : 'rejected';
      var acceptBtn = card.querySelector('.finding-accept');
      var rejectBtn = card.querySelector('.finding-reject');
      if (accepted) {
        acceptBtn.classList.add('active');
        rejectBtn.classList.remove('active');
        card.style.opacity = '1';
      } else {
        acceptBtn.classList.remove('active');
        rejectBtn.classList.add('active');
        card.style.opacity = '0.6';
      }
      updateFindingsSummary();
    }
    
    function setAllFindings(accepted) {
      document.querySelectorAll('.finding-card').forEach(function(card) {
        setFindingDecision(card.dataset.findingId, accepted);
      });
    }
    
    function updateFindingsSummary() {
      var cards = document.querySelectorAll('.finding-card');
      if (cards.length === 0) return;
      var accepted = 0, rejected = 0;
      cards.forEach(function(c) { if (c.dataset.decision === 'accepted') accepted++; else rejected++; });
      var el = document.getElementById('findings-summary');
      if (el) el.innerHTML = '<span style="color:var(--green)">' + accepted + ' accepted</span> &middot; <span style="color:var(--red)">' + rejected + ' rejected</span> of ' + cards.length + ' findings';
    }
    
    async function gateDecision(nodeId, action) {
      if (!activeRun) { console.warn('gateDecision: no activeRun'); return; }
    
      const feedback = document.getElementById('gate-feedback')?.value || '';
    
      // Collect per-finding decisions from accept/reject buttons
      var findingCards = document.querySelectorAll('.finding-card');
      var findingsDecisions = null;
      if (findingCards.length > 0) {
        findingsDecisions = [];
        findingCards.forEach(function(card) {
          findingsDecisions.push({ id: card.dataset.findingId, accepted: card.dataset.decision === 'accepted' });
        });
      }
    
      var body = { action: action, feedback: feedback };
      if (findingsDecisions) body.findings_decisions = findingsDecisions;
    
      try {
        var url = '/board/api/pipelines/' + pipeline.id + '/runs/' + activeRun.id + '/gate/' + nodeId;
        var res = await fetch(url, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(body)
        });
        if (res.ok) {
          var accepted = findingsDecisions ? findingsDecisions.filter(function(f) { return f.accepted; }).length : 0;
          var total = findingsDecisions ? findingsDecisions.length : 0;
          var msg = findingsDecisions ? 'Gate ' + action + 'ed (' + accepted + '/' + total + ' findings accepted)' : 'Gate ' + action + 'ed';
          showToast(msg, { type: action === 'approve' ? 'success' : '' });
        } else {
          var errBody = await res.text();
          console.error('gateDecision failed:', res.status, errBody);
          showToast('Gate decision failed: ' + res.status, { type: 'error' });
        }
      } catch(e) {
        console.error('gateDecision error:', e);
        showToast('Gate decision error: ' + e.message, { type: 'error' });
      }
      pollRunStatus();
    }
    
    function collectPredecessorIssueIds(nodeId) {
      // Walk backwards through the graph collecting all issue nodes (transitive)
      var visited = {};
      var issueIds = [];
      function walk(nid) {
        if (visited[nid]) return;
        visited[nid] = true;
        var node = nodes.find(function(n) { return n.id === nid; });
        if (node && node.type === 'issue' && node.issue_id) {
          issueIds.push(node.issue_id);
        }
        edges.forEach(function(e) {
          if (e.target_node_id === nid) walk(e.source_node_id);
        });
      }
      // Start from direct predecessors (don't include the kb_sync node itself)
      edges.forEach(function(e) {
        if (e.target_node_id === nodeId) walk(e.source_node_id);
      });
      return issueIds;
    }
    
    async function kbSyncSendAndApprove(nodeId) {
      if (!activeRun) return;
      if (!confirm('Send all predecessor issue reports to the Knowledge Base?')) return;
    
      var predecessorIssueIds = collectPredecessorIssueIds(nodeId);
    
      if (predecessorIssueIds.length === 0) {
        showToast('No predecessor issues found to send', { type: 'error' });
        return;
      }
    
      var allPaths = [];
      var fromReports = 0;
      var fromDesc = 0;
      for (var i = 0; i < predecessorIssueIds.length; i++) {
        try {
          var res = await fetch('/board/api/vault/send', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ issue_id: predecessorIssueIds[i] })
          });
          var data = await res.json();
          if (data.ok && data.notes_written) {
            allPaths = allPaths.concat(data.notes_written);
            if (data.source === 'reports') fromReports++; else fromDesc++;
          }
        } catch(err) {
          showToast('KB send failed: ' + err.message, { type: 'error' });
        }
      }
    
      if (allPaths.length > 0) {
        var msg = 'Sent ' + allPaths.length + ' note(s) to KB';
        if (fromDesc > 0) msg += ' (' + fromDesc + ' from description only)';
        showToast(msg, { type: 'success' });
      } else {
        showToast('No notes were written', { type: 'error' });
      }
    
      // Now approve the gate to advance the pipeline
      gateDecision(nodeId, 'approve');
    }
    
    """
  end

  defp help_and_utils_js do
    ~S"""
    // ══════════════════════════════════
    // Help modal
    // ══════════════════════════════════
    function toggleHelpModal() {
      const m = document.getElementById('help-modal');
      m.style.display = m.style.display === 'none' ? 'flex' : 'none';
    }
    function closeHelpModal() {
      document.getElementById('help-modal').style.display = 'none';
    }
    
    // ══════════════════════════════════
    // Utilities
    // ══════════════════════════════════
    function generateId() {
      return 'n' + Math.random().toString(36).substring(2, 14);
    }
    
    // ══════════════════════════════════
    // ══════════════════════════════════
    // Minimap
    // ══════════════════════════════════
    function renderMinimap() {
      const canvas = document.getElementById('minimap-canvas');
      if (!canvas || nodes.length === 0) return;
      const ctx = canvas.getContext('2d');
      const W = canvas.width, H = canvas.height;
      ctx.clearRect(0, 0, W, H);
    
      // Compute bounding box of all nodes
      let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
      nodes.forEach(n => {
        const w = (n.type === 'start' || n.type === 'end') ? 40 : 200;
        const h = (n.type === 'start' || n.type === 'end') ? 40 : 60;
        if (n.position.x < minX) minX = n.position.x;
        if (n.position.y < minY) minY = n.position.y;
        if (n.position.x + w > maxX) maxX = n.position.x + w;
        if (n.position.y + h > maxY) maxY = n.position.y + h;
      });
      const pad = 40;
      minX -= pad; minY -= pad; maxX += pad; maxY += pad;
      const bw = maxX - minX || 1, bh = maxY - minY || 1;
      const s = Math.min(W / bw, H / bh);
    
      // Draw edges
      ctx.strokeStyle = '#58687a';
      ctx.lineWidth = 1;
      edges.forEach(e => {
        const src = nodes.find(n => n.id === e.source_node_id);
        const tgt = nodes.find(n => n.id === e.target_node_id);
        if (!src || !tgt) return;
        const sx = (src.position.x + 100 - minX) * s;
        const sy = (src.position.y + 30 - minY) * s;
        const tx = (tgt.position.x + 100 - minX) * s;
        const ty = (tgt.position.y + 30 - minY) * s;
        if (e.source_port === 'reject') ctx.strokeStyle = '#f85149';
        else ctx.strokeStyle = '#58687a';
        ctx.beginPath(); ctx.moveTo(sx, sy); ctx.lineTo(tx, ty); ctx.stroke();
      });
    
      // Draw nodes
      nodes.forEach(n => {
        const color = NODE_COLORS[n.type] || '#8b949e';
        const w = (n.type === 'start' || n.type === 'end') ? 40 : 200;
        const h = (n.type === 'start' || n.type === 'end') ? 40 : 60;
        const x = (n.position.x - minX) * s;
        const y = (n.position.y - minY) * s;
        ctx.fillStyle = color;
        ctx.globalAlpha = 0.8;
        if (n.type === 'start' || n.type === 'end') {
          ctx.beginPath(); ctx.arc(x + w*s/2, y + h*s/2, Math.max(3, w*s/2), 0, Math.PI*2); ctx.fill();
        } else {
          ctx.fillRect(x, y, Math.max(4, w*s), Math.max(3, h*s));
        }
        ctx.globalAlpha = 1;
      });
    
      // Draw viewport indicator
      const vp = document.getElementById('minimap-vp');
      const viewport = document.querySelector('.canvas-viewport');
      if (vp && viewport) {
        const vw = viewport.clientWidth / scale;
        const vh = viewport.clientHeight / scale;
        const vpx = (-panX / scale - minX) * s;
        const vpy = (-panY / scale - minY) * s;
        vp.style.left = Math.max(0, vpx) + 'px';
        vp.style.top = Math.max(0, vpy) + 'px';
        vp.style.width = Math.min(W, vw * s) + 'px';
        vp.style.height = Math.min(H, vh * s) + 'px';
      }
    }
    
    """
  end

  defp product_and_history_js do
    ~S"""
    // Load products for the product selector
    async function loadProductSelector() {
      try {
        var res = await fetch('/board/api/products');
        var data = await res.json();
        var sel = document.getElementById('pipeline-product');
        (data.products || []).forEach(function(p) {
          var opt = document.createElement('option');
          opt.value = p.id;
          opt.textContent = p.name;
          if (p.id === pipeline.product_id) opt.selected = true;
          sel.appendChild(opt);
        });
      } catch(e) {}
    }
    
    // Resume execution mode if there's an active run for this pipeline
    async function resumeActiveRun() {
      try {
        var res = await fetch('/board/api/pipelines/' + pipeline.id + '/runs');
        if (!res.ok) return;
        var data = await res.json();
        var runs = data.runs || [];
        // Find the most recent active run
        var active = runs.filter(function(r) { return r.status === 'running' || r.status === 'paused'; });
        if (active.length === 0) return;
        activeRun = active[active.length - 1];
    
        // Enter exec mode
        if (!document.getElementById('exec-sidebar')) {
          var sidebar = document.createElement('div');
          sidebar.className = 'exec-sidebar';
          sidebar.id = 'exec-sidebar';
          document.body.appendChild(sidebar);
        }
    
        execMode = true;
        document.getElementById('run-btn').innerHTML = '&#9632; Stop';
        document.getElementById('palette').style.display = 'none';
        render();
        pollTimer = setInterval(pollRunStatus, 2000);
      } catch(e) {}
    }
    
    // ══════════════════════════════════
    // Run History (Fix R)
    // ══════════════════════════════════
    var runHistoryOpen = false;
    
    function toggleRunHistory() {
      var panel = document.getElementById('run-history-panel');
      runHistoryOpen = !runHistoryOpen;
      panel.style.display = runHistoryOpen ? 'block' : 'none';
      if (runHistoryOpen) loadRunHistory();
    }
    
    async function loadRunHistory() {
      var list = document.getElementById('run-history-list');
      list.innerHTML = '<div class="rh-empty">Loading...</div>';
      try {
        var res = await fetch('/board/api/pipelines/' + pipeline.id + '/runs');
        var data = await res.json();
        var runs = data.runs || [];
        if (runs.length === 0) {
          list.innerHTML = '<div class="rh-empty">No runs yet</div>';
          return;
        }
        list.innerHTML = runs.map(function(r) {
          var states = r.node_states || {};
          var total = Object.keys(states).length;
          var done = Object.values(states).filter(function(s) { return s === 'completed'; }).length;
          var failed = Object.values(states).filter(function(s) { return s === 'failed'; }).length;
          var waiting = Object.values(states).filter(function(s) { return s === 'waiting_gate'; }).length;
    
          var started = r.started_at ? new Date(r.started_at).toLocaleString() : '-';
          var ended = r.completed_at ? new Date(r.completed_at).toLocaleString() : '-';
    
          var gatesHtml = '';
          if (r.gate_decisions && r.gate_decisions.length > 0) {
            gatesHtml = '<div class="rh-gates"><strong style="font-size:0.72rem">Gate decisions:</strong>';
            r.gate_decisions.forEach(function(g) {
              var color = g.action === 'approve' ? 'var(--green)' : 'var(--red)';
              var fb = g.feedback ? ' — ' + esc(g.feedback) : '';
              gatesHtml += '<div class="rh-gate"><span style="color:' + color + '">' + g.action + '</span> on ' + g.node_id + fb + '</div>';
            });
            gatesHtml += '</div>';
          }
    
          return '<div class="rh-item">' +
            '<div class="rh-item-header">' +
              '<span class="rh-status rh-status-' + r.status + '">' + r.status + '</span>' +
              '<span class="rh-time">' + started + '</span>' +
            '</div>' +
            '<div class="rh-nodes">' + done + '/' + total + ' completed' +
              (failed > 0 ? ', ' + failed + ' failed' : '') +
              (waiting > 0 ? ', ' + waiting + ' waiting' : '') +
            '</div>' +
            (r.completed_at ? '<div class="rh-time" style="margin-top:2px">Ended: ' + ended + '</div>' : '') +
            gatesHtml +
          '</div>';
        }).join('');
      } catch(e) {
        list.innerHTML = '<div class="rh-empty">Failed to load history</div>';
      }
    }
    
    """
  end

  defp init_js do
    ~S"""
    // Init
    // ══════════════════════════════════
    render();
    if (nodes.length > 0) zoomFit();
    renderMinimap();
    loadProductSelector();
    resumeActiveRun();
    """
  end
end

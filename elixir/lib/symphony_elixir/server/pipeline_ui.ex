defmodule SymphonyElixir.Server.PipelineUI do
  @moduledoc """
  Pipeline designer and execution monitor UI.

  - render_list/0: Pipeline list page at /pipeline
  - render_designer/1: Visual canvas designer for a specific pipeline
  """

  alias SymphonyElixir.Server.UIHelpers

  # ── Pipeline List Page ──────────────────────────────────────────

  @spec render_list() :: String.t()
  def render_list do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Symphony Pipelines</title>
      <style>
    #{list_css()}
      </style>
    </head>
    <body>
    #{UIHelpers.nav_topbar("pipeline")}
      <div class="page-header">
        <h2>Pipelines</h2>
        <button class="btn btn-primary" onclick="createPipeline()">+ New Pipeline</button>
      </div>
      <div class="pipeline-grid" id="pipeline-grid"></div>
      <script>
    #{UIHelpers.esc_js()}
    #{UIHelpers.toast_js()}
    #{list_js()}
      </script>
    </body>
    </html>
    """
  end

  defp list_css do
    UIHelpers.base_css() <>
      UIHelpers.topbar_css() <>
      UIHelpers.nav_active_css() <>
      UIHelpers.button_css() <>
      UIHelpers.toast_css() <>
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
      """
  end

  defp list_js do
    ~S"""
    let pipelines = [];

    async function loadPipelines() {
      const res = await fetch('/board/api/pipelines');
      const data = await res.json();
      pipelines = data.pipelines || [];
      renderGrid();
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
            <div class="mini-preview">${renderMiniSvg(p)}</div>
            <div class="pipeline-card-name">${esc(p.name)}</div>
            <div class="pipeline-card-desc">${desc}</div>
            <div class="pipeline-card-meta">
              <span class="node-count">${nodeCount} nodes</span>
              <span>${edgeCount} connections</span>
            </div>
            <div class="pipeline-card-actions">
              <button class="btn btn-sm btn-ghost" onclick="event.stopPropagation(); duplicatePipeline('${p.id}')">Duplicate</button>
              <button class="btn btn-sm btn-ghost" style="color:var(--red)" onclick="event.stopPropagation(); deletePipeline('${p.id}')">Delete</button>
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
          svg += `<line x1="${s.position.x + 100}" y1="${s.position.y + 30}" x2="${t.position.x + 100}" y2="${t.position.y + 30}" stroke="#30363d" stroke-width="2"/>`;
        }
      });

      // nodes
      nodes.forEach(n => {
        const c = colors[n.type] || '#8b949e';
        if (n.type === 'start' || n.type === 'end') {
          svg += `<circle cx="${n.position.x + 100}" cy="${n.position.y + 30}" r="8" fill="${c}" opacity="0.8"/>`;
        } else {
          svg += `<rect x="${n.position.x}" y="${n.position.y}" width="200" height="48" rx="6" fill="${c}" opacity="0.15" stroke="${c}" stroke-width="1.5"/>`;
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
    """
  end

  # ── Pipeline Designer Page ──────────────────────────────────────

  @spec render_designer(map()) :: String.t()
  def render_designer(pipeline) do
    pipeline_json = Jason.encode!(pipeline)

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>#{UIHelpers.esc(pipeline.name)} — Symphony Pipeline</title>
      <style>
    #{designer_css()}
      </style>
    </head>
    <body>
    #{UIHelpers.nav_topbar("pipeline")}

      <!-- Floating palette -->
      <div class="palette" id="palette">
        <div class="palette-item" draggable="true" data-type="start" title="Start">
          <svg viewBox="0 0 16 16" width="16" height="16"><circle cx="8" cy="8" r="6" fill="#58a6ff"/></svg>
        </div>
        <div class="palette-item" draggable="true" data-type="issue" title="Issue / Task">
          <svg viewBox="0 0 16 16" width="16" height="16"><rect x="2" y="2" width="12" height="12" rx="2" fill="#58a6ff"/></svg>
        </div>
        <div class="palette-item" draggable="true" data-type="human_gate" title="Human Gate">
          <svg viewBox="0 0 16 16" width="16" height="16"><polygon points="8,1 15,8 8,15 1,8" fill="#d29922"/></svg>
        </div>
        <div class="palette-item" draggable="true" data-type="quality_gate" title="Quality Gate">
          <svg viewBox="0 0 16 16" width="16" height="16"><polygon points="8,1 15,8 8,15 1,8" fill="#bc8cff"/></svg>
        </div>
        <div class="palette-item" draggable="true" data-type="loop" title="Loop">
          <svg viewBox="0 0 16 16" width="16" height="16"><path d="M4 8a4 4 0 0 1 8 0" stroke="#d18616" stroke-width="2" fill="none"/><path d="M10 6l2 2-2 2" stroke="#d18616" stroke-width="2" fill="none"/></svg>
        </div>
        <div class="palette-item" draggable="true" data-type="kb_sync" title="KB Sync">
          <svg viewBox="0 0 16 16" width="16" height="16"><rect x="2" y="2" width="12" height="12" rx="2" fill="#3fb950"/></svg>
        </div>
        <div class="palette-item" draggable="true" data-type="integration" title="Integration">
          <svg viewBox="0 0 16 16" width="16" height="16"><rect x="2" y="2" width="12" height="12" rx="2" fill="#8b949e"/></svg>
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
        <button class="btn btn-sm btn-ghost" onclick="toggleExecution()" id="run-btn">&#9654; Run</button>
        <button class="btn btn-sm btn-primary" onclick="savePipeline()">Save</button>
      </div>

      <!-- Pipeline name / breadcrumb top-left below topbar -->
      <div class="canvas-breadcrumb">
        <a href="/board/pipeline" class="btn btn-ghost btn-sm">&larr; Pipelines</a>
        <input id="pipeline-name" class="pipeline-name-input" value="#{UIHelpers.esc(pipeline.name)}" onchange="markDirty()">
        <span style="color:var(--border);font-size:0.9rem">/</span>
        <input id="pipeline-desc" class="pipeline-desc-input" placeholder="Add description..." value="#{UIHelpers.esc(pipeline.description || "")}" onchange="markDirty()">
        <button class="btn btn-ghost btn-sm" onclick="toggleHelpModal()" title="Keyboard shortcuts" style="margin-left:auto">?</button>
      </div>

      <!-- Help modal -->
      <div class="modal-overlay" id="help-modal" style="display:none" onclick="if(event.target===this)closeHelpModal()">
        <div class="modal" style="max-width:440px">
          <div class="modal-header">
            <h3>Keyboard Shortcuts</h3>
            <button class="btn-icon" onclick="closeHelpModal()">&times;</button>
          </div>
          <div class="modal-body" style="font-size:0.85rem">
            <table style="width:100%;border-collapse:collapse">
              <tr><td style="padding:4px 0;color:var(--text-muted)">Save</td><td style="text-align:right"><kbd>Ctrl+S</kbd></td></tr>
              <tr><td style="padding:4px 0;color:var(--text-muted)">Undo</td><td style="text-align:right"><kbd>Ctrl+Z</kbd></td></tr>
              <tr><td style="padding:4px 0;color:var(--text-muted)">Redo</td><td style="text-align:right"><kbd>Ctrl+Y</kbd> / <kbd>Ctrl+Shift+Z</kbd></td></tr>
              <tr><td style="padding:4px 0;color:var(--text-muted)">Delete node</td><td style="text-align:right"><kbd>Delete</kbd> / <kbd>Backspace</kbd></td></tr>
              <tr><td style="padding:4px 0;color:var(--text-muted)">Deselect / Close</td><td style="text-align:right"><kbd>Escape</kbd></td></tr>
              <tr><td style="padding:4px 0;color:var(--text-muted)">Show help</td><td style="text-align:right"><kbd>?</kbd></td></tr>
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
    </body>
    </html>
    """
  end

  defp designer_css do
    UIHelpers.base_css() <>
      UIHelpers.topbar_css() <>
      UIHelpers.nav_active_css() <>
      UIHelpers.button_css() <>
      UIHelpers.form_css() <>
      UIHelpers.modal_css() <>
      UIHelpers.toast_css() <>
      UIHelpers.ai_draft_css() <>
      UIHelpers.skill_picker_css() <>
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
      .p-node-label { font-size: 0.85rem; font-weight: 500; color: var(--text-primary); margin-top: 2px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
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

      /* Execution overlay styles */
      .p-node.exec-completed { border-color: var(--green); box-shadow: 0 0 8px rgba(63,185,80,0.3); }
      .p-node.exec-running { border-color: var(--accent); animation: pulse-node 2s infinite; }
      .p-node.exec-waiting { border-color: var(--yellow); animation: pulse-gate 2s infinite; }
      .p-node.exec-failed { border-color: var(--red); box-shadow: 0 0 8px rgba(248,81,73,0.3); }
      .p-node-terminal.exec-completed { box-shadow: 0 0 8px rgba(63,185,80,0.5); }

      @keyframes pulse-node {
        0%, 100% { box-shadow: 0 0 0 0 rgba(88,166,255,0.4); }
        50% { box-shadow: 0 0 0 8px rgba(88,166,255,0); }
      }
      @keyframes pulse-gate {
        0%, 100% { box-shadow: 0 0 0 0 rgba(210,153,34,0.4); }
        50% { box-shadow: 0 0 0 8px rgba(210,153,34,0); }
      }

      /* Execution sidebar */
      .exec-sidebar {
        position: fixed; top: 48px; right: 0; bottom: 0; width: 320px;
        background: rgba(22,27,34,0.95); border-left: 1px solid var(--border);
        z-index: 110; transform: translateX(100%);
        transition: transform 250ms ease; overflow-y: auto; padding: 16px;
      }
      .exec-sidebar.open { transform: translateX(0); }
      .exec-sidebar h3 { font-size: 0.95rem; margin-bottom: 12px; }
      .gate-action { margin-top: 12px; display: flex; gap: 6px; }
      .gate-feedback { width: 100%; margin-top: 8px; background: var(--bg-tertiary); border: 1px solid var(--border); border-radius: 6px; color: var(--text-primary); padding: 8px; font-size: 0.85rem; resize: vertical; min-height: 60px; }

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
      """
  end

  defp designer_js do
    designer_js_part1() <> UIHelpers.create_issue_modal_js("ci") <> UIHelpers.skill_picker_js() <> designer_js_part2()
  end

  defp designer_js_part1 do
    ~S"""
    // ═══════════════════════════════════════════════════════════════
    // State
    // ═══════════════════════════════════════════════════════════════
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
    let allSkills = [];
    let allSkillGroups = [];

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

    // ═══════════════════════════════════════════════════════════════
    // Render
    // ═══════════════════════════════════════════════════════════════
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
          if (n.type === 'loop') meta = '<div class="p-node-meta">Max retries: ' + (n.loop_max_retries || '∞') + '</div>';

          el.innerHTML = `
            <div class="p-node-top" style="background:${color}"></div>
            <div class="p-node-body">
              <div class="p-node-type">${NODE_LABELS[n.type] || n.type}</div>
              <div class="p-node-label">${esc(n.label || NODE_LABELS[n.type])}</div>
              ${meta}
            </div>
            <div class="port port-in" data-node="${n.id}" data-port="input"></div>
            <div class="port port-out" data-node="${n.id}" data-port="output"></div>
            ${(n.type === 'human_gate' || n.type === 'quality_gate') ? '<div class="port port-reject" data-node="' + n.id + '" data-port="reject"></div>' : ''}
          `;

          // Selected toolbar
          if (n.id === selectedNodeId && !execMode) {
            el.innerHTML += `
              <div class="node-toolbar">
                <button class="btn btn-sm btn-ghost" onclick="event.stopPropagation(); openConfig('${n.id}')">Configure</button>
                <button class="btn btn-sm btn-ghost" onclick="event.stopPropagation(); duplicateNode('${n.id}')">Duplicate</button>
                <button class="btn btn-sm btn-ghost" style="color:var(--red)" onclick="event.stopPropagation(); deleteNode('${n.id}')">Delete</button>
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
            showToast('Connection deleted', { type: 'success', undo: function() { edges.push(removedEdge); undo(); } });
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

    // ═══════════════════════════════════════════════════════════════
    // Pan & Zoom
    // ═══════════════════════════════════════════════════════════════
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

    // ═══════════════════════════════════════════════════════════════
    // Node interaction (drag, select, connect)
    // ═══════════════════════════════════════════════════════════════
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

    // ═══════════════════════════════════════════════════════════════
    // Temp edge for connection drawing
    // ═══════════════════════════════════════════════════════════════
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

    // ═══════════════════════════════════════════════════════════════
    // Palette drag-and-drop
    // ═══════════════════════════════════════════════════════════════
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

    // ═══════════════════════════════════════════════════════════════
    // Configuration modal
    // ═══════════════════════════════════════════════════════════════
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
        html += `
          <div class="form-group">
            <label>Linked Issue ID</label>
            <input id="cfg-issue-id" value="${esc(node.issue_id || '')}" placeholder="Select or enter issue ID">
            <div id="issue-picker" style="margin-top:4px"></div>
          </div>
          <div style="border-top:1px solid var(--border);margin:12px 0;padding-top:12px">
            <button class="btn btn-ghost" type="button" onclick="openCreateIssueModal()" style="width:100%">+ Create new issue</button>
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
        html += `
          <div class="form-group">
            <label>Review Instructions</label>
            <textarea id="cfg-instructions" rows="3">${esc((node.config || {}).instructions || '')}</textarea>
          </div>`;
      }

      if (node.type === 'quality_gate') {
        const checks = (node.config || {}).checks || ['tests', 'lint', 'types'];
        html += `
          <div class="form-group">
            <label>Quality Checks (comma-separated)</label>
            <input id="cfg-checks" value="${checks.join(', ')}">
          </div>`;
      }

      if (node.type === 'integration') {
        const intType = (node.config || {}).integration_type || 'jira';
        html += `
          <div class="form-group">
            <label>Integration Type</label>
            <select id="cfg-int-type">
              <option value="jira" ${intType === 'jira' ? 'selected' : ''}>Jira</option>
              <option value="gitlab" ${intType === 'gitlab' ? 'selected' : ''}>GitLab CI</option>
              <option value="confluence" ${intType === 'confluence' ? 'selected' : ''}>Confluence</option>
            </select>
          </div>
          <div class="form-group">
            <label>Configuration (JSON)</label>
            <textarea id="cfg-int-config" rows="4">${esc(JSON.stringify((node.config || {}).integration_config || {}, null, 2))}</textarea>
          </div>`;
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
      }
      if (node.type === 'loop') {
        node.loop_max_retries = parseInt(document.getElementById('cfg-max-retries').value) || 5;
        node.loop_condition = document.getElementById('cfg-loop-cond').value || null;
      }
      if (node.type === 'human_gate') {
        node.config = node.config || {};
        node.config.instructions = document.getElementById('cfg-instructions').value;
      }
      if (node.type === 'quality_gate') {
        node.config = node.config || {};
        node.config.checks = document.getElementById('cfg-checks').value.split(',').map(s => s.trim()).filter(Boolean);
      }
      if (node.type === 'integration') {
        node.config = node.config || {};
        node.config.integration_type = document.getElementById('cfg-int-type').value;
        try {
          node.config.integration_config = JSON.parse(document.getElementById('cfg-int-config').value);
        } catch(e) {}
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
    """
  end

  defp designer_js_part2 do
    ~S"""
    async function loadSkills() {
      try {
        var [sRes, gRes] = await Promise.all([fetch('/board/api/skills'), fetch('/board/api/skill-groups')]);
        var sData = await sRes.json(); var gData = await gRes.json();
        allSkills = (sData.skills || []).sort(function(a, b) { return a.name.localeCompare(b.name); });
        allSkillGroups = (gData.skill_groups || []).sort(function(a, b) { return a.name.localeCompare(b.name); });
      } catch (e) { allSkills = []; allSkillGroups = []; }
    }
    loadSkills();

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

    // ═══════════════════════════════════════════════════════════════
    // Save
    // ═══════════════════════════════════════════════════════════════
    function markDirty() { dirty = true; }

    window.addEventListener('beforeunload', e => {
      if (dirty) { e.preventDefault(); e.returnValue = ''; }
    });

    async function savePipeline() {
      const name = document.getElementById('pipeline-name').value;
      const description = document.getElementById('pipeline-desc').value;
      const res = await fetch('/board/api/pipelines/' + pipeline.id, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, description, nodes, edges, settings: pipeline.settings })
      });
      if (res.ok) {
        dirty = false;
        document.title = name + ' — Symphony Pipeline';
        showToast('Pipeline saved', { type: 'success' });
      } else {
        showToast('Failed to save pipeline', { type: 'error' });
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

    // ═══════════════════════════════════════════════════════════════
    // Execution mode
    // ═══════════════════════════════════════════════════════════════
    async function toggleExecution() {
      if (execMode) {
        // Stop execution mode
        execMode = false;
        activeRun = null;
        if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
        document.getElementById('run-btn').innerHTML = '&#9654; Run';
        document.querySelector('.exec-sidebar')?.classList.remove('open');
        document.getElementById('palette').style.display = 'flex';
        render();
        return;
      }

      // Save first
      if (dirty) await savePipeline();

      // Start a run
      const res = await fetch('/board/api/pipelines/' + pipeline.id + '/run', { method: 'POST' });
      if (!res.ok) { showToast('Failed to start run', { type: 'error' }); return; }
      activeRun = await res.json();
      showToast('Pipeline run started', { type: 'success' });

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
          // Update sidebar if open
          if (selectedNodeId) showExecSidebar(selectedNodeId);
        }
      } catch(e) {}
    }

    function closeExecSidebar() {
      const sidebar = document.getElementById('exec-sidebar');
      if (sidebar) sidebar.classList.remove('open');
      selectedNodeId = null;
      render();
    }

    function showExecSidebar(nodeId) {
      const sidebar = document.getElementById('exec-sidebar');
      if (!sidebar || !activeRun) return;
      sidebar.classList.add('open');

      const node = nodes.find(n => n.id === nodeId);
      if (!node) { sidebar.innerHTML = ''; return; }

      const state = (activeRun.node_states || {})[nodeId] || 'pending';
      const attempts = (activeRun.node_attempts || {})[nodeId] || 0;
      const color = NODE_COLORS[node.type] || '#8b949e';

      let html = `
        <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:4px">
          <h3 style="border-left:3px solid ${color}; padding-left:8px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; max-width:250px; margin:0">${esc(node.label)}</h3>
          <button class="btn-icon" onclick="closeExecSidebar()" title="Close">&times;</button>
        </div>
        <div style="margin-top:8px; font-size:0.85rem; color:var(--text-muted)">
          State: <strong style="color:var(--text-primary)">${state}</strong><br>
          Attempts: ${attempts}
        </div>`;

      if (state === 'waiting_gate' && (node.type === 'human_gate' || node.type === 'quality_gate')) {
        html += `
          <div class="gate-action">
            <button class="btn btn-sm btn-primary" onclick="gateDecision('${nodeId}', 'approve')">Approve</button>
            <button class="btn btn-sm btn-ghost" style="color:var(--red)" onclick="gateDecision('${nodeId}', 'reject')">Reject</button>
          </div>
          <textarea class="gate-feedback" id="gate-feedback" placeholder="Feedback (optional)" rows="3"></textarea>`;
      }

      if (node.type === 'issue' && node.issue_id && state === 'running') {
        html += '<div style="margin-top:12px;font-size:0.8rem;color:var(--text-muted)">Issue dispatched to orchestrator. Waiting for completion...</div>';
      }

      sidebar.innerHTML = html;
    }

    async function gateDecision(nodeId, action) {
      if (!activeRun) return;
      const feedback = document.getElementById('gate-feedback')?.value || '';
      const res = await fetch(`/board/api/pipelines/${pipeline.id}/runs/${activeRun.id}/gate/${nodeId}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action, feedback })
      });
      if (res.ok) {
        showToast('Gate ' + action + 'ed', { type: action === 'approve' ? 'success' : '' });
      } else {
        showToast('Gate decision failed', { type: 'error' });
      }
      pollRunStatus();
    }

    // ═══════════════════════════════════════════════════════════════
    // Help modal
    // ═══════════════════════════════════════════════════════════════
    function toggleHelpModal() {
      const m = document.getElementById('help-modal');
      m.style.display = m.style.display === 'none' ? 'flex' : 'none';
    }
    function closeHelpModal() {
      document.getElementById('help-modal').style.display = 'none';
    }

    // ═══════════════════════════════════════════════════════════════
    // Utilities
    // ═══════════════════════════════════════════════════════════════
    function generateId() {
      return 'n' + Math.random().toString(36).substring(2, 14);
    }

    // ═══════════════════════════════════════════════════════════════
    // ═══════════════════════════════════════════════════════════════
    // Minimap
    // ═══════════════════════════════════════════════════════════════
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

    // Init
    // ═══════════════════════════════════════════════════════════════
    render();
    if (nodes.length > 0) zoomFit();
    renderMinimap();
    """
  end

end

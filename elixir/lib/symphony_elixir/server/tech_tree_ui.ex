defmodule SymphonyElixir.Server.TechTreeUI do
  @moduledoc """
  Task lineage visualization for issue lineage.

  Root issues (manually created, no parent) appear on the left.
  Follow-up issues branch to the right, connected by arrows.
  """

  @doc "Render the task lineage HTML page."
  @spec render() :: String.t()
  def render do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Symphony Task Lineage</title>
      <style>
    #{css()}
      </style>
    </head>
    <body>
      <header class="topbar">
        <div class="topbar-left">
          <nav class="breadcrumb"><a href="/board">Board</a><span class="sep">/</span></nav>
          <h1>Task Lineage</h1>
          <select id="project-filter" class="project-select" onchange="filterProject()">
            <option value="">All Projects</option>
          </select>
        </div>
        <div class="topbar-right">
          <span class="legend">
            <span class="legend-item"><span class="dot dot-root"></span> Root</span>
            <span class="legend-item"><span class="dot dot-done"></span> Done</span>
            <span class="legend-item"><span class="dot dot-active"></span> Active</span>
            <span class="legend-item"><span class="dot dot-review"></span> Review</span>
          </span>
        </div>
      </header>

      <div class="tree-viewport" id="viewport">
        <svg class="connectors" id="connectors"></svg>
        <div class="tree-canvas" id="canvas"></div>
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
    UIHelpers.base_css() <> UIHelpers.topbar_css() <>
      ~S"""

      body {
        overflow: hidden;
        height: 100vh;
        display: flex;
        flex-direction: column;
      }

      .project-select {
        background: var(--bg-tertiary);
        color: var(--text-secondary);
        border: 1px solid var(--border);
        border-radius: 6px;
        padding: 4px 8px;
        font-size: 0.8rem;
      }

      .legend {
        display: flex;
        gap: 16px;
        font-size: 0.8rem;
        color: var(--text-muted);
      }
      .legend-item { display: flex; align-items: center; gap: 6px; }
      .dot {
        width: 10px;
        height: 10px;
        border-radius: 50%;
        display: inline-block;
      }
      .dot-root { background: var(--accent); }
      .dot-done { background: var(--green); }
      .dot-active { background: var(--yellow); }
      .dot-review { background: var(--purple); }

      /* Viewport: pannable area */
      .tree-viewport {
        flex: 1;
        overflow: auto;
        position: relative;
        cursor: grab;
      }
      .tree-viewport:active { cursor: grabbing; }

      .connectors {
        position: absolute;
        top: 0;
        left: 0;
        pointer-events: none;
        z-index: 1;
      }

      .tree-canvas {
        position: relative;
        padding: 40px;
        min-width: 100%;
        min-height: 100%;
      }

      /* Node cards */
      .tree-node {
        position: absolute;
        width: 220px;
        background: var(--bg-secondary);
        border: 1px solid var(--border);
        border-radius: 8px;
        padding: 12px;
        cursor: pointer;
        transition: border-color 0.15s, box-shadow 0.15s;
        z-index: 2;
      }
      .tree-node:hover {
        border-color: var(--accent);
        box-shadow: 0 0 0 1px var(--accent);
      }
      .tree-node.state-done { border-left: 3px solid var(--green); }
      .tree-node.state-todo,
      .tree-node.state-in-progress { border-left: 3px solid var(--yellow); }
      .tree-node.state-review { border-left: 3px solid var(--purple); }
      .tree-node.state-archived { border-left: 3px solid #484f58; opacity: 0.6; }
      .tree-node.state-cancelled { border-left: 3px solid var(--red); opacity: 0.5; }
      .tree-node.is-root { border-left: 3px solid var(--accent); }

      .node-identifier {
        font-size: 0.7rem;
        color: var(--text-muted);
        font-weight: 600;
        letter-spacing: 0.03em;
        margin-bottom: 4px;
      }
      .node-title {
        font-size: 0.82rem;
        font-weight: 500;
        color: var(--text-primary);
        line-height: 1.3;
        margin-bottom: 6px;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }
      .node-meta {
        display: flex;
        align-items: center;
        gap: 6px;
        flex-wrap: wrap;
      }
      .node-state {
        font-size: 0.65rem;
        text-transform: uppercase;
        letter-spacing: 0.04em;
        padding: 2px 6px;
        border-radius: 4px;
        font-weight: 600;
      }
      .node-state.done { background: rgba(63,185,80,0.15); color: var(--green); }
      .node-state.todo,
      .node-state.in-progress { background: rgba(210,153,34,0.15); color: var(--yellow); }
      .node-state.review { background: rgba(188,140,255,0.15); color: var(--purple); }
      .node-state.archived { background: rgba(72,79,88,0.25); color: var(--text-muted); }
      .node-state.cancelled { background: rgba(248,81,73,0.15); color: var(--red); }
      .node-state.backlog { background: rgba(139,148,158,0.15); color: var(--text-muted); }

      .node-labels {
        display: flex;
        gap: 4px;
        flex-wrap: wrap;
      }
      .node-label {
        font-size: 0.6rem;
        background: var(--bg-tertiary);
        color: var(--text-muted);
        padding: 1px 5px;
        border-radius: 3px;
      }
      .node-children-count {
        font-size: 0.65rem;
        color: var(--text-muted);
        margin-left: auto;
      }
      .node-age {
        font-size: 0.6rem;
        color: var(--text-muted);
        opacity: 0.7;
      }
      .node-age.stale { color: var(--yellow); opacity: 1; }
      .node-age.old { color: var(--red); opacity: 1; }

      /* Temporal fade — older completed nodes dim */
      .tree-node.temporal-old { opacity: 0.5; }
      .tree-node.temporal-recent { box-shadow: 0 0 0 1px var(--accent); }

      /* Empty state */
      .empty-state {
        display: flex;
        align-items: center;
        justify-content: center;
        height: 60vh;
        color: var(--text-muted);
        font-size: 1rem;
      }
      """
  end

  defp js do
    ~S"""
    const API = '/board/api';
    let allIssues = [];
    let currentProject = '';

    async function loadIssues() {
      const res = await fetch(API + '/issues');
      const data = await res.json();
      allIssues = data.issues || [];
      populateProjectFilter();
      renderTree();
    }

    function populateProjectFilter() {
      const sel = document.getElementById('project-filter');
      fetch(API + '/snapshot').then(function(r) { return r.json(); }).then(function(data) {
        const projs = data.projects || [];
        sel.innerHTML = '<option value="">All Projects</option>';
        projs.forEach(function(p) {
          sel.innerHTML += '<option value="' + p.id + '">' + esc(p.name) + '</option>';
        });
        if (currentProject) sel.value = currentProject;
      }).catch(function() {});
    }

    function filterProject() {
      currentProject = document.getElementById('project-filter').value;
      renderTree();
    }

    function esc(s) {
      if (s == null) return '';
      const d = document.createElement('div');
      d.textContent = s;
      return d.innerHTML;
    }

    function buildTree(issues) {
      const byId = {};
      issues.forEach(function(i) { byId[i.id] = i; });
      const children = {};
      const roots = [];
      issues.forEach(function(i) {
        if (i.parent_issue_id && byId[i.parent_issue_id]) {
          if (!children[i.parent_issue_id]) children[i.parent_issue_id] = [];
          children[i.parent_issue_id].push(i);
        } else {
          roots.push(i);
        }
      });
      const sortByIdent = function(a, b) {
        const na = parseInt((a.identifier || '').split('-').pop()) || 0;
        const nb = parseInt((b.identifier || '').split('-').pop()) || 0;
        return na - nb;
      };
      roots.sort(sortByIdent);
      Object.keys(children).forEach(function(pid) { children[pid].sort(sortByIdent); });
      return { roots: roots, children: children };
    }

    const NODE_W = 220, NODE_H = 90, H_GAP = 80, V_GAP = 20;

    function layoutTree(tree) {
      const nodes = [];
      const subtreeHeights = {};

      function getSubtreeHeight(issue) {
        if (subtreeHeights[issue.id] !== undefined) return subtreeHeights[issue.id];
        const kids = tree.children[issue.id] || [];
        if (kids.length === 0) { subtreeHeights[issue.id] = NODE_H; return NODE_H; }
        let total = 0;
        kids.forEach(function(kid, idx) { if (idx > 0) total += V_GAP; total += getSubtreeHeight(kid); });
        subtreeHeights[issue.id] = Math.max(NODE_H, total);
        return subtreeHeights[issue.id];
      }

      let totalH = 0;
      tree.roots.forEach(function(r, idx) { if (idx > 0) totalH += V_GAP; totalH += getSubtreeHeight(r); });

      function placeNode(issue, depth, yStart, parentId) {
        const subtreeH = subtreeHeights[issue.id];
        const x = depth * (NODE_W + H_GAP);
        const y = yStart + (subtreeH - NODE_H) / 2;
        const kids = tree.children[issue.id] || [];
        nodes.push({ issue: issue, x: x, y: y, depth: depth, parentId: parentId, isRoot: !parentId, childCount: kids.length });
        let childY = yStart;
        kids.forEach(function(kid, idx) { if (idx > 0) childY += V_GAP; placeNode(kid, depth + 1, childY, issue.id); childY += subtreeHeights[kid.id]; });
      }

      let yOff = 0;
      tree.roots.forEach(function(r, idx) { if (idx > 0) yOff += V_GAP; placeNode(r, 0, yOff, null); yOff += subtreeHeights[r.id]; });
      return nodes;
    }

    function renderTree() {
      let issues = allIssues;
      if (currentProject) { issues = issues.filter(function(i) { return i.project_id === currentProject; }); }

      const canvas = document.getElementById('canvas');
      const svg = document.getElementById('connectors');

      if (issues.length === 0) {
        canvas.innerHTML = '<div class="empty-state">No issues to display</div>';
        svg.innerHTML = ''; svg.setAttribute('width', 0); svg.setAttribute('height', 0);
        return;
      }

      const tree = buildTree(issues);
      const nodes = layoutTree(tree);

      let maxX = 0, maxY = 0;
      nodes.forEach(function(n) { if (n.x + NODE_W > maxX) maxX = n.x + NODE_W; if (n.y + NODE_H > maxY) maxY = n.y + NODE_H; });
      maxX += 80; maxY += 80;

      canvas.style.width = maxX + 'px';
      canvas.style.height = maxY + 'px';
      svg.setAttribute('width', maxX);
      svg.setAttribute('height', maxY);

      const posMap = {};
      nodes.forEach(function(n) { posMap[n.issue.id] = { x: n.x, y: n.y }; });

      let paths = '';
      nodes.forEach(function(n) {
        if (!n.parentId || !posMap[n.parentId]) return;
        const parent = posMap[n.parentId];
        const px = parent.x + NODE_W + 40, py = parent.y + NODE_H / 2 + 40;
        const cx = n.x + 40, cy = n.y + NODE_H / 2 + 40;
        const midX = (px + cx) / 2;
        paths += '<path d="M' + px + ' ' + py + ' C' + midX + ' ' + py + ' ' + midX + ' ' + cy + ' ' + cx + ' ' + cy + '" fill="none" stroke="#58687a" stroke-width="2" opacity="0.7"/>';
        paths += '<polygon points="' + cx + ',' + cy + ' ' + (cx - 8) + ',' + (cy - 4) + ' ' + (cx - 8) + ',' + (cy + 4) + '" fill="#58687a" opacity="0.7"/>';
      });
      svg.innerHTML = paths;

      canvas.innerHTML = '';
      nodes.forEach(function(n) {
        const issue = n.issue;
        const stateSlug = (issue.state || '').toLowerCase().replace(/\s+/g, '-');
        let stateClass = 'state-' + stateSlug;
        if (n.isRoot) stateClass += ' is-root';

        let labelsHtml = '';
        if (issue.labels && issue.labels.length > 0) {
          labelsHtml = '<div class="node-labels">' + issue.labels.slice(0, 3).map(function(l) { return '<span class="node-label">' + esc(l) + '</span>'; }).join('') + '</div>';
        }

        let childBadge = '';
        if (n.childCount > 0) {
          childBadge = '<span class="node-children-count">' + n.childCount + ' follow-up' + (n.childCount > 1 ? 's' : '') + '</span>';
        }

        // Temporal encoding (#35)
        var ageHtml = '';
        var temporalClass = '';
        if (issue.created_at) {
          var days = Math.floor((Date.now() - new Date(issue.created_at).getTime()) / 86400000);
          var ageClass = days > 30 ? 'old' : (days > 14 ? 'stale' : '');
          ageHtml = '<span class="node-age ' + ageClass + '">' + (days > 0 ? days + 'd ago' : 'today') + '</span>';
          // Temporal visual encoding for completed items
          var isDone = stateSlug === 'done' || stateSlug === 'archived';
          if (isDone && days > 30) temporalClass = ' temporal-old';
          else if (days <= 3) temporalClass = ' temporal-recent';
        }

        const div = document.createElement('div');
        div.className = 'tree-node ' + stateClass + temporalClass;
        div.style.left = (n.x + 40) + 'px';
        div.style.top = (n.y + 40) + 'px';
        div.onclick = function() { window.location.href = '/board/issues/' + issue.id; };
        div.innerHTML =
          '<div class="node-identifier">' + esc(issue.identifier) + ' ' + ageHtml + '</div>' +
          '<div class="node-title">' + esc(issue.title) + '</div>' +
          '<div class="node-meta"><span class="node-state ' + stateSlug + '">' + esc(issue.state) + '</span>' + labelsHtml + childBadge + '</div>';
        canvas.appendChild(div);
      });
    }

    (function() {
      const vp = document.getElementById('viewport');
      let dragging = false, startX, startY, scrollL, scrollT;
      vp.addEventListener('mousedown', function(e) {
        if (e.target.closest('.tree-node')) return;
        dragging = true; startX = e.clientX; startY = e.clientY; scrollL = vp.scrollLeft; scrollT = vp.scrollTop;
      });
      window.addEventListener('mousemove', function(e) { if (!dragging) return; vp.scrollLeft = scrollL - (e.clientX - startX); vp.scrollTop = scrollT - (e.clientY - startY); });
      window.addEventListener('mouseup', function() { dragging = false; });
    })();

    loadIssues();
    """
  end
end

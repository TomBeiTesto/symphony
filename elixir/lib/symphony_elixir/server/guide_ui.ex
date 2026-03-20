defmodule SymphonyElixir.Server.GuideUI do
  @moduledoc """
  Interactive concept map and help guide for Symphony.
  Renders a canvas-based graph of all Symphony concepts with click-to-explore detail panels.
  """

  alias SymphonyElixir.Server.UIHelpers

  @spec render() :: String.t()
  def render do
    body = """
    <div class="guide-wrap">
      <div class="guide-sidebar" id="guide-sidebar">
        <div class="gs-header">
          <h3>Symphony Guide</h3>
          <p class="gs-sub">Click a concept to explore. Press <kbd>?</kbd> for explain mode on any page.</p>
        </div>
        <div class="gs-search">
          <input type="text" id="guide-search" placeholder="Search concepts..." autocomplete="off">
        </div>
        <div id="gs-list" class="gs-list"></div>
        <div id="gs-detail" class="gs-detail" style="display:none"></div>
      </div>
      <div class="guide-canvas-wrap">
        <canvas id="guide-canvas"></canvas>
        <div class="guide-legend" id="guide-legend"></div>
      </div>
    </div>
    <script>
    #{UIHelpers.esc_js()}
    #{guide_js()}
    </script>
    """

    UIHelpers.page_template("Symphony Guide", "guide", guide_css(), body)
  end

  defp guide_css do
    ~S"""
    .guide-wrap {
      display: flex; height: calc(100vh - 48px); overflow: hidden;
    }
    .guide-sidebar {
      width: 340px; min-width: 340px; background: var(--bg-secondary);
      border-right: 1px solid var(--border); display: flex; flex-direction: column;
      overflow: hidden;
    }
    .gs-header { padding: 20px 20px 12px; }
    .gs-header h3 { margin: 0 0 4px; font-size: 1.1rem; color: var(--text-primary); }
    .gs-sub { margin: 0; font-size: 0.78rem; color: var(--text-muted); line-height: 1.4; }
    .gs-sub kbd {
      background: var(--bg-tertiary); border: 1px solid var(--border);
      border-radius: 3px; padding: 1px 5px; font-size: 0.72rem; font-family: inherit;
    }
    .gs-search { padding: 0 20px 12px; }
    .gs-search input {
      width: 100%; padding: 7px 10px; background: var(--bg-tertiary);
      border: 1px solid var(--border); border-radius: var(--radius-sm);
      color: var(--text-primary); font-size: 0.82rem;
    }
    .gs-search input:focus { outline: none; border-color: var(--accent); }
    .gs-list {
      flex: 1; overflow-y: auto; padding: 0 12px 12px;
    }
    .gs-item {
      padding: 10px 12px; border-radius: var(--radius-sm); cursor: pointer;
      margin-bottom: 2px; display: flex; align-items: center; gap: 10px;
      transition: background var(--transition);
    }
    .gs-item:hover { background: var(--bg-hover); }
    .gs-item.active { background: rgba(88,166,255,0.12); }
    .gs-item-dot {
      width: 10px; height: 10px; border-radius: 50%; flex-shrink: 0;
    }
    .gs-item-info { min-width: 0; }
    .gs-item-name { font-weight: 600; font-size: 0.85rem; color: var(--text-primary); }
    .gs-item-desc {
      font-size: 0.72rem; color: var(--text-muted); white-space: nowrap;
      overflow: hidden; text-overflow: ellipsis;
    }
    .gs-detail {
      padding: 20px; overflow-y: auto; border-top: 1px solid var(--border);
      animation: gs-slide-in 200ms ease;
    }
    @keyframes gs-slide-in {
      from { opacity: 0; transform: translateY(8px); }
      to { opacity: 1; transform: translateY(0); }
    }
    .gs-detail-title {
      font-size: 1rem; font-weight: 700; margin: 0 0 12px;
      display: flex; align-items: center; gap: 8px;
    }
    .gs-detail-dot { width: 12px; height: 12px; border-radius: 50%; }
    .gs-detail h4 {
      font-size: 0.75rem; font-weight: 600; color: var(--text-muted);
      text-transform: uppercase; letter-spacing: 0.04em;
      margin: 14px 0 4px;
    }
    .gs-detail p { margin: 0 0 6px; font-size: 0.84rem; color: var(--text-secondary); line-height: 1.55; }
    .gs-detail .gs-link {
      display: inline-block; margin-top: 12px; padding: 5px 12px;
      background: var(--bg-tertiary); border: 1px solid var(--border);
      border-radius: var(--radius-sm); color: var(--accent); font-size: 0.78rem;
      text-decoration: none; transition: all var(--transition);
    }
    .gs-detail .gs-link:hover { background: var(--bg-hover); border-color: var(--accent); }
    .gs-detail .gs-conn-list { list-style: none; padding: 0; margin: 4px 0 0; }
    .gs-detail .gs-conn-list li {
      font-size: 0.8rem; color: var(--purple); padding: 2px 0;
      cursor: pointer;
    }
    .gs-detail .gs-conn-list li:hover { color: var(--accent); text-decoration: underline; }
    .gs-detail .gs-back {
      background: none; border: none; color: var(--text-muted); cursor: pointer;
      font-size: 0.78rem; padding: 0; margin-bottom: 8px;
    }
    .gs-detail .gs-back:hover { color: var(--accent); }
    .guide-canvas-wrap {
      flex: 1; position: relative; background: var(--bg-primary);
      overflow: hidden;
    }
    #guide-canvas { width: 100%; height: 100%; display: block; }
    .guide-legend {
      position: absolute; bottom: 16px; left: 16px;
      background: var(--bg-secondary); border: 1px solid var(--border);
      border-radius: var(--radius-sm); padding: 10px 14px;
      font-size: 0.72rem; color: var(--text-muted); display: flex; gap: 14px;
      flex-wrap: wrap;
    }
    .legend-item { display: flex; align-items: center; gap: 5px; }
    .legend-dot { width: 8px; height: 8px; border-radius: 50%; }
    """
  end

  defp guide_js do
    ~S"""
    (function() {
      // ── Concept graph data ──
      var concepts = [
        {
          id: 'products', label: 'Products', color: '#58a6ff', category: 'core',
          short: 'Top-level containers for your work',
          what: 'A Product groups related Projects, Issues, and Pipelines under one umbrella. Think of it as a "workspace" for a business domain or application.',
          why: 'When you have multiple repos or services that form one product, grouping them lets pipelines and agents work across the full scope.',
          examples: 'An e-commerce platform might be one Product containing a frontend repo, API repo, and database migrations repo.',
          link: '/board'
        },
        {
          id: 'projects', label: 'Projects', color: '#3fb950', category: 'core',
          short: 'Git repositories linked to a product',
          what: 'A Project is a single git repository. It has a path on disk and optionally a remote URL. Projects belong to a Product.',
          why: 'Agents need to know which codebase to work in. The project path becomes the agent\'s workspace.',
          examples: 'Your API server repo at /repos/api-server, your frontend at /repos/web-client — each is a separate Project under the same Product.',
          link: '/board'
        },
        {
          id: 'issues', label: 'Issues', color: '#d29922', category: 'core',
          short: 'Trackable work items on the kanban board',
          what: 'An Issue is a task with a title, description, state (Todo, In Progress, Done, etc.), priority, labels, and optional skill assignments. Issues live on the Kanban board.',
          why: 'Issues are what agents actually work on. When the Orchestrator dispatches an agent, it gives it an Issue to complete.',
          examples: 'Issue: "Extract Architecture" — the agent reads the codebase and writes an architecture document.',
          link: '/board'
        },
        {
          id: 'pipelines', label: 'Pipelines', color: '#bc8cff', category: 'automation',
          short: 'Automated multi-step AI workflows',
          what: 'A Pipeline is a directed graph (DAG) of Nodes connected by edges. When you start a run, Symphony walks the graph and executes each node in order, respecting dependencies.',
          why: 'Complex tasks need multiple steps: analyze → plan → implement → review → test. A pipeline automates this entire workflow with gates for human review.',
          examples: 'Feature Implementation pipeline: KB Context → Impact Analysis → Plan → Human Gate → Code → Code Review → Tests → KB Sync.',
          link: '/board/pipeline'
        },
        {
          id: 'nodes', label: 'Pipeline Nodes', color: '#bc8cff', category: 'automation',
          short: 'Individual steps within a pipeline',
          what: 'Nodes are the building blocks of pipelines. Types: Issue (creates/runs an agent task), Human Gate (pause for review), Quality Gate (automated checks), KB Sync (sync to knowledge base), Loop, Integration.',
          why: 'Different steps need different behavior. Issue nodes do work, gates ensure quality, KB sync preserves knowledge.',
          examples: 'An Issue node labeled "Code Implementation" creates an issue and dispatches an agent. A Human Gate pauses for your code review.',
          link: '/board/pipeline'
        },
        {
          id: 'skills', label: 'Skills', color: '#f85149', category: 'ai',
          short: 'Reusable AI capabilities and instructions',
          what: 'A Skill is a document of rules and procedures that gets injected into an agent\'s prompt. Skills shape how agents work — they encode best practices, processes, and constraints.',
          why: 'Without skills, agents use generic behavior. Skills make them follow YOUR process: your testing standards, your code review checklist, your documentation format.',
          examples: '"Verification" skill: forces agents to verify after every change. "UI Design" skill: enforces spacing scales and responsive behavior.',
          link: '/board/skills'
        },
        {
          id: 'skillgroups', label: 'Skill Groups', color: '#f85149', category: 'ai',
          short: 'Bundles of skills applied together',
          what: 'A Skill Group is a named collection of skills. Assigning a group to an issue gives the agent all the skills in that bundle.',
          why: 'Instead of picking 5 individual skills every time, assign "Full Discipline" and get verification + debugging + TDD + planning + code review.',
          examples: '"Quality Essentials" = verification + code-review. "Feature Implementation" = all 7 feature pipeline skills.',
          link: '/board/skills'
        },
        {
          id: 'orchestrator', label: 'Orchestrator', color: '#d18616', category: 'ai',
          short: 'Dispatches and manages AI agents',
          what: 'The Orchestrator is a background process that watches for ready issues and spawns AI agents to work on them. It manages concurrency, retries, and plan review.',
          why: 'You don\'t manually start agents. The orchestrator picks up issues as they become ready and handles the full lifecycle.',
          examples: 'Move an issue to "Todo" → Orchestrator sees it → spawns Claude agent → agent works → updates issue to "Done".',
          link: '/board/settings'
        },
        {
          id: 'kb', label: 'Knowledge Base', color: '#3fb950', category: 'knowledge',
          short: 'Synced documentation vault for AI context',
          what: 'The Knowledge Base is a local folder (Obsidian vault style) where structured notes about your product live — architecture, business logic, constraints, workflows.',
          why: 'Agents have no memory between runs. The KB gives them persistent context: "here\'s how our auth system works" so they don\'t re-discover it every time.',
          examples: 'After running "Extract Product Knowledge", your KB has architecture.md, business-logic.md, constraints.md — agents read these before making changes.',
          link: '/board/settings'
        },
        {
          id: 'settings', label: 'Settings', color: '#8b949e', category: 'config',
          short: 'Configuration for providers and integrations',
          what: 'Global configuration: AI provider API keys, agent model selection, workspace root, Knowledge Base vault path, GitLab integration, and feature flags.',
          why: 'Everything is configurable. Different products can use different models, different KB vaults, different CI/CD integrations.',
          examples: 'Set ANTHROPIC_API_KEY, choose claude-sonnet for fast tasks and claude-opus for complex ones, point KB to your Obsidian vault.',
          link: '/board/settings'
        }
      ];

      var edges = [
        { from: 'products', to: 'projects', label: 'contains' },
        { from: 'products', to: 'issues', label: 'tracks' },
        { from: 'products', to: 'pipelines', label: 'owns' },
        { from: 'pipelines', to: 'nodes', label: 'composed of' },
        { from: 'nodes', to: 'skills', label: 'uses' },
        { from: 'nodes', to: 'issues', label: 'creates' },
        { from: 'issues', to: 'orchestrator', label: 'dispatched to' },
        { from: 'orchestrator', to: 'skills', label: 'invokes' },
        { from: 'kb', to: 'orchestrator', label: 'informs' },
        { from: 'settings', to: 'orchestrator', label: 'configures' },
        { from: 'skills', to: 'skillgroups', label: 'bundled into' },
        { from: 'pipelines', to: 'kb', label: 'syncs to' }
      ];

      // ── Pre-computed layout (circular with Products at top) ──
      var nodePositions = {
        products:     { x: 0.50, y: 0.10 },
        projects:     { x: 0.22, y: 0.25 },
        issues:       { x: 0.50, y: 0.30 },
        pipelines:    { x: 0.78, y: 0.25 },
        nodes:        { x: 0.82, y: 0.50 },
        skills:       { x: 0.60, y: 0.62 },
        skillgroups:  { x: 0.40, y: 0.75 },
        orchestrator: { x: 0.30, y: 0.50 },
        kb:           { x: 0.14, y: 0.65 },
        settings:     { x: 0.14, y: 0.40 }
      };

      var canvas = document.getElementById('guide-canvas');
      var ctx = canvas.getContext('2d');
      var dpr = window.devicePixelRatio || 1;
      var W, H;
      var hoveredNode = null;
      var selectedNode = null;
      var animOffset = 0;
      var nodeRadius = 40;

      function resize() {
        var rect = canvas.parentElement.getBoundingClientRect();
        W = rect.width; H = rect.height;
        canvas.width = W * dpr; canvas.height = H * dpr;
        canvas.style.width = W + 'px'; canvas.style.height = H + 'px';
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      }

      function getNodePos(id) {
        var p = nodePositions[id];
        return { x: p.x * W, y: p.y * H };
      }

      function drawEdge(e, highlight) {
        var from = getNodePos(e.from);
        var to = getNodePos(e.to);
        var dx = to.x - from.x, dy = to.y - from.y;
        var dist = Math.sqrt(dx*dx + dy*dy);
        var nx = dx/dist, ny = dy/dist;
        var sx = from.x + nx * nodeRadius, sy = from.y + ny * nodeRadius;
        var ex = to.x - nx * nodeRadius, ey = to.y - ny * nodeRadius;

        // Bezier control point (slight curve)
        var mx = (sx + ex) / 2, my = (sy + ey) / 2;
        var perpX = -ny * 30, perpY = nx * 30;
        var cx = mx + perpX, cy = my + perpY;

        ctx.beginPath();
        ctx.moveTo(sx, sy);
        ctx.quadraticCurveTo(cx, cy, ex, ey);
        ctx.strokeStyle = highlight ? 'rgba(88,166,255,0.6)' : 'rgba(110,118,129,0.25)';
        ctx.lineWidth = highlight ? 2.5 : 1.5;
        if (!highlight) {
          ctx.setLineDash([6, 4]);
          ctx.lineDashOffset = -animOffset;
        } else {
          ctx.setLineDash([]);
        }
        ctx.stroke();
        ctx.setLineDash([]);

        // Arrowhead
        var t = 0.95;
        var ax = (1-t)*(1-t)*sx + 2*(1-t)*t*cx + t*t*ex;
        var ay = (1-t)*(1-t)*sy + 2*(1-t)*t*cy + t*t*ey;
        var angle = Math.atan2(ey - ay, ex - ax);
        var aSize = highlight ? 9 : 7;
        ctx.beginPath();
        ctx.moveTo(ex, ey);
        ctx.lineTo(ex - aSize*Math.cos(angle-0.4), ey - aSize*Math.sin(angle-0.4));
        ctx.lineTo(ex - aSize*Math.cos(angle+0.4), ey - aSize*Math.sin(angle+0.4));
        ctx.closePath();
        ctx.fillStyle = highlight ? 'rgba(88,166,255,0.7)' : 'rgba(110,118,129,0.35)';
        ctx.fill();

        // Edge label
        var lx = (1-0.5)*(1-0.5)*sx + 2*(1-0.5)*0.5*cx + 0.5*0.5*ex;
        var ly = (1-0.5)*(1-0.5)*sy + 2*(1-0.5)*0.5*cy + 0.5*0.5*ey;
        ctx.font = '11px -apple-system, BlinkMacSystemFont, sans-serif';
        ctx.fillStyle = highlight ? 'rgba(88,166,255,0.8)' : 'rgba(139,148,158,0.6)';
        ctx.textAlign = 'center';
        ctx.fillText(e.label, lx, ly - 5);
      }

      function drawNode(c) {
        var pos = getNodePos(c.id);
        var isHovered = hoveredNode === c.id;
        var isSelected = selectedNode === c.id;
        var r = nodeRadius;

        // Glow
        if (isHovered || isSelected) {
          ctx.beginPath();
          ctx.arc(pos.x, pos.y, r + 8, 0, Math.PI * 2);
          var glow = ctx.createRadialGradient(pos.x, pos.y, r, pos.x, pos.y, r + 12);
          glow.addColorStop(0, c.color + '40');
          glow.addColorStop(1, c.color + '00');
          ctx.fillStyle = glow;
          ctx.fill();
        }

        // Circle
        ctx.beginPath();
        ctx.arc(pos.x, pos.y, r, 0, Math.PI * 2);
        ctx.fillStyle = isSelected ? c.color + '30' : (isHovered ? c.color + '20' : 'rgba(22,27,34,0.9)');
        ctx.fill();
        ctx.strokeStyle = isSelected ? c.color : (isHovered ? c.color + 'cc' : c.color + '60');
        ctx.lineWidth = isSelected ? 2.5 : (isHovered ? 2 : 1.5);
        ctx.stroke();

        // Label
        ctx.font = (isHovered || isSelected ? 'bold ' : '') + '13px -apple-system, BlinkMacSystemFont, sans-serif';
        ctx.fillStyle = isSelected ? c.color : (isHovered ? '#e6edf3' : '#c9d1d9');
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';

        // Word wrap in circle
        var words = c.label.split(' ');
        if (words.length > 1) {
          ctx.fillText(words[0], pos.x, pos.y - 7);
          ctx.fillText(words.slice(1).join(' '), pos.x, pos.y + 9);
        } else {
          ctx.fillText(c.label, pos.x, pos.y);
        }
      }

      function draw() {
        ctx.clearRect(0, 0, W, H);

        // Draw edges
        edges.forEach(function(e) {
          var hl = selectedNode && (e.from === selectedNode || e.to === selectedNode);
          drawEdge(e, hl);
        });

        // Draw non-highlighted edges first, then highlighted on top
        concepts.forEach(function(c) { drawNode(c); });
      }

      function animate() {
        animOffset = (animOffset + 0.3) % 100;
        draw();
        requestAnimationFrame(animate);
      }

      // ── Hit detection ──
      function hitTest(mx, my) {
        for (var i = concepts.length - 1; i >= 0; i--) {
          var pos = getNodePos(concepts[i].id);
          var dx = mx - pos.x, dy = my - pos.y;
          if (dx*dx + dy*dy <= nodeRadius * nodeRadius) return concepts[i].id;
        }
        return null;
      }

      canvas.addEventListener('mousemove', function(e) {
        var rect = canvas.getBoundingClientRect();
        hoveredNode = hitTest(e.clientX - rect.left, e.clientY - rect.top);
        canvas.style.cursor = hoveredNode ? 'pointer' : 'default';
      });

      canvas.addEventListener('click', function(e) {
        var rect = canvas.getBoundingClientRect();
        var hit = hitTest(e.clientX - rect.left, e.clientY - rect.top);
        if (hit) {
          selectedNode = hit;
          showDetail(hit);
        }
      });

      // ── Sidebar list ──
      var listEl = document.getElementById('gs-list');
      var detailEl = document.getElementById('gs-detail');
      var searchEl = document.getElementById('guide-search');

      function renderList(filter) {
        var q = (filter || '').toLowerCase();
        var html = '';
        concepts.forEach(function(c) {
          if (q && c.label.toLowerCase().indexOf(q) === -1 && c.short.toLowerCase().indexOf(q) === -1) return;
          var active = selectedNode === c.id ? ' active' : '';
          html += '<div class="gs-item' + active + '" data-id="' + c.id + '" onclick="window._selectConcept(\'' + c.id + '\')">';
          html += '<div class="gs-item-dot" style="background:' + c.color + '"></div>';
          html += '<div class="gs-item-info"><div class="gs-item-name">' + esc(c.label) + '</div>';
          html += '<div class="gs-item-desc">' + esc(c.short) + '</div></div></div>';
        });
        listEl.innerHTML = html;
      }

      window._selectConcept = function(id) {
        selectedNode = id;
        showDetail(id);
        renderList(searchEl.value);
      };

      searchEl.addEventListener('input', function() {
        renderList(this.value);
      });

      function showDetail(id) {
        var c = concepts.find(function(n) { return n.id === id; });
        if (!c) return;

        // Find connections
        var connected = [];
        edges.forEach(function(e) {
          if (e.from === id) {
            var target = concepts.find(function(n) { return n.id === e.to; });
            if (target) connected.push({ label: e.label + ' → ' + target.label, id: target.id });
          }
          if (e.to === id) {
            var source = concepts.find(function(n) { return n.id === e.from; });
            if (source) connected.push({ label: source.label + ' → ' + e.label, id: source.id });
          }
        });

        var html = '<button class="gs-back" onclick="window._closeDetail()">← All concepts</button>';
        html += '<div class="gs-detail-title"><div class="gs-detail-dot" style="background:' + c.color + '"></div>' + esc(c.label) + '</div>';
        html += '<h4>What it is</h4><p>' + esc(c.what) + '</p>';
        html += '<h4>Why use it</h4><p>' + esc(c.why) + '</p>';
        if (c.examples) html += '<h4>Example</h4><p>' + esc(c.examples) + '</p>';

        if (connected.length) {
          html += '<h4>Connections</h4><ul class="gs-conn-list">';
          connected.forEach(function(conn) {
            html += '<li onclick="window._selectConcept(\'' + conn.id + '\')">' + esc(conn.label) + '</li>';
          });
          html += '</ul>';
        }

        if (c.link) html += '<a class="gs-link" href="' + c.link + '">Open in Symphony →</a>';

        listEl.style.display = 'none';
        detailEl.innerHTML = html;
        detailEl.style.display = 'block';
        renderList(searchEl.value);
      }

      window._closeDetail = function() {
        selectedNode = null;
        detailEl.style.display = 'none';
        listEl.style.display = 'block';
        renderList(searchEl.value);
      };

      // ── Legend ──
      var categories = {core: 'Core', automation: 'Automation', ai: 'AI & Skills', knowledge: 'Knowledge', config: 'Config'};
      var catColors = {core: '#58a6ff', automation: '#bc8cff', ai: '#f85149', knowledge: '#3fb950', config: '#8b949e'};
      var legendHtml = '';
      Object.keys(categories).forEach(function(k) {
        legendHtml += '<div class="legend-item"><div class="legend-dot" style="background:' + catColors[k] + '"></div>' + categories[k] + '</div>';
      });
      document.getElementById('guide-legend').innerHTML = legendHtml;

      // ── Init ──
      resize();
      renderList('');
      animate();
      window.addEventListener('resize', function() { resize(); });
    })();
    """
  end
end

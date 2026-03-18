defmodule SymphonyElixir.Server.UIHelpers do
  @moduledoc """
  Shared utilities for server-rendered UI pages: HTML escaping, CSS theme, JS helpers.
  """

  @doc "HTML-escape a value for safe interpolation."
  @spec esc(term()) :: String.t()
  def esc(nil), do: ""
  def esc(val) when is_atom(val), do: esc(Atom.to_string(val))

  def esc(val) when is_binary(val) do
    val
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  def esc(val), do: esc(to_string(val))

  @doc "CSS custom properties for the shared dark theme."
  @spec theme_css() :: String.t()
  def theme_css do
    ~S"""
    :root {
      --bg-primary: #0d1117;
      --bg-secondary: #161b22;
      --bg-tertiary: #1c2128;
      --bg-hover: #1f2937;
      --border: #30363d;
      --border-light: #21262d;
      --text-primary: #e6edf3;
      --text-secondary: #c9d1d9;
      --text-muted: #8b949e;
      --accent: #58a6ff;
      --accent-hover: #79c0ff;
      --green: #3fb950;
      --yellow: #d29922;
      --red: #f85149;
      --purple: #bc8cff;
      --orange: #d18616;
      --radius: 8px;
      --radius-sm: 6px;
      --shadow: 0 8px 24px rgba(0,0,0,0.4);
      --transition: 150ms ease;
    }
    """
  end

  @doc "Shared JS `esc()` function for client-side HTML escaping."
  @spec esc_js() :: String.t()
  def esc_js do
    ~S"""
    function esc(s) {
      if (s == null) return '';
      var d = document.createElement('div');
      d.textContent = s;
      return d.innerHTML;
    }
    """
  end

  @doc "Shared JS color maps for issue states and priorities."
  @spec color_maps_js() :: String.t()
  def color_maps_js do
    ~S"""
    const COLUMN_COLORS = {
      'backlog': '#8b949e', 'todo': '#d29922', 'in progress': '#58a6ff',
      'review': '#bc8cff', 'done': '#3fb950', 'archived': '#484f58', 'cancelled': '#f85149'
    };
    const PRIORITY_COLORS = { 1: '#f85149', 2: '#d18616', 3: '#d29922', 4: '#58a6ff' };
    function stateColor(state) { return COLUMN_COLORS[(state || '').toLowerCase()] || '#8b949e'; }
    """
  end

  @doc "Shared JS markdown renderer supporting headings, bold, italic, code blocks, tables, lists, blockquotes, links, and horizontal rules."
  @spec markdown_js() :: String.t()
  def markdown_js do
    ~S"""
    function renderMarkdown(text) {
      var html = esc(text);
      // Code blocks (``` ... ```)
      html = html.replace(/```(\w*)\n([\s\S]*?)```/g, function(m, lang, code) {
        return '<pre><code>' + code + '</code></pre>';
      });
      // Tables
      html = html.replace(/^(\|.+\|)\n(\|[-| :]+\|)\n((?:\|.+\|\n?)+)/gm, function(m, header, sep, body) {
        var ths = header.split('|').filter(function(c){return c.trim();}).map(function(c){return '<th>'+c.trim()+'</th>';}).join('');
        var rows = body.trim().split('\n').map(function(row) {
          var tds = row.split('|').filter(function(c){return c.trim();}).map(function(c){return '<td>'+c.trim()+'</td>';}).join('');
          return '<tr>' + tds + '</tr>';
        }).join('');
        return '<table><thead><tr>' + ths + '</tr></thead><tbody>' + rows + '</tbody></table>';
      });
      // Headers
      html = html.replace(/^#### (.+)$/gm, '<h4>$1</h4>');
      html = html.replace(/^### (.+)$/gm, '<h3>$1</h3>');
      html = html.replace(/^## (.+)$/gm, '<h2>$1</h2>');
      html = html.replace(/^# (.+)$/gm, '<h1>$1</h1>');
      // Horizontal rule
      html = html.replace(/^---+$/gm, '<hr>');
      // Bold and italic
      html = html.replace(/\*\*\*(.+?)\*\*\*/g, '<strong><em>$1</em></strong>');
      html = html.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
      html = html.replace(/\*(.+?)\*/g, '<em>$1</em>');
      // Inline code
      html = html.replace(/`([^`]+)`/g, '<code>$1</code>');
      // Links
      html = html.replace(/\[([^\]]+)\]\(([^)]+)\)/g, function(_, text, url) {
        if (/^(https?:\/\/|mailto:|\/|#)/.test(url)) {
          return '<a href="' + url + '" target="_blank" rel="noopener">' + text + '</a>';
        }
        return text;
      });
      // Blockquotes
      html = html.replace(/^&gt; (.+)$/gm, '<blockquote>$1</blockquote>');
      // Unordered lists
      html = html.replace(/^- (.+)$/gm, '<li>$1</li>');
      html = html.replace(/((?:<li>.*<\/li>\n?)+)/g, '<ul>$1</ul>');
      // Ordered lists
      html = html.replace(/^\d+\. (.+)$/gm, '<li>$1</li>');
      // Paragraphs
      html = html.replace(/\n\n/g, '</p><p>');
      html = html.replace(/\n/g, '<br>');
      // Clean up <br> inside block elements
      html = html.replace(/<br>(<\/?(?:h[1-4]|ul|ol|li|pre|blockquote|table|thead|tbody|tr|th|td|hr))/g, '$1');
      html = html.replace(/(<\/?(?:h[1-4]|ul|ol|li|pre|blockquote|table|thead|tbody|tr|th|td|hr)>)<br>/g, '$1');
      html = '<p>' + html + '</p>';
      html = html.replace(/<p>\s*<\/p>/g, '');
      return html;
    }
    """
  end

  @doc "Shared CSS for rendered markdown content."
  @spec markdown_css() :: String.t()
  def markdown_css do
    ~S"""
      .markdown-body h1, .markdown-body h2, .markdown-body h3, .markdown-body h4 { color: var(--text-primary); margin: 16px 0 8px; }
      .markdown-body h1 { font-size: 1.3rem; border-bottom: 1px solid var(--border); padding-bottom: 6px; }
      .markdown-body h2 { font-size: 1.1rem; border-bottom: 1px solid var(--border); padding-bottom: 4px; }
      .markdown-body h3 { font-size: 0.95rem; }
      .markdown-body h4 { font-size: 0.88rem; color: var(--text-secondary); }
      .markdown-body p { margin: 6px 0; line-height: 1.55; }
      .markdown-body strong { color: var(--text-primary); }
      .markdown-body code { background: var(--bg-hover); padding: 1px 5px; border-radius: 3px; font-size: 0.82rem; font-family: 'SF Mono', 'Fira Code', monospace; }
      .markdown-body pre { background: var(--bg-hover); padding: 12px; border-radius: 6px; overflow-x: auto; margin: 8px 0; }
      .markdown-body pre code { background: none; padding: 0; font-size: 0.8rem; line-height: 1.5; }
      .markdown-body ul, .markdown-body ol { padding-left: 20px; margin: 6px 0; }
      .markdown-body li { margin: 3px 0; line-height: 1.5; }
      .markdown-body blockquote { border-left: 3px solid var(--accent); padding: 4px 12px; margin: 8px 0; color: var(--text-secondary); background: rgba(88,166,255,0.05); border-radius: 0 4px 4px 0; }
      .markdown-body table { border-collapse: collapse; width: 100%; margin: 8px 0; font-size: 0.82rem; }
      .markdown-body th, .markdown-body td { border: 1px solid var(--border); padding: 6px 10px; text-align: left; }
      .markdown-body th { background: var(--bg-hover); font-weight: 600; color: var(--text-primary); }
      .markdown-body hr { border: none; border-top: 1px solid var(--border); margin: 12px 0; }
      .markdown-body a { color: var(--accent); text-decoration: none; }
      .markdown-body a:hover { text-decoration: underline; }
    """
  end

  @doc "Shared base CSS reset, body, and scrollbar styles."
  @spec base_css() :: String.t()
  def base_css do
    theme_css() <>
      ~S"""

      * { box-sizing: border-box; margin: 0; padding: 0; }

      body {
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans', Helvetica, Arial, sans-serif;
        background: var(--bg-primary);
        color: var(--text-primary);
        font-size: 14px;
      }

      ::-webkit-scrollbar { width: 6px; height: 6px; }
      ::-webkit-scrollbar-track { background: transparent; }
      ::-webkit-scrollbar-thumb { background: var(--border); border-radius: 3px; }
      ::-webkit-scrollbar-thumb:hover { background: var(--text-muted); }
      """
  end

  @doc "Shared topbar CSS used across all pages."
  @spec topbar_css() :: String.t()
  def topbar_css do
    ~S"""
      .topbar {
        display: flex; align-items: center; justify-content: space-between;
        padding: 10px 20px; border-bottom: 1px solid var(--border);
        background: var(--bg-secondary); flex-shrink: 0; z-index: 10;
      }
      .topbar-left { display: flex; align-items: center; gap: 10px; }
      .topbar-left h1 { font-size: 1.05rem; font-weight: 600; color: var(--text-primary); }
      .topbar-right { display: flex; align-items: center; gap: 6px; }
      .topbar-nav { display: flex; align-items: center; gap: 2px; margin-left: 8px; }
      .topbar-divider { width: 1px; height: 20px; background: var(--border); margin: 0 6px; }
      .logo { color: var(--accent); }
      .back-link { color: var(--text-muted); text-decoration: none; font-size: 0.85rem; padding: 4px 8px; border-radius: 4px; }
      .back-link:hover { color: var(--accent); background: var(--bg-hover); }
      .breadcrumb { display: flex; align-items: center; gap: 6px; font-size: 0.85rem; color: var(--text-muted); }
      .breadcrumb a { color: var(--text-muted); text-decoration: none; }
      .breadcrumb a:hover { color: var(--accent); }
      .breadcrumb .sep { opacity: 0.4; }
      .pipeline-run-dot {
        display: inline-block; width: 7px; height: 7px; border-radius: 50%;
        background: var(--accent); margin-left: 4px; vertical-align: middle;
        animation: pulse 2s infinite;
      }
    """
  end

  @doc "Shared JS snippet that checks for active pipeline runs and shows indicator dot."
  @spec pipeline_indicator_js() :: String.t()
  def pipeline_indicator_js do
    ~S"""
    (function() {
      var dot = document.getElementById('pipeline-run-indicator');
      if (!dot) return;
      function check() {
        fetch('/board/api/pipeline-runs/active').then(function(r) { return r.json(); }).then(function(d) {
          dot.style.display = (d.runs && d.runs.length > 0) ? 'inline-block' : 'none';
          dot.title = (d.runs && d.runs.length > 0) ? d.runs.length + ' pipeline(s) running' : '';
        }).catch(function() {});
      }
      check();
      setInterval(check, 10000);
    })();
    """
  end

  @doc "Shared button CSS."
  @spec button_css() :: String.t()
  def button_css do
    ~S"""
      .btn {
        display: inline-flex; align-items: center; gap: 5px;
        padding: 5px 12px; border-radius: var(--radius-sm);
        font-size: 0.8rem; font-weight: 500; cursor: pointer;
        border: 1px solid transparent; transition: all var(--transition);
        text-decoration: none; white-space: nowrap;
      }
      .btn-primary { background: var(--accent); color: #fff; border-color: var(--accent); }
      .btn-primary:hover { background: var(--accent-hover); }
      .btn-ghost { background: transparent; color: var(--text-secondary); border-color: var(--border); }
      .btn-ghost:hover { color: var(--text-primary); background: var(--bg-hover); }
      .btn-accent { background: var(--purple); color: #fff; border-color: var(--purple); }
      .btn-accent:hover { opacity: 0.9; }
      .btn-accent-soft { background: rgba(188,140,255,0.15); color: var(--purple); border: 1px solid rgba(188,140,255,0.3); }
      .btn-accent-soft:hover { background: rgba(188,140,255,0.25); }
      .btn-danger { background: transparent; color: var(--red); border-color: var(--red); }
      .btn-danger:hover { background: var(--red); color: #fff; }
      .btn-sm { padding: 3px 8px; font-size: 0.75rem; }
      .btn-icon {
        background: none; border: none; color: var(--text-secondary);
        font-size: 1.4rem; cursor: pointer; padding: 0 4px;
        line-height: 1; transition: color var(--transition);
      }
      .btn-icon:hover { color: var(--text-primary); }
    """
  end

  @doc "Shared form CSS."
  @spec form_css() :: String.t()
  def form_css do
    ~S"""
      .form-group { margin-bottom: 14px; }
      .form-group label {
        display: block; font-size: 0.8rem; font-weight: 500;
        color: var(--text-secondary); margin-bottom: 5px;
      }
      .form-group input, .form-group textarea, .form-group select {
        width: 100%; padding: 7px 10px; background: var(--bg-primary);
        border: 1px solid var(--border); border-radius: var(--radius-sm);
        color: var(--text-primary); font-size: 0.85rem; font-family: inherit;
        outline: none; transition: border-color var(--transition);
      }
      .form-group textarea { resize: vertical; min-height: 80px; }
      .form-group input:focus, .form-group textarea:focus, .form-group select:focus { border-color: var(--accent); }
      .form-row { display: flex; gap: 12px; }
      .form-row .form-group { flex: 1; }
      .form-actions { display: flex; justify-content: flex-end; gap: 8px; margin-top: 8px; }
      .form-checkbox { margin-bottom: 8px; }
      .form-checkbox label {
        display: inline-flex; align-items: center; gap: 6px;
        font-size: 0.85rem; color: var(--text-muted); cursor: pointer; font-weight: 400;
      }
      .form-checkbox label input[type="checkbox"] { width: auto; }
      .help-text { display: block; font-size: 0.72rem; color: var(--text-muted); margin-top: 3px; line-height: 1.4; }
      @media (max-width: 600px) { .form-row { flex-direction: column; gap: 0; } }
    """
  end

  @doc "Shared modal CSS."
  @spec modal_css() :: String.t()
  def modal_css do
    ~S"""
      .modal-overlay {
        display: none; position: fixed; inset: 0;
        background: rgba(0,0,0,0.6); z-index: 1000;
        align-items: center; justify-content: center;
      }
      .modal-overlay.active { display: flex; }
      .modal {
        background: var(--bg-secondary); border: 1px solid var(--border);
        border-radius: var(--radius); padding: 24px;
        width: 560px; max-width: 92vw; max-height: 85vh;
        overflow-y: auto; box-shadow: var(--shadow);
      }
      .modal-wide { width: 700px; }
      .modal-header {
        display: flex; align-items: center; justify-content: space-between;
        margin-bottom: 18px;
      }
      .modal-header h2, .modal-header h3 { font-size: 1.05rem; font-weight: 600; }
      .modal-body { margin-bottom: 16px; }
      .modal-footer {
        display: flex; justify-content: flex-end; gap: 8px;
        padding-top: 12px; border-top: 1px solid var(--border); margin-top: 8px;
      }
    """
  end

  @doc "Shared badge CSS for state badges."
  @spec badge_css() :: String.t()
  def badge_css do
    ~S"""
      .badge {
        display: inline-block; padding: 2px 8px; border-radius: 10px;
        font-size: 0.7rem; font-weight: 600;
      }
      .badge-backlog { background: rgba(139,148,158,0.15); color: var(--text-muted); }
      .badge-todo { background: rgba(210,153,34,0.15); color: var(--yellow); }
      .badge-in-progress { background: rgba(88,166,255,0.15); color: var(--accent); }
      .badge-review { background: rgba(188,140,255,0.15); color: var(--purple); }
      .badge-done { background: rgba(63,185,80,0.15); color: var(--green); }
      .badge-cancelled { background: rgba(248,81,73,0.15); color: var(--red); }
      .badge-archived { background: rgba(72,79,88,0.25); color: var(--text-muted); }
      .badge-default { background: var(--bg-tertiary); color: var(--text-secondary); border: 1px solid var(--border); }
    """
  end

  @doc "Shared toast/notification CSS and JS."
  @spec toast_css() :: String.t()
  def toast_css do
    ~S"""
      .toast-container { position: fixed; bottom: 20px; right: 20px; z-index: 9999; display: flex; flex-direction: column; gap: 8px; }
      .toast {
        padding: 10px 16px; border-radius: var(--radius-sm);
        background: var(--bg-secondary); border: 1px solid var(--border);
        color: var(--text-primary); font-size: 0.85rem;
        box-shadow: var(--shadow); display: flex; align-items: center; gap: 10px;
        animation: toastIn 0.2s ease;
      }
      .toast.success { border-color: var(--green); }
      .toast.error { border-color: var(--red); }
      .toast-undo { color: var(--accent); cursor: pointer; font-weight: 600; background: none; border: none; font-size: 0.85rem; }
      @keyframes toastIn { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }
    """
  end

  @doc "Toast JS helper."
  @spec toast_js() :: String.t()
  def toast_js do
    ~S"""
    function showToast(msg, opts) {
      opts = opts || {};
      var container = document.getElementById('toast-container');
      if (!container) { container = document.createElement('div'); container.id = 'toast-container'; container.className = 'toast-container'; document.body.appendChild(container); }
      var toast = document.createElement('div');
      toast.className = 'toast ' + (opts.type || '');
      var html = '<span>' + esc(msg) + '</span>';
      if (opts.undo) { html += '<button class="toast-undo" onclick="this.parentElement._undo()">Undo</button>'; }
      toast.innerHTML = html;
      if (opts.undo) { toast._undo = function() { opts.undo(); toast.remove(); }; }
      container.appendChild(toast);
      setTimeout(function() { toast.remove(); }, opts.duration || 4000);
    }
    """
  end

  @doc "Shared loading skeleton CSS."
  @spec skeleton_css() :: String.t()
  def skeleton_css do
    ~S"""
      .skeleton { background: linear-gradient(90deg, var(--bg-tertiary) 25%, var(--bg-hover) 50%, var(--bg-tertiary) 75%); background-size: 200% 100%; animation: shimmer 1.5s infinite; border-radius: var(--radius-sm); }
      @keyframes shimmer { 0% { background-position: 200% 0; } 100% { background-position: -200% 0; } }
      .skeleton-card { height: 72px; margin-bottom: 6px; }
      .skeleton-text { height: 14px; width: 60%; margin-bottom: 8px; }
    """
  end

  @doc "Hub layout CSS: sidebar + main content with tabs."
  @spec hub_layout_css() :: String.t()
  def hub_layout_css do
    ~S"""
      .hub-layout { display: flex; flex: 1; overflow: hidden; }

      /* --- Sidebar --- */
      .sidebar {
        width: 240px; min-width: 240px; flex-shrink: 0;
        background: var(--bg-secondary); border-right: 1px solid var(--border);
        display: flex; flex-direction: column; overflow: hidden;
        transition: width 200ms ease, min-width 200ms ease;
      }
      .sidebar.collapsed { width: 48px; min-width: 48px; }
      .sidebar-scroll { flex: 1; overflow-y: auto; padding: 8px 0; }
      .sidebar-section { padding: 4px 10px; }
      .sidebar-title {
        font-size: 0.65rem; text-transform: uppercase; letter-spacing: 0.06em;
        color: var(--text-muted); font-weight: 600; padding: 8px 6px 4px; user-select: none;
      }
      .sidebar-item {
        display: flex; align-items: center; justify-content: space-between;
        padding: 5px 10px; border-radius: var(--radius-sm); cursor: pointer;
        transition: background var(--transition); font-size: 0.82rem; color: var(--text-secondary);
        gap: 8px; user-select: none;
      }
      .sidebar-item:hover { background: var(--bg-hover); }
      .sidebar-item.active {
        background: rgba(88,166,255,0.1); color: var(--accent); font-weight: 600;
      }
      .sidebar-item-name { flex: 1; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
      .sidebar-badge {
        font-size: 0.65rem; background: var(--bg-tertiary); color: var(--text-muted);
        padding: 1px 6px; border-radius: 10px; min-width: 18px; text-align: center; flex-shrink: 0;
      }
      .sidebar-item.active .sidebar-badge { background: rgba(88,166,255,0.15); color: var(--accent); }
      .sidebar-footer {
        border-top: 1px solid var(--border); padding: 8px 10px;
        display: flex; flex-wrap: wrap; gap: 2px;
      }
      .sidebar-footer a {
        font-size: 0.75rem; color: var(--text-muted); text-decoration: none;
        padding: 3px 6px; border-radius: var(--radius-sm);
        transition: all var(--transition);
      }
      .sidebar-footer a:hover { color: var(--accent); background: var(--bg-hover); }
      .sidebar-toggle {
        background: none; border: none; color: var(--text-muted); cursor: pointer;
        padding: 6px; border-radius: var(--radius-sm); transition: all var(--transition);
      }
      .sidebar-toggle:hover { color: var(--text-primary); background: var(--bg-hover); }
      .sidebar.collapsed .sidebar-item-name,
      .sidebar.collapsed .sidebar-badge,
      .sidebar.collapsed .sidebar-title,
      .sidebar.collapsed .sidebar-footer a span { display: none; }
      .sidebar.collapsed .sidebar-item { justify-content: center; padding: 6px; }
      .sidebar.collapsed .sidebar-footer { justify-content: center; }

      /* --- Tab Bar --- */
      .tab-bar {
        display: flex; align-items: center; gap: 0; padding: 0 20px;
        border-bottom: 1px solid var(--border); background: var(--bg-secondary); flex-shrink: 0;
      }
      .tab-item {
        padding: 10px 16px; font-size: 0.82rem; font-weight: 500;
        color: var(--text-muted); cursor: pointer;
        border-bottom: 2px solid transparent; transition: all var(--transition);
        display: flex; align-items: center; gap: 6px; user-select: none;
      }
      .tab-item:hover { color: var(--text-primary); }
      .tab-item.active { color: var(--accent); border-bottom-color: var(--accent); }
      .tab-badge {
        font-size: 0.65rem; padding: 1px 6px; border-radius: 10px;
        background: var(--bg-tertiary); color: var(--text-muted);
      }
      .tab-item.active .tab-badge { background: rgba(88,166,255,0.15); color: var(--accent); }
      .tab-item.tab-disabled { opacity: 0.4; pointer-events: none; }
      .tab-actions { margin-left: auto; display: flex; align-items: center; gap: 6px; }

      /* Hub main */
      .hub-main { flex: 1; display: flex; flex-direction: column; overflow: hidden; min-width: 0; }
      .tab-content { flex: 1; overflow: auto; }

      @media (max-width: 768px) {
        .sidebar { width: 48px; min-width: 48px; }
        .sidebar .sidebar-item-name, .sidebar .sidebar-badge, .sidebar .sidebar-title { display: none; }
        .sidebar .sidebar-item { justify-content: center; padding: 6px; }
        .tab-item { padding: 8px 10px; font-size: 0.78rem; }
      }
    """
  end

  @doc "Shared navigation topbar HTML. `active` is the current page key."
  @spec nav_topbar(String.t()) :: String.t()
  def nav_topbar(active \\ "") do
    nav_items = [
      {"hub", "/board", "Hub"},
      {"pipeline", "/board/pipeline", "Pipeline"},
      {"skills", "/board/skills", "Skills"},
      {"settings", "/board/settings", "Settings"}
    ]

    links =
      nav_items
      |> Enum.map(fn {key, href, label} ->
        cls = if key == active, do: "btn btn-ghost nav-active", else: "btn btn-ghost"

        indicator =
          if key == "pipeline",
            do:
              ~s(<span id="pipeline-run-indicator" class="pipeline-run-dot" style="display:none" title="Pipeline running"></span>),
            else: ""

        ~s(<a href="#{href}" class="#{cls}">#{label}#{indicator}</a>)
      end)
      |> Enum.join("\n            ")

    back_btn =
      if active != "hub",
        do:
          ~s[<button class="btn btn-ghost btn-back" onclick="history.back()" title="Go back">&larr;</button>],
        else: ""

    """
      <header class="topbar">
        <div class="topbar-left">
          #{back_btn}
          <a href="/board" style="display:flex;align-items:center;gap:8px;text-decoration:none;color:inherit;">
            <svg class="logo" viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M8 12l2 2 4-4"/></svg>
            <h1 style="margin:0;">Symphony</h1>
          </a>
        </div>
        <div class="topbar-right">
          <div class="topbar-nav">
            #{links}
          </div>
        </div>
      </header>
    """
  end

  @doc """
  Shared create-issue modal HTML.

  Options:
  - prefix: ID prefix to avoid clashes (default "ci")
  - on_submit: JS function name called on form submit (default "submitCreateIssue")
  - on_cancel: JS function name called on cancel (default "closeCreateIssueModal")
  - submit_label: submit button text (default "Create Issue")
  - show_skills: include the pill-style skills picker (default false)
  - show_skills_picker: include the checkbox-style skills picker used by Hub (default false)
  - ai_draft: include the AI Draft bar above the form (default false)
  """
  @spec create_issue_modal_html(keyword()) :: String.t()
  def create_issue_modal_html(opts \\ []) do
    p = Keyword.get(opts, :prefix, "ci")
    on_submit = Keyword.get(opts, :on_submit, "submitCreateIssue")
    on_cancel = Keyword.get(opts, :on_cancel, "closeCreateIssueModal")
    submit_label = Keyword.get(opts, :submit_label, "Create Issue")
    show_skills = Keyword.get(opts, :show_skills, false)
    show_skills_picker = Keyword.get(opts, :show_skills_picker, false)
    ai_draft = Keyword.get(opts, :ai_draft, false)
    z_index = Keyword.get(opts, :z_index, nil)

    skills_html =
      cond do
        show_skills_picker ->
          """
                <div class="form-group">
                  <label>Skills <button type="button" class="skill-picker-toggle" onclick="toggleSkillPicker('#{p}-skills')">select skills...</button></label>
                  <div class="skill-picker" id="#{p}-skills" style="display:none"></div>
                </div>
          """

        show_skills ->
          """
                <div class="form-group">
                  <label>Skills <span class="form-hint">(select skills to inject into agent prompt)</span></label>
                  <div class="form-skill-pills" id="#{p}-skill-pills"></div>
                  <select id="#{p}-add-skill" onchange="formAddSkill(this.value); this.value='';">
                    <option value="">+ Add skill or group...</option>
                  </select>
                </div>
          """

        true ->
          ""
      end

    ai_draft_html =
      if ai_draft do
        """
            <div class="ai-draft-bar">
              <textarea id="#{p}-ai-draft-input" class="ai-draft-input" placeholder="Describe what you need in a few words... (Shift+Enter for new line)" rows="1" onkeydown="if(event.key==='Enter'&&!event.shiftKey){event.preventDefault();#{p}AiDraft();}"></textarea>
              <button type="button" class="btn btn-accent-soft btn-sm" id="#{p}-ai-draft-btn" onclick="#{p}AiDraft()">AI Draft</button>
            </div>
        """
      else
        ""
      end

    """
    <div class="modal-overlay" id="#{p}-modal" style="display:none#{if z_index, do: ";z-index:#{z_index}", else: ""}" onclick="if(event.target===this)#{on_cancel}()">
      <div class="modal" style="max-width:560px" onclick="event.stopPropagation()">
        <div class="modal-header">
          <h3 id="#{p}-modal-title">New Issue</h3>
          <button class="btn-icon" onclick="#{on_cancel}()">&times;</button>
        </div>
    #{ai_draft_html}
        <form id="#{p}-form" onsubmit="#{on_submit}(event)">
          <input type="hidden" id="#{p}-id" value="">
          <div class="form-group">
            <label>Title</label>
            <input type="text" id="#{p}-title" required placeholder="Issue title...">
          </div>
          <div class="form-group">
            <label>Description</label>
            <textarea id="#{p}-description" rows="5" placeholder="Describe the issue..."></textarea>
          </div>
          <div class="form-row">
            <div class="form-group">
              <label>State</label>
              <select id="#{p}-state"></select>
            </div>
            <div class="form-group">
              <label>Priority</label>
              <select id="#{p}-priority">
                <option value="0">No priority</option>
                <option value="1">Urgent</option>
                <option value="2">High</option>
                <option value="3">Medium</option>
                <option value="4">Low</option>
              </select>
            </div>
          </div>
          <div class="form-group">
            <label>Labels (comma-separated)</label>
            <input type="text" id="#{p}-labels" placeholder="bug, frontend, urgent">
          </div>
          <div class="form-group">
            <label>Product</label>
            <select id="#{p}-product" onchange="#{p}OnProductChange()">
              <option value="">No product</option>
            </select>
          </div>
          <div class="form-group">
            <label>Project</label>
            <select id="#{p}-project">
              <option value="">No project</option>
            </select>
          </div>
    #{skills_html}
          <div class="form-group form-checkbox">
            <label><input type="checkbox" id="#{p}-followups" checked> Propose follow-up issues</label>
          </div>
          <div class="form-group form-checkbox">
            <label><input type="checkbox" id="#{p}-plan-first"> Plan first (agent plans before implementing)</label>
          </div>
          <div class="form-actions">
            <button type="button" class="btn btn-ghost" onclick="#{on_cancel}()">Cancel</button>
            <button type="submit" class="btn btn-primary" id="#{p}-submit">#{submit_label}</button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  @doc """
  Shared JS for populating and opening a create-issue modal.

  Returns JS functions: `{prefix}PopulateStates()`, `{prefix}PopulateProjects()`,
  `{prefix}CollectData()`. Callers wire these into their own open/submit handlers.
  """
  @spec create_issue_modal_js(String.t()) :: String.t()
  def create_issue_modal_js(prefix \\ "ci") do
    ~s"""
    async function #{prefix}PopulateStates(defaultState) {
      try {
        const res = await fetch('/board/api/states');
        const data = await res.json();
        const sel = document.getElementById('#{prefix}-state');
        sel.innerHTML = '';
        (data.states || []).forEach(s => {
          const opt = document.createElement('option');
          opt.value = s; opt.textContent = s;
          if (s === (defaultState || 'Backlog')) opt.selected = true;
          sel.appendChild(opt);
        });
      } catch(e) {}
    }

    var #{prefix}_allProducts = [];
    var #{prefix}_allProjects = [];

    async function #{prefix}PopulateProducts(defaultProductId) {
      try {
        const res = await fetch('/board/api/products');
        const data = await res.json();
        #{prefix}_allProducts = data.products || [];
        const sel = document.getElementById('#{prefix}-product');
        sel.innerHTML = '<option value="">No product</option>';
        #{prefix}_allProducts.forEach(p => {
          const opt = document.createElement('option');
          opt.value = p.id; opt.textContent = p.name;
          if (p.id === defaultProductId) opt.selected = true;
          sel.appendChild(opt);
        });
      } catch(e) {}
    }

    async function #{prefix}PopulateProjects(defaultProjectId) {
      try {
        const res = await fetch('/board/api/projects');
        const data = await res.json();
        #{prefix}_allProjects = data.projects || [];
        #{prefix}FilterProjects(defaultProjectId);
      } catch(e) {}
    }

    function #{prefix}FilterProjects(defaultProjectId) {
      const sel = document.getElementById('#{prefix}-project');
      const prodId = document.getElementById('#{prefix}-product').value;
      const prod = #{prefix}_allProducts.find(p => p.id === prodId);
      const allowedIds = prod ? new Set(prod.project_ids || []) : null;
      sel.innerHTML = '<option value="">No project</option>';
      #{prefix}_allProjects.forEach(p => {
        if (allowedIds && !allowedIds.has(p.id)) return;
        const opt = document.createElement('option');
        opt.value = p.id; opt.textContent = p.name;
        if (p.id === defaultProjectId) opt.selected = true;
        sel.appendChild(opt);
      });
    }

    function #{prefix}OnProductChange() {
      #{prefix}FilterProjects(null);
    }

    function #{prefix}Reset() {
      document.getElementById('#{prefix}-id').value = '';
      document.getElementById('#{prefix}-title').value = '';
      document.getElementById('#{prefix}-description').value = '';
      document.getElementById('#{prefix}-priority').value = '0';
      document.getElementById('#{prefix}-labels').value = '';
      document.getElementById('#{prefix}-product').value = '';
      document.getElementById('#{prefix}-followups').checked = true;
      document.getElementById('#{prefix}-plan-first').checked = false;
      var aiInput = document.getElementById('#{prefix}-ai-draft-input');
      if (aiInput) aiInput.value = '';
    }

    function #{prefix}CollectData() {
      return {
        title: document.getElementById('#{prefix}-title').value.trim(),
        description: document.getElementById('#{prefix}-description').value,
        state: document.getElementById('#{prefix}-state').value,
        priority: document.getElementById('#{prefix}-priority').value,
        labels: document.getElementById('#{prefix}-labels').value,
        product_id: document.getElementById('#{prefix}-product').value || null,
        project_id: document.getElementById('#{prefix}-project').value || null,
        propose_followups: document.getElementById('#{prefix}-followups').checked,
        plan_status: document.getElementById('#{prefix}-plan-first').checked ? 'planning' : null
      };
    }

    async function #{prefix}AiDraft() {
      const input = document.getElementById('#{prefix}-ai-draft-input');
      if (!input) return;
      const hint = input.value.trim();
      if (!hint) { input.focus(); return; }
      const btn = document.getElementById('#{prefix}-ai-draft-btn');
      btn.textContent = 'Drafting...'; btn.disabled = true; input.disabled = true;
      try {
        const body = { hint: hint };
        const prodSel = document.getElementById('#{prefix}-product');
        if (prodSel && prodSel.value) body.product_id = prodSel.value;
        const projSel = document.getElementById('#{prefix}-project');
        if (projSel && projSel.value) body.project_id = projSel.value;
        // Allow callers to inject extra params (e.g. product_id)
        if (typeof #{prefix}AiDraftExtras === 'function') Object.assign(body, #{prefix}AiDraftExtras());
        const res = await fetch('/board/api/ai/draft-issue', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(body)
        });
        const draft = await res.json();
        if (draft.error) { if (typeof showToast === 'function') showToast('Draft failed: ' + draft.error, { type: 'error' }); return; }
        document.getElementById('#{prefix}-title').value = draft.title || hint;
        document.getElementById('#{prefix}-description').value = draft.description || '';
        document.getElementById('#{prefix}-priority').value = (draft.priority || 0).toString();
        document.getElementById('#{prefix}-labels').value = (draft.labels || []).join(', ');
        // Allow callers to handle extra draft fields (e.g. skills)
        if (typeof #{prefix}AiDraftApply === 'function') #{prefix}AiDraftApply(draft);
        input.value = '';
        if (typeof showToast === 'function') showToast('Issue drafted by AI', { type: 'success' });
      } catch (e) { if (typeof showToast === 'function') showToast('Draft failed: ' + e.message, { type: 'error' }); }
      finally { btn.textContent = 'AI Draft'; btn.disabled = false; input.disabled = false; }
    }
    """
  end

  @doc "CSS for the AI draft bar used in create modals."
  def ai_draft_css do
    ~S"""
      .ai-draft-bar { display: flex; align-items: flex-start; gap: 8px; padding: 8px 20px 12px; border-bottom: 1px solid var(--border-light); margin-bottom: 0; }
      .ai-draft-input { flex: 1; padding: 6px 10px; background: var(--bg-primary); border: 1px solid var(--border); border-radius: var(--radius-sm, 6px); color: var(--text-primary); font-size: 0.85rem; font-family: inherit; outline: none; resize: vertical; min-height: 34px; max-height: 200px; line-height: 1.4; }
      .ai-draft-input:focus { border-color: var(--accent); }
      .ai-draft-input::placeholder { color: var(--text-muted); }
    """
  end

  @doc "CSS for the skill picker widget."
  def skill_picker_css do
    ~S"""
      .skill-picker { max-height: 200px; overflow-y: auto; border: 1px solid var(--border); border-radius: 6px; padding: 8px; margin-top: 4px; background: var(--bg-secondary); }
      .skill-picker-section { margin-bottom: 8px; }
      .skill-picker-section strong { display: block; font-size: 0.7rem; text-transform: uppercase; color: var(--text-muted); margin-bottom: 4px; letter-spacing: 0.5px; }
      .skill-pick-item { display: flex !important; align-items: center; gap: 6px; padding: 3px 0; font-size: 0.8rem; cursor: pointer; font-weight: normal; margin-bottom: 0; }
      .skill-pick-item input[type="checkbox"] { margin: 0; cursor: pointer; width: auto; flex-shrink: 0; }
      .skill-pick-name { color: var(--text-primary); }
      .skill-pick-count { color: var(--text-muted); font-size: 0.7rem; }
      .skill-pick-empty { font-size: 0.8rem; color: var(--text-muted); padding: 8px; text-align: center; }
      .skill-picker-toggle { font-size: 0.75rem; color: var(--accent); cursor: pointer; border: none; background: none; padding: 0; }
      .skill-picker-toggle:hover { text-decoration: underline; }
    """
  end

  @doc "JS for the skill picker widget. Requires allSkills and allSkillGroups arrays and esc() to be defined."
  def skill_picker_js do
    ~S"""
      function renderSkillPicker(containerId, selectedSkillIds, selectedGroupIds) {
        var el = document.getElementById(containerId); if (!el) return; var html = '';
        if (allSkillGroups.length > 0) { html += '<div class="skill-picker-section"><strong>Skill Groups</strong>'; allSkillGroups.forEach(function(g) { var checked = selectedGroupIds.indexOf(g.id) >= 0 ? ' checked' : ''; html += '<label class="skill-pick-item"><input type="checkbox" value="' + g.id + '" data-type="group"' + checked + '><span class="skill-pick-name">' + esc(g.name) + '</span><span class="skill-pick-count">(' + (g.skill_ids || []).length + ')</span></label>'; }); html += '</div>'; }
        if (allSkills.length > 0) { var categories = {}; allSkills.forEach(function(s) { var cat = s.category || 'custom'; if (!categories[cat]) categories[cat] = []; categories[cat].push(s); }); Object.keys(categories).sort().forEach(function(cat) { html += '<div class="skill-picker-section"><strong>' + esc(cat.charAt(0).toUpperCase() + cat.slice(1)) + '</strong>'; categories[cat].forEach(function(s) { var checked = selectedSkillIds.indexOf(s.id) >= 0 ? ' checked' : ''; html += '<label class="skill-pick-item"><input type="checkbox" value="' + s.id + '" data-type="skill"' + checked + '><span class="skill-pick-name">' + esc(s.name) + '</span></label>'; }); html += '</div>'; }); }
        if (!html) html = '<div class="skill-pick-empty">No skills available.</div>';
        el.innerHTML = html;
      }

      function getSelectedSkills(containerId) {
        var el = document.getElementById(containerId); if (!el) return { skill_ids: [], skill_group_ids: [] };
        var skillIds = [], groupIds = [];
        el.querySelectorAll('input[type=checkbox]:checked').forEach(function(cb) { if (cb.dataset.type === 'group') groupIds.push(cb.value); else skillIds.push(cb.value); });
        return { skill_ids: skillIds, skill_group_ids: groupIds };
      }

      function toggleSkillPicker(containerId) {
        var el = document.getElementById(containerId); if (!el) return;
        if (el.style.display === 'none') {
          var current = getSelectedSkills(containerId);
          renderSkillPicker(containerId, current.skill_ids, current.skill_group_ids);
          el.style.display = '';
        } else {
          el.style.display = 'none';
        }
      }
    """
  end

  @doc "Shared JS time utilities: timeAgo, formatTime, truncate."
  @spec time_utils_js() :: String.t()
  def time_utils_js do
    ~S"""
    function formatTime(ts) {
      try {
        var d = new Date(ts);
        return d.toLocaleTimeString('en-GB', {hour:'2-digit', minute:'2-digit', second:'2-digit'});
      } catch(e) { return ''; }
    }

    function timeAgo(ts) {
      if (!ts) return '';
      try {
        var secs = Math.floor((Date.now() - new Date(ts).getTime()) / 1000);
        if (secs < 5) return 'just now';
        if (secs < 60) return secs + 's ago';
        var mins = Math.floor(secs / 60); if (mins < 60) return mins + 'm ago';
        var hrs = Math.floor(mins / 60); if (hrs < 24) return hrs + 'h ago';
        var days = Math.floor(hrs / 24); if (days < 30) return days + 'd ago';
        return new Date(ts).toLocaleDateString();
      } catch(e) { return ''; }
    }

    function truncate(s, n) {
      return s.length > n ? s.slice(0, n) + '...' : s;
    }
    """
  end

  @doc "Shared pulse animation CSS."
  @spec pulse_css() :: String.t()
  def pulse_css do
    ~S"""
      @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.7; } }
    """
  end

  @doc "Shared spinner CSS."
  @spec spinner_css() :: String.t()
  def spinner_css do
    ~S"""
      .spinner { display: inline-block; width: 14px; height: 14px; border: 2px solid var(--border); border-top-color: var(--accent); border-radius: 50%; animation: spin 0.6s linear infinite; vertical-align: middle; margin-right: 6px; }
      @keyframes spin { to { transform: rotate(360deg); } }
    """
  end

  @doc "Shared label tag CSS."
  @spec label_css() :: String.t()
  def label_css do
    ~S"""
      .label { display: inline-block; padding: 2px 8px; border-radius: 10px; font-size: 0.7rem; background: rgba(88,166,255,0.1); color: var(--accent-hover); }
    """
  end

  @doc "Shared dropdown CSS (supports both .dropdown.open and .dropdown-menu.open patterns)."
  @spec dropdown_css() :: String.t()
  def dropdown_css do
    ~S"""
      .dropdown { position: relative; }
      .dropdown-menu { display: none; position: absolute; top: 100%; right: 0; margin-top: 4px; background: var(--bg-secondary); border: 1px solid var(--border); border-radius: var(--radius-sm); min-width: 220px; box-shadow: var(--shadow); z-index: 100; padding: 4px 0; }
      .dropdown.open .dropdown-menu, .dropdown-menu.open { display: block; }
      .dropdown-item { display: block; width: 100%; padding: 7px 12px; background: none; border: none; color: var(--text-secondary); font-size: 0.82rem; text-align: left; cursor: pointer; font-family: inherit; transition: background var(--transition); }
      .dropdown-item:hover { background: var(--bg-hover); color: var(--text-primary); }
      .dropdown-item small { display: block; color: var(--text-muted); font-size: 0.72rem; margin-top: 2px; }
    """
  end

  @doc "Shared dropdown JS: toggleDropdown, closeDropdowns, click-outside handler."
  @spec dropdown_js() :: String.t()
  def dropdown_js do
    ~S"""
    function toggleDropdown(id) { var el = document.getElementById(id); document.querySelectorAll('.dropdown.open').forEach(function(d) { if (d.id !== id) d.classList.remove('open'); }); el.classList.toggle('open'); }
    function closeDropdowns() { document.querySelectorAll('.dropdown.open').forEach(function(d) { d.classList.remove('open'); }); }
    document.addEventListener('click', function(e) { if (!e.target.closest('.dropdown')) closeDropdowns(); });
    """
  end

  @doc "Shared page actions bar CSS (used by board, skills, tech tree, issue detail)."
  @spec page_actions_css() :: String.t()
  def page_actions_css do
    ~S"""
      .page-actions-bar { display: flex; align-items: center; justify-content: space-between; padding: 10px 20px; border-bottom: 1px solid var(--border); background: var(--bg-primary); flex-shrink: 0; }
      .page-actions-left { display: flex; align-items: center; gap: 10px; }
      .page-actions-right { display: flex; align-items: center; gap: 6px; }
      .page-title { font-size: 1rem; font-weight: 600; color: var(--text-primary); }
    """
  end

  @doc "Shared JS for loading skills and skill groups from API."
  @spec load_skills_js() :: String.t()
  def load_skills_js do
    ~S"""
    var allSkills = [];
    var allSkillGroups = [];

    async function loadAllSkills() {
      try {
        var results = await Promise.all([
          fetch('/board/api/skills'),
          fetch('/board/api/skill-groups')
        ]);
        var skillsData = await results[0].json();
        var groupsData = await results[1].json();
        allSkills = (skillsData.skills || []).sort(function(a, b) { return a.name.localeCompare(b.name); });
        allSkillGroups = (groupsData.skill_groups || []).sort(function(a, b) { return a.name.localeCompare(b.name); });
      } catch(e) { allSkills = []; allSkillGroups = []; }
    }
    """
  end

  @doc "CSS for active nav item highlight."
  @spec nav_active_css() :: String.t()
  def nav_active_css do
    ~S"""
      .nav-active { color: var(--accent) !important; background: rgba(88,166,255,0.08) !important; }
      .btn-back { font-size: 1.1rem; padding: 2px 8px; min-height: 0; line-height: 1; margin-right: 4px; }
    """
  end

  @doc "Shared CSS for integration help/info boxes in pipeline config panels."
  @spec integration_help_css() :: String.t()
  def integration_help_css do
    ~S"""
      .integration-help {
        background: var(--bg-hover); border-left: 3px solid var(--accent);
        padding: 8px 12px; margin: 8px 0 12px; font-size: 0.78rem;
        color: var(--text-muted); line-height: 1.5; border-radius: 0 var(--radius-sm) var(--radius-sm) 0;
      }
      .integration-help .warn {
        color: var(--warning, #d29922); font-weight: 500;
      }
      .integration-help a { color: var(--accent); text-decoration: underline; }
    """
  end

  @doc """
  Shared JS for kanban drag-drop handlers.

  Expects the caller to define:
  - `draggedCard` variable (set to null initially)
  - `_apiLock` variable
  - `API` constant
  - `kanbanAfterMutation()` callback invoked after a successful drop or quick-add

  Options (set via `window._kanbanOpts`):
  - `cardSelector`: CSS selector for draggable card (default: '.issue-card')
  - `bodySelector`: CSS selector for drop zone columns (default: '.kb-column-body')
  - `getQuickAddExtras()`: function returning extra fields for quick-add POST body (default: {})
  """
  @spec kanban_drag_drop_js() :: String.t()
  def kanban_drag_drop_js do
    ~S"""
    var _kanbanOpts = window._kanbanOpts || {};
    var _kCardSel = _kanbanOpts.cardSelector || '.issue-card';
    var _kBodySel = _kanbanOpts.bodySelector || '.kb-column-body';

    function handleDragStart(e) {
      draggedCard = e.target.closest(_kCardSel);
      if (draggedCard) {
        draggedCard.classList.add('dragging');
        e.dataTransfer.effectAllowed = 'move';
        e.dataTransfer.setData('text/plain', draggedCard.dataset.id);
      }
    }

    function handleDragEnd(e) {
      if (draggedCard) draggedCard.classList.remove('dragging');
      draggedCard = null;
      document.querySelectorAll(_kBodySel).forEach(function(el) { el.classList.remove('drag-over'); });
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
      var issueId = e.dataTransfer.getData('text/plain');
      var newState = e.currentTarget.dataset.state;
      if (!issueId || !newState || _apiLock) return;
      if (['Cancelled', 'Archived'].includes(newState)) {
        if (!confirm('Move issue to ' + newState + '?')) return;
      }
      _apiLock = true;
      try {
        var res = await fetch(API + '/issues/' + issueId + '/move', {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ state: newState })
        });
        if (!res.ok) {
          var data = await res.json().catch(function() { return {}; });
          showToast('Move failed: ' + esc(data.error || 'unknown'), { type: 'error' });
        }
        await kanbanAfterMutation();
      } catch (err) {
        showToast('Move failed: ' + esc(err.message || 'network error'), { type: 'error' });
      } finally {
        _apiLock = false;
      }
    }

    async function handleQuickAdd(e) {
      if (e.key !== 'Enter') return;
      var input = e.target;
      var title = input.value.trim();
      if (!title || _apiLock) return;
      var state = input.dataset.state;
      input.value = '';
      var body = { title: title, state: state };
      var extras = (_kanbanOpts.getQuickAddExtras || function() { return {}; })();
      Object.keys(extras).forEach(function(k) { body[k] = extras[k]; });
      _apiLock = true;
      try {
        var res = await fetch(API + '/issues', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(body)
        });
        if (!res.ok) {
          var data = await res.json().catch(function() { return {}; });
          showToast('Quick add failed: ' + esc(data.error || 'unknown'), { type: 'error' });
        }
        await kanbanAfterMutation();
      } catch (err) {
        showToast('Quick add failed: ' + esc(err.message || 'network error'), { type: 'error' });
      } finally {
        _apiLock = false;
      }
    }
    """
  end
end

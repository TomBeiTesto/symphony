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
      .modal-header h2 { font-size: 1.05rem; font-weight: 600; }
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
end

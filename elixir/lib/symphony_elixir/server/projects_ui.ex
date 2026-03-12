defmodule SymphonyElixir.Server.ProjectsUI do
  @moduledoc """
  Dedicated Projects page for Symphony — browse, create, edit, import,
  and clone projects. Single source of truth for project management UI.
  """

  @doc "Render the full Projects HTML page."
  @spec render() :: String.t()
  def render do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Symphony Projects</title>
      <style>
    #{css()}
      </style>
    </head>
    <body>
      <header class="topbar">
        <div class="topbar-left">
          <nav class="breadcrumb"><a href="/board">Board</a><span class="sep">/</span></nav>
          <h1>Projects</h1>
          <span class="project-count" id="project-count"></span>
        </div>
        <div class="topbar-right">
          <input type="text" class="search-input" id="search" placeholder="Filter projects..." oninput="filterProjects()">
          <button class="btn btn-accent" onclick="showScanView()">
            <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 19a2 2 0 01-2 2H4a2 2 0 01-2-2V5a2 2 0 012-2h5l2 3h9a2 2 0 012 2z"/></svg>
            Import
          </button>
          <button class="btn btn-primary" onclick="showCreateForm()">
            <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
            New Project
          </button>
        </div>
      </header>

      <main class="projects-page">
        <div id="project-grid" class="project-grid"></div>
        <div id="empty-state" class="empty-state" style="display:none">
          <svg viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="currentColor" stroke-width="1.5" opacity="0.3"><path d="M22 19a2 2 0 01-2 2H4a2 2 0 01-2-2V5a2 2 0 012-2h5l2 3h9a2 2 0 012 2z"/></svg>
          <p>No projects yet</p>
          <p class="empty-hint">Create a project to organize issues, or import from a directory.</p>
        </div>
      </main>

      <!-- Create / Edit Form Modal -->
      <div class="modal-overlay" id="form-overlay" onclick="closeForm()">
        <div class="modal" onclick="event.stopPropagation()">
          <div class="modal-header">
            <h2 id="form-title">New Project</h2>
            <button class="btn-icon" onclick="closeForm()">&times;</button>
          </div>
          <form id="project-form" onsubmit="handleSubmit(event)">
            <input type="hidden" id="form-id" value="">
            <div class="form-group">
              <label for="form-name">Project Name</label>
              <input type="text" id="form-name" required placeholder="My Project">
            </div>
            <div class="form-group">
              <label for="form-description">Description</label>
              <textarea id="form-description" rows="3" placeholder="What is this project about?"></textarea>
            </div>
            <div class="form-group">
              <label for="form-path">Local Directory Path</label>
              <div style="display:flex; gap: 8px;">
                <input type="text" id="form-path" placeholder="/home/user/projects/my-app" style="flex:1">
                <button type="button" class="btn" onclick="browseFolder('form-path')">Browse</button>
              </div>
            </div>
            <div class="form-group">
              <label for="form-repo">Repository URL (optional)</label>
              <input type="text" id="form-repo" placeholder="https://github.com/user/repo.git">
            </div>
            <div class="form-group">
              <label for="form-tags">Tags (comma-separated)</label>
              <input type="text" id="form-tags" placeholder="python, api, data-pipeline">
            </div>
            <div class="form-actions">
              <button type="button" class="btn btn-ghost" onclick="closeForm()">Cancel</button>
              <button type="submit" class="btn btn-primary" id="form-submit-btn">Create Project</button>
            </div>
          </form>
        </div>
      </div>

      <!-- Import / Scan Modal -->
      <div class="modal-overlay" id="scan-overlay" onclick="closeScan()">
        <div class="modal modal-wide" onclick="event.stopPropagation()">
          <div class="modal-header">
            <h2>Import from Directory</h2>
            <button class="btn-icon" onclick="closeScan()">&times;</button>
          </div>
          <div class="form-group">
            <label for="scan-root-path">Root Directory</label>
            <div style="display:flex; gap: 8px;">
              <input type="text" id="scan-root-path" placeholder="C:\\Projects or /home/user/repos" style="flex:1">
              <button class="btn" onclick="browseFolder('scan-root-path')" id="browse-btn">Browse</button>
              <button class="btn btn-primary" onclick="scanDirectory()" id="scan-btn">Scan</button>
            </div>
            <small class="help-text">Recursively scans for git repos and projects. Analyzes READMEs, package files, and tech stack to generate titles, descriptions, and tags.</small>
          </div>
          <div style="display:flex; gap: 16px; margin-top: 8px;">
            <label class="checkbox-label"><input type="checkbox" id="scan-ai-summarize" checked> AI summarize (uses Claude)</label>
            <label class="checkbox-label"><input type="checkbox" id="scan-git-pull"> Git pull latest</label>
          </div>
          <div id="scan-results" style="margin-top: 12px;"></div>
          <div class="form-actions" style="margin-top: 16px;">
            <button class="btn btn-ghost" onclick="closeScan()">Cancel</button>
            <button class="btn btn-primary" id="import-btn" style="display:none" onclick="importScanned()">Import Selected</button>
          </div>
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

    UIHelpers.base_css() <>
      UIHelpers.topbar_css() <>
      UIHelpers.button_css() <>
      UIHelpers.form_css() <>
      UIHelpers.modal_css() <>
      UIHelpers.badge_css() <>
      UIHelpers.toast_css() <>
      ~S"""

      body { min-height: 100vh; }
      .topbar { position: sticky; top: 0; }

      .project-count {
        font-size: 0.8rem; color: var(--text-muted);
        background: var(--bg-tertiary); padding: 2px 8px;
        border-radius: 10px;
      }

      .search-input {
        padding: 5px 10px; background: var(--bg-primary);
        border: 1px solid var(--border); border-radius: var(--radius-sm);
        color: var(--text-primary); font-size: 0.82rem; outline: none;
        width: 200px; transition: border-color var(--transition);
      }
      .search-input:focus { border-color: var(--accent); }

      .projects-page {
        max-width: 1100px; margin: 0 auto; padding: 24px;
      }

      .project-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
        gap: 16px;
      }

      .project-card {
        background: var(--bg-secondary); border: 1px solid var(--border);
        border-radius: var(--radius); padding: 20px;
        transition: border-color var(--transition);
        display: flex; flex-direction: column; gap: 12px;
      }
      .project-card:hover { border-color: var(--accent); }

      .project-card h3 {
        font-size: 1rem; font-weight: 600; color: var(--text-primary);
        margin: 0; display: flex; align-items: center; gap: 8px;
      }
      .project-card .desc {
        font-size: 0.82rem; color: var(--text-secondary);
        line-height: 1.4; display: -webkit-box;
        -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden;
      }
      .project-card .meta {
        display: flex; align-items: center; gap: 12px; flex-wrap: wrap;
        font-size: 0.75rem; color: var(--text-muted);
      }
      .project-card .meta-item {
        display: flex; align-items: center; gap: 4px;
      }
      .project-card .tags {
        display: flex; flex-wrap: wrap; gap: 4px;
      }
      .project-card .tag {
        font-size: 0.65rem; padding: 1px 6px; border-radius: 8px;
        background: rgba(88,166,255,0.1); color: var(--accent);
        border: 1px solid rgba(88,166,255,0.15);
      }
      .project-card .actions {
        display: flex; gap: 6px; margin-top: auto; padding-top: 4px;
        border-top: 1px solid var(--border-light);
      }
      .issue-count {
        font-size: 0.72rem; background: var(--bg-tertiary);
        padding: 2px 7px; border-radius: 10px; color: var(--text-muted);
        font-weight: 600;
      }

      .empty-state {
        display: flex; flex-direction: column; align-items: center;
        justify-content: center; gap: 12px; padding: 80px 20px;
        color: var(--text-muted);
      }
      .empty-state p { font-size: 1rem; margin: 0; }
      .empty-hint { font-size: 0.85rem; opacity: 0.6; }

      .help-text { font-size: 0.75rem; color: var(--text-muted); margin-top: 4px; display: block; }
      .checkbox-label {
        display: flex; align-items: center; gap: 4px;
        cursor: pointer; font-size: 0.8rem; color: var(--text-secondary);
      }

      .scan-card {
        background: var(--bg-secondary); border: 1px solid var(--border);
        border-radius: var(--radius-sm); padding: 10px 12px; margin-bottom: 6px;
      }

      @media (max-width: 600px) {
        .topbar { flex-wrap: wrap; gap: 8px; }
        .search-input { width: 100%; order: 10; }
        .project-grid { grid-template-columns: 1fr; }
        .projects-page { padding: 12px; }
      }
      """
  end

  defp javascript do
    ~S"""
    const API = '/board/api';
    let allProjects = [];
    let allIssues = [];
    let scannedCandidates = [];

    function esc(s) {
      if (s == null) return '';
      var d = document.createElement('div');
      d.textContent = s;
      return d.innerHTML;
    }

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

    async function loadProjects() {
      try {
        var [projRes, snapRes] = await Promise.all([
          fetch(API + '/projects'),
          fetch(API + '/snapshot')
        ]);
        var projData = await projRes.json();
        var snapData = await snapRes.json();
        allProjects = projData.projects || [];
        allIssues = [];
        (snapData.columns || []).forEach(function(col) {
          (col.issues || []).forEach(function(i) { allIssues.push(i); });
        });
        renderProjects();
      } catch (e) {
        console.error('Failed to load projects:', e);
      }
    }

    function renderProjects() {
      var q = (document.getElementById('search').value || '').toLowerCase();
      var filtered = q ? allProjects.filter(function(p) {
        return (p.name || '').toLowerCase().includes(q) ||
               (p.description || '').toLowerCase().includes(q) ||
               (p.path || '').toLowerCase().includes(q) ||
               (p.tags || []).join(' ').toLowerCase().includes(q);
      }) : allProjects;

      document.getElementById('project-count').textContent = allProjects.length + ' project' + (allProjects.length !== 1 ? 's' : '');

      var grid = document.getElementById('project-grid');
      var empty = document.getElementById('empty-state');

      if (filtered.length === 0 && !q) {
        grid.innerHTML = '';
        empty.style.display = '';
        return;
      }
      empty.style.display = 'none';

      if (filtered.length === 0) {
        grid.innerHTML = '<div style="color:var(--text-muted);padding:24px;grid-column:1/-1;text-align:center">No projects matching "' + esc(q) + '"</div>';
        return;
      }

      grid.innerHTML = filtered.map(function(p) {
        var issueCount = allIssues.filter(function(i) { return i.project_id === p.id; }).length;
        var pathHtml = p.path ? '<span class="meta-item" title="' + esc(p.path) + '">&#128193; ' + esc(truncPath(p.path)) + '</span>' : '';
        var repoHtml = p.repo_url ? '<span class="meta-item" title="' + esc(p.repo_url) + '">&#128279; repo</span>' : '';
        var tagsHtml = (p.tags && p.tags.length) ? '<div class="tags">' + p.tags.map(function(t) { return '<span class="tag">' + esc(t) + '</span>'; }).join('') + '</div>' : '';
        var cloneBtn = (p.repo_url && !p.path) ? '<button class="btn btn-ghost btn-sm" onclick="cloneProject(\'' + p.id + '\')">Clone</button>' : '';

        return '<div class="project-card">' +
          '<h3>' + esc(p.name) + '<span class="issue-count">' + issueCount + '</span></h3>' +
          (p.description ? '<div class="desc">' + esc(p.description) + '</div>' : '') +
          tagsHtml +
          '<div class="meta">' + pathHtml + repoHtml + '</div>' +
          '<div class="actions">' +
            cloneBtn +
            '<button class="btn btn-ghost btn-sm" onclick="editProject(\'' + p.id + '\')">Edit</button>' +
            '<button class="btn btn-danger btn-sm" onclick="deleteProject(\'' + p.id + '\')">Delete</button>' +
          '</div>' +
        '</div>';
      }).join('');
    }

    function filterProjects() { renderProjects(); }
    function truncPath(p) { return p.length > 40 ? '...' + p.slice(-37) : p; }

    // --- Create / Edit ---
    function showCreateForm() {
      document.getElementById('form-id').value = '';
      document.getElementById('form-name').value = '';
      document.getElementById('form-description').value = '';
      document.getElementById('form-path').value = '';
      document.getElementById('form-repo').value = '';
      document.getElementById('form-tags').value = '';
      document.getElementById('form-title').textContent = 'New Project';
      document.getElementById('form-submit-btn').textContent = 'Create Project';
      document.getElementById('form-overlay').classList.add('active');
    }

    function editProject(id) {
      var p = allProjects.find(function(x) { return x.id === id; });
      if (!p) return;
      document.getElementById('form-id').value = p.id;
      document.getElementById('form-name').value = p.name || '';
      document.getElementById('form-description').value = p.description || '';
      document.getElementById('form-path').value = p.path || '';
      document.getElementById('form-repo').value = p.repo_url || '';
      document.getElementById('form-tags').value = (p.tags || []).join(', ');
      document.getElementById('form-title').textContent = 'Edit: ' + p.name;
      document.getElementById('form-submit-btn').textContent = 'Save Changes';
      document.getElementById('form-overlay').classList.add('active');
    }

    function closeForm() {
      document.getElementById('form-overlay').classList.remove('active');
    }

    async function handleSubmit(e) {
      e.preventDefault();
      var id = document.getElementById('form-id').value;
      var tagsStr = document.getElementById('form-tags').value;
      var tags = tagsStr ? tagsStr.split(',').map(function(t) { return t.trim(); }).filter(Boolean) : [];
      var data = {
        name: document.getElementById('form-name').value,
        description: document.getElementById('form-description').value,
        path: document.getElementById('form-path').value || null,
        repo_url: document.getElementById('form-repo').value || null,
        tags: tags
      };
      try {
        var res;
        if (id) {
          res = await fetch(API + '/projects/' + id, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) });
        } else {
          res = await fetch(API + '/projects', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) });
        }
        if (!res.ok) {
          var errData = await res.json().catch(function() { return {}; });
          showToast('Save failed: ' + (errData.error || 'unknown error'), { type: 'error' });
          return;
        }
        closeForm();
        await loadProjects();
      } catch (err) {
        showToast('Save failed: ' + err.message, { type: 'error' });
      }
    }

    async function deleteProject(id) {
      var p = allProjects.find(function(x) { return x.id === id; });
      if (!confirm('Delete project "' + (p ? p.name : '') + '" and all its issues?')) return;
      try {
        await fetch(API + '/projects/' + id, { method: 'DELETE' });
        await loadProjects();
      } catch (err) {
        showToast('Delete failed: ' + err.message, { type: 'error' });
      }
    }

    async function cloneProject(id) {
      var p = allProjects.find(function(x) { return x.id === id; });
      if (!confirm('Clone repository for "' + (p ? p.name : '') + '"?\n' + (p ? p.repo_url : ''))) return;
      try {
        var res = await fetch(API + '/projects/' + id + '/clone', { method: 'POST' });
        var data = await res.json();
        if (res.ok) {
          showToast('Cloned to: ' + data.path, { type: 'success' });
          await loadProjects();
        } else {
          showToast('Clone failed: ' + (data.error || 'unknown'), { type: 'error' });
        }
      } catch (err) {
        showToast('Clone failed: ' + err.message, { type: 'error' });
      }
    }

    // --- Browse Folder (native OS dialog) ---
    async function browseFolder(targetInputId) {
      try {
        var res = await fetch(API + '/browse-folder', { method: 'POST' });
        var data = await res.json();
        if (data.path) {
          document.getElementById(targetInputId).value = data.path;
        }
      } catch (err) {
        showToast('Failed to open folder dialog: ' + err.message, { type: 'error' });
      }
    }

    // --- Scan / Import ---
    function showScanView() {
      document.getElementById('scan-root-path').value = '';
      document.getElementById('scan-results').innerHTML = '';
      document.getElementById('import-btn').style.display = 'none';
      scannedCandidates = [];
      document.getElementById('scan-overlay').classList.add('active');
    }

    function closeScan() {
      document.getElementById('scan-overlay').classList.remove('active');
    }

    async function scanDirectory() {
      var rootPath = document.getElementById('scan-root-path').value.trim();
      if (!rootPath) return;
      var btn = document.getElementById('scan-btn');
      var results = document.getElementById('scan-results');
      var aiSummarize = document.getElementById('scan-ai-summarize').checked;
      btn.disabled = true; btn.textContent = 'Scanning...';
      results.innerHTML = aiSummarize
        ? '<div style="color:var(--text-muted)">Scanning directories and running AI analysis... This may take a moment.</div>'
        : '<div style="color:var(--text-muted)">Scanning directories...</div>';

      try {
        var res = await fetch(API + '/projects/scan', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            root_path: rootPath,
            git_pull: document.getElementById('scan-git-pull').checked,
            ai_summarize: aiSummarize
          })
        });
        var data = await res.json();
        if (!res.ok) {
          results.innerHTML = '<div style="color:var(--red)">Error: ' + esc(data.error || 'unknown') + (data.detail ? ' &mdash; ' + esc(data.detail) : '') + '</div>';
          return;
        }
        scannedCandidates = data.candidates || [];
        var existingPaths = new Set(allProjects.map(function(p) { return p.path; }).filter(Boolean));
        scannedCandidates.forEach(function(c) {
          c._selected = !existingPaths.has(c.path);
          c._existing = existingPaths.has(c.path);
        });
        renderScanResults();
      } catch (err) {
        results.innerHTML = '<div style="color:var(--red)">Scan failed: ' + esc(err.message || 'unknown error') + '</div>';
      } finally {
        btn.disabled = false; btn.textContent = 'Scan';
      }
    }

    function renderScanResults() {
      var results = document.getElementById('scan-results');
      if (scannedCandidates.length === 0) {
        results.innerHTML = '<div style="color:var(--text-muted)">No projects found.</div>';
        document.getElementById('import-btn').style.display = 'none';
        return;
      }
      var selectable = scannedCandidates.filter(function(c) { return !c._existing; });
      var selectedCount = scannedCandidates.filter(function(c) { return c._selected; }).length;

      var html = '<div style="margin-bottom:8px;display:flex;justify-content:space-between;align-items:center">' +
        '<span style="font-size:0.85rem;color:var(--text-secondary)">Found ' + scannedCandidates.length + ' project' + (scannedCandidates.length !== 1 ? 's' : '') + ' (' + selectedCount + ' selected)</span>' +
        (selectable.length > 0 ? '<label style="font-size:0.8rem;color:var(--text-muted);cursor:pointer"><input type="checkbox" ' + (selectedCount === selectable.length ? 'checked' : '') + ' onchange="toggleAllScan(this.checked)"> Select all</label>' : '') +
      '</div>';

      html += scannedCandidates.map(function(c, i) {
        var disabled = c._existing;
        var badge = disabled ? '<span style="font-size:0.7rem;background:var(--bg-tertiary);color:var(--text-muted);padding:2px 6px;border-radius:4px;margin-left:8px">already imported</span>' : '';
        var repo = c.repo_url ? '<span style="font-size:0.75rem;color:var(--text-muted)">&#128279; ' + esc(c.repo_url) + '</span>' : '';
        var tagsHtml = (c.tags && c.tags.length) ? '<div style="display:flex;flex-wrap:wrap;gap:4px;margin-top:4px">' + c.tags.map(function(t) { return '<span style="font-size:0.65rem;padding:1px 6px;border-radius:8px;background:rgba(88,166,255,0.1);color:var(--accent);border:1px solid rgba(88,166,255,0.15)">' + esc(t) + '</span>'; }).join('') + '</div>' : '';

        return '<div class="scan-card" style="' + (disabled ? 'opacity:0.5' : '') + '">' +
          '<div style="display:flex;align-items:flex-start;gap:10px">' +
            '<input type="checkbox" ' + (c._selected ? 'checked' : '') + ' ' + (disabled ? 'disabled' : '') + ' onchange="toggleScanItem(' + i + ',this.checked)" style="margin-top:4px">' +
            '<div style="flex:1;min-width:0">' +
              '<div style="display:flex;align-items:center;gap:6px;flex-wrap:wrap">' +
                '<strong style="font-size:0.9rem">' + esc(c.name) + '</strong>' + badge +
              '</div>' +
              (c.description ? '<div style="font-size:0.8rem;color:var(--text-secondary);margin-top:2px">' + esc(c.description) + '</div>' : '') +
              tagsHtml +
              '<div style="font-size:0.75rem;color:var(--text-muted);margin-top:4px">&#128193; ' + esc(c.path) + ' ' + repo + '</div>' +
            '</div>' +
          '</div>' +
        '</div>';
      }).join('');
      results.innerHTML = html;
      document.getElementById('import-btn').style.display = selectedCount > 0 ? '' : 'none';
      document.getElementById('import-btn').textContent = 'Import ' + selectedCount + ' Project' + (selectedCount !== 1 ? 's' : '');
    }

    function toggleScanItem(idx, checked) {
      scannedCandidates[idx]._selected = checked;
      renderScanResults();
    }
    function toggleAllScan(checked) {
      scannedCandidates.forEach(function(c) { if (!c._existing) c._selected = checked; });
      renderScanResults();
    }

    async function importScanned() {
      var toImport = scannedCandidates.filter(function(c) { return c._selected && !c._existing; })
        .map(function(c) { return { name: c.name, slug: c.slug, path: c.path, description: c.description, repo_url: c.repo_url, tags: c.tags || [] }; });
      if (toImport.length === 0) return;
      var btn = document.getElementById('import-btn');
      btn.disabled = true; btn.textContent = 'Importing...';
      try {
        var res = await fetch(API + '/projects/import', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ projects: toImport })
        });
        if (res.ok) {
          closeScan();
          showToast('Imported ' + toImport.length + ' project' + (toImport.length !== 1 ? 's' : ''), { type: 'success' });
          await loadProjects();
        } else {
          var errData = await res.json().catch(function() { return {}; });
          showToast('Import failed: ' + (errData.error || 'unknown'), { type: 'error' });
        }
      } catch (err) {
        showToast('Import failed: ' + err.message, { type: 'error' });
      } finally {
        btn.disabled = false;
      }
    }

    // Keyboard
    document.addEventListener('keydown', function(e) {
      if (e.key === 'Escape') { closeForm(); closeScan(); }
    });

    loadProjects();
    """
  end
end

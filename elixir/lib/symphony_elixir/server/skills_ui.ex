defmodule SymphonyElixir.Server.SkillsUI do
  @moduledoc """
  Server-rendered Skills Library UI page.

  Browse, create, edit, duplicate, and delete skills.
  Manage skill groups (collections of skills).
  """

  alias SymphonyElixir.Server.UIHelpers

  @doc "Render the full Skills Library HTML page."
  @spec render() :: String.t()
  def render do
    body = """
      <div class="page-actions-bar">
        <div class="page-actions-left"><h2 class="page-title">Skills Library</h2></div>
        <div class="page-actions-right">
          <button class="btn btn-ghost" onclick="openGroupsModal()">
            <svg viewBox="0 0 24 24" width="14" height="14" fill="none"
              stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="7" height="7" rx="1"/>
              <rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/>
              <rect x="14" y="14" width="7" height="7" rx="1"/></svg>
            Groups
          </button>
          <button class="btn btn-primary" onclick="openCreateSkillModal()">+ New Skill</button>
        </div>
      </div>

      <main class="skills-page">
        <aside class="sidebar">
          <div class="filter-section">
            <h3>Category</h3>
            <ul class="filter-list" id="category-filters">
              <li class="filter-item active" data-category="all" onclick="filterCategory('all')">All</li>
              <li class="filter-item" data-category="quality" onclick="filterCategory('quality')">Quality</li>
              <li class="filter-item" data-category="workflow" onclick="filterCategory('workflow')">Workflow</li>
              <li class="filter-item" data-category="debugging" onclick="filterCategory('debugging')">Debugging</li>
              <li class="filter-item" data-category="planning" onclick="filterCategory('planning')">Planning</li>
              <li class="filter-item" data-category="system" onclick="filterCategory('system')">System</li>
              <li class="filter-item" data-category="custom" onclick="filterCategory('custom')">Custom</li>
            </ul>
          </div>
          <div class="filter-section">
            <h3>Search</h3>
            <input type="text" id="search-input" class="search-input"
              placeholder="Search skills..." oninput="filterSkills()">
          </div>
          <div class="filter-section stats">
            <span id="skill-count">0 skills</span>
          </div>
        </aside>

        <div class="skills-grid" id="skills-grid">
          <div class="loading">Loading skills...</div>
        </div>
      </main>

      <!-- Create/Edit Skill Modal -->
      <div class="modal-overlay" id="skill-modal">
        <div class="modal modal-wide">
          <div class="modal-header">
            <h2 id="skill-modal-title">New Skill</h2>
            <button class="btn-icon" onclick="closeSkillModal()">&times;</button>
          </div>
          <div class="form-group">
            <label for="skill-name">Name</label>
            <input type="text" id="skill-name" placeholder="e.g. verification-before-completion">
          </div>
          <div class="form-row">
            <div class="form-group">
              <label for="skill-category">Category</label>
              <select id="skill-category">
                <option value="quality">Quality</option>
                <option value="workflow">Workflow</option>
                <option value="debugging">Debugging</option>
                <option value="planning">Planning</option>
                <option value="system">System</option>
                <option value="custom" selected>Custom</option>
              </select>
            </div>
            <div class="form-group">
              <label for="skill-tags">Tags (comma-separated)</label>
              <input type="text" id="skill-tags" placeholder="e.g. gate, completion, tdd">
            </div>
          </div>
          <div class="form-group">
            <label for="skill-description">Description
              <span class="help-text">(trigger conditions — when should this skill activate?)</span></label>
            <input type="text" id="skill-description" placeholder="Use when the agent claims work is done...">
          </div>
          <div class="form-group">
            <label>Content <span class="help-text">(the full skill document the agent receives)</span></label>
            <div class="editor-tabs">
              <button class="editor-tab active" onclick="switchEditorTab('edit')">Edit</button>
              <button class="editor-tab" onclick="switchEditorTab('preview')">Preview</button>
            </div>
            <textarea id="skill-content" class="skill-editor"
              placeholder="# Skill Name&#10;&#10;## Iron Law&#10;..."></textarea>
            <div id="skill-preview" class="skill-preview" style="display:none;"></div>
          </div>
          <div class="form-actions">
            <button class="btn btn-ghost" onclick="closeSkillModal()">Cancel</button>
            <button class="btn btn-primary" id="skill-save-btn" onclick="saveSkill()">Create</button>
          </div>
        </div>
      </div>

      <!-- Skill Groups Modal -->
      <div class="modal-overlay" id="groups-modal">
        <div class="modal modal-wide">
          <div class="modal-header">
            <h2>Skill Groups</h2>
            <button class="btn-icon" onclick="closeGroupsModal()">&times;</button>
          </div>
          <div class="groups-layout">
            <div class="groups-list" id="groups-list">
              <div class="loading">Loading groups...</div>
            </div>
            <div class="group-detail" id="group-detail" style="display:none;">
              <div class="form-group">
                <label for="group-name">Group Name</label>
                <input type="text" id="group-name" placeholder="e.g. Quality Essentials">
              </div>
              <div class="form-group">
                <label for="group-description">Description</label>
                <input type="text" id="group-description" placeholder="Skills for enforcing quality...">
              </div>
              <div class="form-group">
                <label>Skills in Group</label>
                <div class="group-skills" id="group-skills"></div>
                <div class="form-group" style="margin-top:8px;">
                  <select id="add-skill-to-group" onchange="addSkillToGroup()">
                    <option value="">+ Add a skill...</option>
                  </select>
                </div>
              </div>
              <div class="form-actions">
                <button class="btn btn-danger btn-sm" id="delete-group-btn" onclick="deleteGroup()">Delete</button>
                <button class="btn btn-primary btn-sm" onclick="saveGroup()">Save</button>
              </div>
            </div>
          </div>
          <div class="form-actions" style="margin-top:12px; justify-content: flex-start;">
            <button class="btn btn-ghost" onclick="createGroup()">+ New Group</button>
          </div>
        </div>
      </div>

      <div id="toast-container" class="toast-container"></div>

      <script>
    #{js()}
      </script>
    """

    UIHelpers.page_template("Symphony Skills", "skills", css(), body)
  end

  defp css do
    UIHelpers.form_css() <>
      UIHelpers.modal_css() <>
      UIHelpers.page_actions_css() <>
      ~S"""
      .skills-page {
        display: flex; height: calc(100vh - 90px); overflow: hidden;
      }
      .sidebar {
        width: 200px; flex-shrink: 0; padding: 16px;
        border-right: 1px solid var(--border); background: var(--bg-secondary);
        overflow-y: auto;
      }
      .filter-section { margin-bottom: 20px; }
      .filter-section h3 {
        font-size: 0.7rem; text-transform: uppercase; letter-spacing: 0.05em;
        color: var(--text-muted); margin-bottom: 8px; font-weight: 600;
      }
      .filter-list { list-style: none; }
      .filter-item {
        padding: 5px 10px; border-radius: var(--radius-sm); cursor: pointer;
        font-size: 0.82rem; color: var(--text-secondary); margin-bottom: 2px;
        transition: all var(--transition);
      }
      .filter-item:hover { background: var(--bg-hover); color: var(--text-primary); }
      .filter-item.active { background: rgba(88,166,255,0.12); color: var(--accent); font-weight: 500; }
      .search-input {
        width: 100%; padding: 6px 10px; background: var(--bg-primary);
        border: 1px solid var(--border); border-radius: var(--radius-sm);
        color: var(--text-primary); font-size: 0.82rem; outline: none;
      }
      .search-input:focus { border-color: var(--accent); }
      .stats { font-size: 0.75rem; color: var(--text-muted); }

      .skills-grid {
        flex: 1; padding: 20px; overflow-y: auto;
        display: grid; grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
        gap: 12px; align-content: start;
      }
      .skill-card {
        background: var(--bg-secondary); border: 1px solid var(--border);
        border-radius: var(--radius); padding: 16px; cursor: pointer;
        transition: all var(--transition); position: relative;
      }
      .skill-card:hover { border-color: var(--accent); transform: translateY(-1px); }
      .skill-card-header { display: flex; align-items: flex-start;
        justify-content: space-between; margin-bottom: 8px; }
      .skill-card-name { font-size: 0.92rem; font-weight: 600; color: var(--text-primary); }
      .skill-card-actions { display: flex; gap: 4px; opacity: 0; transition: opacity var(--transition); }
      .skill-card:hover .skill-card-actions { opacity: 1; }
      .skill-card-desc { font-size: 0.78rem; color: var(--text-muted); margin-bottom: 10px;
        line-height: 1.5; display: -webkit-box; -webkit-line-clamp: 2;
        -webkit-box-orient: vertical; overflow: hidden; }
      .skill-card-footer { display: flex; align-items: center; gap: 6px; flex-wrap: wrap; }
      .category-badge {
        display: inline-block; padding: 2px 8px; border-radius: 10px;
        font-size: 0.65rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.03em;
      }
      .cat-quality { background: rgba(63,185,80,0.15); color: var(--green); }
      .cat-workflow { background: rgba(88,166,255,0.15); color: var(--accent); }
      .cat-debugging { background: rgba(248,81,73,0.15); color: var(--red); }
      .cat-planning { background: rgba(210,153,34,0.15); color: var(--yellow); }
      .cat-system { background: rgba(188,140,255,0.15); color: var(--purple); }
      .cat-custom { background: rgba(139,148,158,0.15); color: var(--text-muted); }
      .tag-pill {
        display: inline-block; padding: 1px 6px; border-radius: 8px;
        font-size: 0.65rem; background: var(--bg-tertiary); color: var(--text-muted);
        border: 1px solid var(--border-light);
      }
      .built-in-badge {
        font-size: 0.6rem; color: var(--purple); border: 1px solid rgba(188,140,255,0.3);
        padding: 1px 5px; border-radius: 6px;
      }

      .editor-tabs { display: flex; gap: 0; margin-bottom: 0; }
      .editor-tab {
        padding: 5px 14px; font-size: 0.78rem; cursor: pointer;
        background: var(--bg-tertiary); border: 1px solid var(--border);
        border-bottom: none; color: var(--text-muted);
        border-radius: var(--radius-sm) var(--radius-sm) 0 0;
      }
      .editor-tab.active { background: var(--bg-primary); color: var(--text-primary); }
      .skill-editor {
        width: 100%; min-height: 300px; padding: 12px; background: var(--bg-primary);
        border: 1px solid var(--border); border-radius: 0 0 var(--radius-sm) var(--radius-sm);
        color: var(--text-primary); font-family: 'Cascadia Code', 'Fira Code', monospace;
        font-size: 0.82rem; resize: vertical; outline: none; line-height: 1.6;
      }
      .skill-editor:focus { border-color: var(--accent); }
      .skill-preview {
        width: 100%; min-height: 300px; padding: 12px; background: var(--bg-primary);
        border: 1px solid var(--border); border-radius: 0 0 var(--radius-sm) var(--radius-sm);
        color: var(--text-secondary); font-size: 0.82rem; line-height: 1.6;
        overflow-y: auto; white-space: pre-wrap;
      }

      .groups-layout { display: flex; gap: 16px; min-height: 300px; }
      .groups-list {
        width: 200px; flex-shrink: 0; border-right: 1px solid var(--border);
        padding-right: 16px; overflow-y: auto;
      }
      .group-item {
        padding: 8px 10px; border-radius: var(--radius-sm); cursor: pointer;
        font-size: 0.82rem; color: var(--text-secondary); margin-bottom: 4px;
        transition: all var(--transition);
      }
      .group-item:hover { background: var(--bg-hover); }
      .group-item.active { background: rgba(88,166,255,0.12); color: var(--accent); }
      .group-item-count { font-size: 0.7rem; color: var(--text-muted); }
      .group-detail { flex: 1; }
      .group-skills { display: flex; flex-direction: column; gap: 4px; }
      .group-skill-item {
        display: flex; align-items: center; justify-content: space-between;
        padding: 6px 10px; background: var(--bg-primary); border: 1px solid var(--border);
        border-radius: var(--radius-sm); font-size: 0.82rem;
      }
      .group-skill-remove {
        background: none; border: none; color: var(--text-muted);
        cursor: pointer; font-size: 1rem; padding: 0 4px;
      }
      .group-skill-remove:hover { color: var(--red); }
      .loading { color: var(--text-muted); font-size: 0.85rem; padding: 20px; }
      """
  end

  defp js do
    UIHelpers.esc_js() <>
      UIHelpers.toast_js() <>
      ~S"""
      var skills = [];
      var skillGroups = [];
      var currentCategory = 'all';
      var editingSkillId = null;
      var editingGroupId = null;
      var currentGroupSkillIds = [];

      document.addEventListener('DOMContentLoaded', function() {
        loadSkills();
        loadGroups();
      });

      function loadSkills() {
        fetch('/board/api/skills').then(r => r.json()).then(data => {
          skills = data.skills || [];
          renderSkills();
        });
      }

      function loadGroups() {
        fetch('/board/api/skill-groups').then(r => r.json()).then(data => {
          skillGroups = data.skill_groups || [];
        });
      }

      function renderSkills() {
        var grid = document.getElementById('skills-grid');
        var search = (document.getElementById('search-input').value || '').toLowerCase();
        var filtered = skills.filter(function(s) {
          if (currentCategory !== 'all' && s.category !== currentCategory) return false;
          if (search && s.name.toLowerCase().indexOf(search) === -1 &&
              (s.description || '').toLowerCase().indexOf(search) === -1 &&
              (s.tags || []).join(' ').toLowerCase().indexOf(search) === -1) return false;
          return true;
        });

        document.getElementById('skill-count').textContent =
          filtered.length + ' skill' + (filtered.length !== 1 ? 's' : '');

        if (filtered.length === 0) {
          grid.innerHTML = '<div class="loading">No skills found. Create one to get started.</div>';
          return;
        }

        grid.innerHTML = filtered.map(function(s) {
          var catClass = 'cat-' + (s.category || 'custom');
          var tags = (s.tags || []).map(function(t) {
            return '<span class="tag-pill">' + esc(t) + '</span>';
          }).join('');
          var builtIn = s.built_in ? '<span class="built-in-badge">built-in</span>' : '';
          return '<div class="skill-card" onclick="openEditSkillModal(\'' + s.id + '\')">' +
            '<div class="skill-card-header">' +
              '<span class="skill-card-name">' + esc(s.name) + '</span>' +
              '<div class="skill-card-actions">' +
                '<button class="btn btn-ghost btn-sm"'
                + ' onclick="event.stopPropagation();duplicateSkill(\'' + s.id + '\')"'
                + ' title="Duplicate">&#x2398;</button>' +
                (s.built_in ? '' : '<button class="btn btn-danger btn-sm"'
                + ' onclick="event.stopPropagation();deleteSkill(\'' + s.id + '\')"'
                + ' title="Delete">&times;</button>') +
              '</div>' +
            '</div>' +
            '<div class="skill-card-desc">' + esc(s.description || 'No description') + '</div>' +
            '<div class="skill-card-footer">' +
              '<span class="category-badge ' + catClass + '">' + esc(s.category) + '</span>' +
              builtIn + tags +
            '</div>' +
          '</div>';
        }).join('');
      }

      function filterCategory(cat) {
        currentCategory = cat;
        document.querySelectorAll('.filter-item').forEach(function(el) {
          el.classList.toggle('active', el.dataset.category === cat);
        });
        renderSkills();
      }

      function filterSkills() { renderSkills(); }

      // --- Skill Modal ---

      function openCreateSkillModal() {
        editingSkillId = null;
        document.getElementById('skill-modal-title').textContent = 'New Skill';
        document.getElementById('skill-save-btn').textContent = 'Create';
        document.getElementById('skill-name').value = '';
        document.getElementById('skill-category').value = 'custom';
        document.getElementById('skill-tags').value = '';
        document.getElementById('skill-description').value = '';
        document.getElementById('skill-content').value = '';
        document.getElementById('skill-name').removeAttribute('readonly');
        switchEditorTab('edit');
        document.getElementById('skill-modal').classList.add('active');
      }

      function openEditSkillModal(id) {
        var s = skills.find(function(sk) { return sk.id === id; });
        if (!s) return;
        editingSkillId = id;
        document.getElementById('skill-modal-title').textContent = s.built_in ? 'View Skill (built-in)' : 'Edit Skill';
        document.getElementById('skill-save-btn').textContent = s.built_in ? 'Duplicate & Edit' : 'Save';
        document.getElementById('skill-name').value = s.name;
        document.getElementById('skill-category').value = s.category;
        document.getElementById('skill-tags').value = (s.tags || []).join(', ');
        document.getElementById('skill-description').value = s.description || '';
        document.getElementById('skill-content').value = s.content || '';
        if (s.built_in) {
          document.getElementById('skill-name').setAttribute('readonly', 'true');
        } else {
          document.getElementById('skill-name').removeAttribute('readonly');
        }
        switchEditorTab('edit');
        document.getElementById('skill-modal').classList.add('active');
      }

      function closeSkillModal() {
        document.getElementById('skill-modal').classList.remove('active');
        editingSkillId = null;
      }

      function switchEditorTab(tab) {
        var editTab = document.querySelector('.editor-tab:first-child');
        var previewTab = document.querySelector('.editor-tab:last-child');
        var editor = document.getElementById('skill-content');
        var preview = document.getElementById('skill-preview');
        if (tab === 'edit') {
          editTab.classList.add('active'); previewTab.classList.remove('active');
          editor.style.display = ''; preview.style.display = 'none';
        } else {
          editTab.classList.remove('active'); previewTab.classList.add('active');
          editor.style.display = 'none'; preview.style.display = '';
          preview.textContent = editor.value;
        }
      }

      function saveSkill() {
        var name = document.getElementById('skill-name').value.trim();
        if (!name) { showToast('Name is required', {type: 'error'}); return; }

        var body = {
          name: name,
          category: document.getElementById('skill-category').value,
          tags: document.getElementById('skill-tags').value,
          description: document.getElementById('skill-description').value,
          content: document.getElementById('skill-content').value
        };

        if (editingSkillId) {
          var existing = skills.find(function(s) { return s.id === editingSkillId; });
          if (existing && existing.built_in) {
            // Duplicate instead of editing
            fetch('/board/api/skills/' + editingSkillId + '/duplicate', { method: 'POST' })
              .then(r => r.json())
              .then(function(newSkill) {
                // Now update the duplicate with our changes
                body.name = name.replace(' (copy)', '') + ' (custom)';
                return fetch('/board/api/skills/' + newSkill.id, {
                  method: 'PATCH',
                  headers: {'Content-Type': 'application/json'},
                  body: JSON.stringify(body)
                });
              })
              .then(r => r.json())
              .then(function() {
                closeSkillModal();
                loadSkills();
                showToast('Skill duplicated and saved', {type: 'success'});
              });
            return;
          }
          fetch('/board/api/skills/' + editingSkillId, {
            method: 'PATCH',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify(body)
          }).then(r => r.json()).then(function() {
            closeSkillModal();
            loadSkills();
            showToast('Skill updated', {type: 'success'});
          });
        } else {
          fetch('/board/api/skills', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify(body)
          }).then(r => r.json()).then(function() {
            closeSkillModal();
            loadSkills();
            showToast('Skill created', {type: 'success'});
          });
        }
      }

      function duplicateSkill(id) {
        fetch('/board/api/skills/' + id + '/duplicate', { method: 'POST' })
          .then(r => r.json())
          .then(function() {
            loadSkills();
            showToast('Skill duplicated', {type: 'success'});
          });
      }

      function deleteSkill(id) {
        if (!confirm('Delete this skill? It will be removed from all issues and groups.')) return;
        fetch('/board/api/skills/' + id, { method: 'DELETE' })
          .then(function(r) {
            if (r.ok) {
              loadSkills();
              showToast('Skill deleted', {type: 'success'});
            } else {
              return r.json().then(function(d) { showToast(d.message || 'Cannot delete', {type: 'error'}); });
            }
          });
      }

      // --- Skill Groups Modal ---

      function openGroupsModal() {
        loadGroups();
        setTimeout(renderGroups, 200);
        document.getElementById('groups-modal').classList.add('active');
      }

      function closeGroupsModal() {
        document.getElementById('groups-modal').classList.remove('active');
        editingGroupId = null;
      }

      function renderGroups() {
        var list = document.getElementById('groups-list');
        if (skillGroups.length === 0) {
          list.innerHTML = '<div class="loading">No groups yet.</div>';
          document.getElementById('group-detail').style.display = 'none';
          return;
        }
        list.innerHTML = skillGroups.map(function(g) {
          var active = editingGroupId === g.id ? ' active' : '';
          return '<div class="group-item' + active + '" onclick="selectGroup(\'' + g.id + '\')">' +
            '<div>' + esc(g.name) + '</div>' +
            '<div class="group-item-count">' + (g.skill_ids || []).length + ' skills</div>' +
          '</div>';
        }).join('');
      }

      function selectGroup(id) {
        var g = skillGroups.find(function(gr) { return gr.id === id; });
        if (!g) return;
        editingGroupId = id;
        currentGroupSkillIds = (g.skill_ids || []).slice();
        document.getElementById('group-name').value = g.name;
        document.getElementById('group-description').value = g.description || '';
        renderGroupSkills();
        document.getElementById('group-detail').style.display = '';
        renderGroups();
      }

      function renderGroupSkills() {
        var container = document.getElementById('group-skills');
        container.innerHTML = currentGroupSkillIds.map(function(sid) {
          var s = skills.find(function(sk) { return sk.id === sid; });
          var name = s ? s.name : sid;
          return '<div class="group-skill-item">' +
            '<span>' + esc(name) + '</span>' +
            '<button class="group-skill-remove" onclick="removeSkillFromGroup(\'' + sid + '\')">&times;</button>' +
          '</div>';
        }).join('');

        // Update "add" dropdown
        var select = document.getElementById('add-skill-to-group');
        select.innerHTML = '<option value="">+ Add a skill...</option>';
        skills.forEach(function(s) {
          if (currentGroupSkillIds.indexOf(s.id) === -1) {
            select.innerHTML += '<option value="' + s.id + '">' + esc(s.name) + '</option>';
          }
        });
      }

      function addSkillToGroup() {
        var select = document.getElementById('add-skill-to-group');
        var sid = select.value;
        if (!sid) return;
        currentGroupSkillIds.push(sid);
        select.value = '';
        renderGroupSkills();
      }

      function removeSkillFromGroup(sid) {
        currentGroupSkillIds = currentGroupSkillIds.filter(function(id) { return id !== sid; });
        renderGroupSkills();
      }

      function saveGroup() {
        var name = document.getElementById('group-name').value.trim();
        if (!name) { showToast('Group name is required', {type: 'error'}); return; }
        var body = {
          name: name,
          description: document.getElementById('group-description').value,
          skill_ids: currentGroupSkillIds
        };

        if (editingGroupId) {
          fetch('/board/api/skill-groups/' + editingGroupId, {
            method: 'PATCH',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify(body)
          }).then(r => r.json()).then(function() {
            loadGroups();
            setTimeout(function() { renderGroups(); selectGroup(editingGroupId); }, 200);
            showToast('Group saved', {type: 'success'});
          });
        } else {
          fetch('/board/api/skill-groups', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify(body)
          }).then(r => r.json()).then(function(g) {
            loadGroups();
            setTimeout(function() { editingGroupId = g.id; renderGroups(); selectGroup(g.id); }, 200);
            showToast('Group created', {type: 'success'});
          });
        }
      }

      function createGroup() {
        editingGroupId = null;
        currentGroupSkillIds = [];
        document.getElementById('group-name').value = '';
        document.getElementById('group-description').value = '';
        renderGroupSkills();
        document.getElementById('group-detail').style.display = '';
        renderGroups();
      }

      function deleteGroup() {
        if (!editingGroupId) return;
        if (!confirm('Delete this group?')) return;
        fetch('/board/api/skill-groups/' + editingGroupId, { method: 'DELETE' })
          .then(function(r) {
            if (r.ok) {
              editingGroupId = null;
              document.getElementById('group-detail').style.display = 'none';
              loadGroups();
              setTimeout(renderGroups, 200);
              showToast('Group deleted', {type: 'success'});
            }
          });
      }

      // Close modals on overlay click
      document.addEventListener('click', function(e) {
        if (e.target.classList.contains('modal-overlay')) {
          e.target.classList.remove('active');
        }
      });
      """
  end
end

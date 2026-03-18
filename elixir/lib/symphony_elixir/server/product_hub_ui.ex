defmodule SymphonyElixir.Server.ProductHubUI do
  @moduledoc """
  Unified Product-Centric Hub UI.

  Combines the Product Spec Sheet and Issue Board into a single workspace
  with a persistent sidebar for product navigation and tabbed main content.

  Layout: Topbar + Sidebar (products) + Tab Bar (Spec Sheet | Issues | Activity)
  """

  @doc "Render the full Product Hub HTML page."
  @spec render() :: String.t()
  def render do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Symphony</title>
      <style>
    #{css()}
      </style>
    </head>
    <body>
    #{SymphonyElixir.Server.UIHelpers.nav_topbar("hub")}
      <div class="hub-actions-bar">
        <div class="dropdown" id="add-dropdown">
          <button class="btn btn-ghost" onclick="toggleDropdown('add-dropdown')">Add &#9662;</button>
          <div class="dropdown-menu" style="left:0;right:auto">
            <button class="dropdown-item" onclick="openNewProductModal(); closeDropdowns()">New Product</button>
            <button class="dropdown-item" onclick="openNewProjectModal(); closeDropdowns()">New Project</button>
            <button class="dropdown-item" onclick="openScanModal(); closeDropdowns()">Import Projects...</button>
          </div>
        </div>
        <button class="btn btn-primary" onclick="openIssueCreateModal()">+ Issue</button>
      </div>

      <div class="hub-layout">
        <!-- Sidebar -->
        <aside class="sidebar" id="sidebar">
          <div class="sidebar-scroll">
            <div class="sidebar-section">
              <div class="sidebar-title">Products</div>
              <div id="sidebar-products"></div>
            </div>
            <div class="sidebar-section" style="margin-top:4px">
              <div class="sidebar-item" id="all-issues-item" onclick="selectAllIssues()">
                <span class="sidebar-item-name">All Issues</span>
                <span class="sidebar-badge" id="all-issues-badge">0</span>
              </div>
            </div>
            <div class="sidebar-section" id="all-projects-section" style="margin-top:4px">
              <div style="display:flex;align-items:center;justify-content:space-between">
                <div class="sidebar-title">Projects</div>
                <button class="btn btn-ghost" style="font-size:0.6rem;padding:1px 5px;min-height:0" id="projects-filter-btn" onclick="toggleProjectsFilter()">All</button>
              </div>
              <div id="sidebar-all-projects"></div>
            </div>
          </div>
        </aside>

        <!-- Main Content -->
        <div class="hub-main">
          <nav class="tab-bar" id="tab-bar">
            <div class="tab-item active" data-tab="spec" onclick="switchTab('spec')">Spec Sheet</div>
            <div class="tab-item" data-tab="issues" onclick="switchTab('issues')">Issues <span class="tab-badge" id="issues-tab-badge">0</span></div>
            <div class="tab-item" data-tab="activity" onclick="switchTab('activity')">Activity <span class="tab-badge" id="activity-tab-badge">0</span></div>
            <div class="tab-item" data-tab="kb" onclick="switchTab('kb')">Knowledge Base <span class="tab-badge" id="kb-tab-badge" style="display:none">0</span></div>
            <div class="tab-actions" id="tab-actions"></div>
          </nav>
          <div class="tab-content" id="tab-content">
            <div id="welcome-screen" class="empty-state">
              <div class="empty-icon">
                <svg viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/></svg>
              </div>
              <h2>Welcome to Symphony</h2>
              <p>Select a product from the sidebar, or create one to get started.</p>
              <button class="btn btn-primary" onclick="openNewProductModal()">Create Product</button>
            </div>
          </div>
        </div>
      </div>

    #{modals()}

      <script>
    #{javascript()}
      </script>
    </body>
    </html>
    """
  end

  defp modals do
    """
      <!-- New Product Modal -->
      <div class="modal-overlay" id="prod-modal" style="display:none">
        <div class="modal">
          <div class="modal-header">
            <h2 id="prod-modal-title">New Product</h2>
            <button class="modal-close" onclick="closeModal('prod-modal')">&times;</button>
          </div>
          <div class="ai-draft-bar" id="prod-ai-draft-bar">
            <input type="text" id="prod-ai-draft-input" class="ai-draft-input" placeholder="Describe your product in a few words..." onkeydown="if(event.key==='Enter'){event.preventDefault();aiDraftProduct();}">
            <button type="button" class="btn btn-accent-soft btn-sm" id="prod-ai-draft-btn" onclick="aiDraftProduct()">AI Draft</button>
          </div>
          <div class="modal-body">
            <input type="hidden" id="product-form-id">
            <label>Name<input type="text" id="product-form-name" placeholder="e.g. B2C Async API"></label>
            <label>Description<textarea id="product-form-desc" placeholder="What does this product cover?"></textarea></label>
            <label>Labels (comma-separated)<input type="text" id="product-form-labels" placeholder="platform, api, internal"></label>
            <label>Projects</label>
            <div class="project-checklist" id="project-checklist"></div>
          </div>
          <div class="modal-footer">
            <button class="btn btn-danger" id="prod-delete-btn" style="display:none;margin-right:auto" onclick="deleteCurrentProduct()">Delete</button>
            <button class="btn btn-ghost" onclick="closeModal('prod-modal')">Cancel</button>
            <button class="btn btn-primary" onclick="saveProduct()">Save</button>
          </div>
        </div>
      </div>

      <!-- Add/Edit Feature Modal -->
      <div class="modal-overlay" id="feature-modal" style="display:none">
        <div class="modal modal-sm">
          <div class="modal-header">
            <h2 id="feature-modal-title">Add Feature</h2>
            <button class="modal-close" onclick="closeModal('feature-modal')">&times;</button>
          </div>
          <div class="modal-body">
            <input type="hidden" id="feature-edit-id">
            <label>Feature Name<input type="text" id="feature-name" placeholder="e.g. API Key Management"></label>
            <label>Description<textarea id="feature-desc" placeholder="What should this feature cover?"></textarea></label>
            <label>Category
              <input type="text" id="feature-category" placeholder="e.g. Security, Data Pipeline, Infrastructure" list="category-list">
              <datalist id="category-list"></datalist>
            </label>
            <label>Dependencies
              <div id="feature-deps-checklist" class="project-checklist" style="max-height:150px"></div>
            </label>
          </div>
          <div class="modal-footer">
            <button class="btn btn-ghost" onclick="closeModal('feature-modal')">Cancel</button>
            <button class="btn btn-primary" onclick="saveFeature()">Save</button>
          </div>
        </div>
      </div>

      <!-- Generate Features Modal -->
      <div class="modal-overlay" id="generate-modal" style="display:none">
        <div class="modal">
          <div class="modal-header">
            <h2>Generate Features with Agent</h2>
            <button class="modal-close" onclick="closeModal('generate-modal')">&times;</button>
          </div>
          <div class="modal-body">
            <label>Describe your product and what features you expect
              <textarea id="generate-prompt" rows="5" placeholder="e.g. This is a B2C async API product..."></textarea>
            </label>
            <label>Agent Skills <button type="button" class="skill-picker-toggle" onclick="toggleSkillPicker('generate-skills')">select skills...</button></label>
            <div class="skill-picker" id="generate-skills" style="display:none"></div>
            <div class="ai-hint">An agent will analyze the projects and propose features as follow-up issues.</div>
          </div>
          <div class="modal-footer">
            <button class="btn btn-ghost" onclick="closeModal('generate-modal')">Cancel</button>
            <button class="btn btn-primary" id="generate-btn" onclick="generateFeatures()">Create Agent Task</button>
          </div>
        </div>
      </div>

      <!-- Code Review Modal -->
      <div class="modal-overlay" id="code-review-modal" style="display:none">
        <div class="modal">
          <div class="modal-header">
            <h2>Code Review</h2>
            <button class="modal-close" onclick="closeModal('code-review-modal')">&times;</button>
          </div>
          <div class="modal-body">
            <label>Focus areas (optional)
              <textarea id="review-focus" rows="4" placeholder="e.g. Security, error handling, test coverage..."></textarea>
            </label>
            <label>Agent Skills <button type="button" class="skill-picker-toggle" onclick="toggleSkillPicker('review-skills')">select skills...</button></label>
            <div class="skill-picker" id="review-skills" style="display:none"></div>
            <div class="ai-hint">An agent will review all project codebases and propose findings.</div>
          </div>
          <div class="modal-footer">
            <button class="btn btn-ghost" onclick="closeModal('code-review-modal')">Cancel</button>
            <button class="btn btn-primary" id="code-review-btn" onclick="startCodeReview()">Start Code Review</button>
          </div>
        </div>
      </div>

      <!-- Generate Definition Modal -->
      <div class="modal-overlay" id="gendef-modal" style="display:none">
        <div class="modal">
          <div class="modal-header">
            <h2>Generate Product Definition</h2>
            <button class="modal-close" onclick="closeModal('gendef-modal')">&times;</button>
          </div>
          <div class="modal-body">
            <label>Additional context (optional)
              <textarea id="gendef-context" rows="3" placeholder="e.g. This product focuses on our B2C platform..."></textarea>
            </label>
            <label>Agent Skills <button type="button" class="skill-picker-toggle" onclick="toggleSkillPicker('gendef-skills')">select skills...</button></label>
            <div class="skill-picker" id="gendef-skills" style="display:none"></div>
            <div class="ai-hint">An agent will analyze the projects and generate a product definition.</div>
          </div>
          <div class="modal-footer">
            <button class="btn btn-ghost" onclick="closeModal('gendef-modal')">Cancel</button>
            <button class="btn btn-primary" id="gendef-btn" onclick="generateDefinition()">Generate Definition</button>
          </div>
        </div>
      </div>

      <!-- Product Task Modal -->
      <div class="modal-overlay" id="product-task-modal" style="display:none">
        <div class="modal">
          <div class="modal-header">
            <h2>Create Product Task</h2>
            <button class="modal-close" onclick="closeModal('product-task-modal')">&times;</button>
          </div>
          <div class="modal-body">
            <label>Task title<input type="text" id="ptask-title" placeholder="e.g. Generate runbook, Write API docs..."></label>
            <label>Description / prompt<textarea id="ptask-prompt" rows="5" placeholder="Describe what the agent should do..."></textarea></label>
            <label>Priority
              <select id="ptask-priority"><option value="1">High</option><option value="2" selected>Medium</option><option value="3">Low</option></select>
            </label>
            <label>Agent Skills <button type="button" class="skill-picker-toggle" onclick="toggleSkillPicker('ptask-skills')">select skills...</button></label>
            <div class="skill-picker" id="ptask-skills" style="display:none"></div>
            <div class="ai-hint">Creates an agent task scoped to this product.</div>
          </div>
          <div class="modal-footer">
            <button class="btn btn-ghost" onclick="closeModal('product-task-modal')">Cancel</button>
            <button class="btn btn-primary" id="ptask-btn" onclick="createProductTask()">Create Task</button>
          </div>
        </div>
      </div>

      <!-- Feature Detail Modal -->
      <div class="modal-overlay" id="detail-modal" style="display:none">
        <div class="modal">
          <div class="modal-header">
            <h2 id="detail-modal-title">Feature Details</h2>
            <button class="modal-close" onclick="closeModal('detail-modal')">&times;</button>
          </div>
          <div class="modal-body" id="detail-modal-body"></div>
          <div class="modal-footer">
            <button class="btn btn-ghost" onclick="closeModal('detail-modal')">Close</button>
          </div>
        </div>
      </div>

      <!-- Issue Create Modal (shared widget) -->
    #{SymphonyElixir.Server.UIHelpers.create_issue_modal_html(prefix: "hi", on_submit: "handleIssueSubmit", on_cancel: "closeIssueModal", ai_draft: true, show_skills_picker: true)}

      <!-- Project Create/Edit Modal -->
      <div class="modal-overlay" id="project-modal" style="display:none">
        <div class="modal">
          <div class="modal-header">
            <h2 id="project-modal-title">New Project</h2>
            <button class="modal-close" onclick="closeModal('project-modal')">&times;</button>
          </div>
          <div class="ai-draft-bar" id="project-ai-draft-bar">
            <input type="text" id="project-ai-draft-input" class="ai-draft-input" placeholder="Describe your project in a few words..." onkeydown="if(event.key==='Enter'){event.preventDefault();aiDraftProject();}">
            <button type="button" class="btn btn-accent-soft btn-sm" id="project-ai-draft-btn" onclick="aiDraftProject()">AI Draft</button>
          </div>
          <form id="project-form" onsubmit="handleProjectSubmit(event)">
            <input type="hidden" id="project-form-id" value="">
            <div class="form-group"><label for="project-form-name">Project Name</label><input type="text" id="project-form-name" required placeholder="My Project"></div>
            <div class="form-group"><label for="project-form-desc">Description</label><textarea id="project-form-desc" rows="3" placeholder="What is this project about?"></textarea></div>
            <div class="form-group"><label for="project-form-path">Local Directory Path</label>
              <div style="display:flex;gap:8px"><input type="text" id="project-form-path" placeholder="/home/user/projects/my-app" style="flex:1"><button type="button" class="btn btn-ghost btn-sm" onclick="browseFolder('project-form-path')">Browse</button></div>
            </div>
            <div class="form-group"><label for="project-form-repo">Repository URL (optional)</label><input type="text" id="project-form-repo" placeholder="https://github.com/user/repo.git"></div>
            <div class="form-row">
              <div class="form-group"><label for="project-form-labels">Labels (comma-separated)</label><input type="text" id="project-form-labels" placeholder="python, api, data-pipeline"></div>
              <div class="form-group"><label for="project-form-priority">Priority</label>
                <select id="project-form-priority"><option value="0">No priority</option><option value="1">Urgent</option><option value="2">High</option><option value="3">Medium</option><option value="4">Low</option></select>
              </div>
            </div>
            <div class="form-actions">
              <button type="button" class="btn btn-ghost" onclick="closeModal('project-modal')">Cancel</button>
              <button type="submit" class="btn btn-primary" id="project-form-submit">Create Project</button>
            </div>
          </form>
        </div>
      </div>

      <!-- Import / Scan Modal -->
      <div class="modal-overlay" id="scan-modal" style="display:none">
        <div class="modal modal-wide">
          <div class="modal-header">
            <h2>Import from Directory</h2>
            <button class="modal-close" onclick="closeModal('scan-modal')">&times;</button>
          </div>
          <div class="modal-body">
            <div class="form-group"><label for="scan-root-path">Root Directory</label>
              <div style="display:flex;gap:8px">
                <input type="text" id="scan-root-path" placeholder="C:\Projects or /home/user/repos" style="flex:1">
                <button type="button" class="btn btn-ghost btn-sm" onclick="browseFolder('scan-root-path')">Browse</button>
                <button type="button" class="btn btn-primary btn-sm" onclick="scanDirectory()" id="scan-btn">Scan</button>
              </div>
              <small style="font-size:0.72rem;color:var(--text-muted);margin-top:4px;display:block">Recursively scans for git repos and projects.</small>
            </div>
            <div style="display:flex;gap:16px;margin-top:8px">
              <label style="display:flex;align-items:center;gap:4px;font-size:0.8rem;color:var(--text-secondary);cursor:pointer"><input type="checkbox" id="scan-ai-summarize" checked> AI summarize</label>
              <label style="display:flex;align-items:center;gap:4px;font-size:0.8rem;color:var(--text-secondary);cursor:pointer"><input type="checkbox" id="scan-git-pull"> Git pull latest</label>
            </div>
            <div id="scan-results" style="margin-top:12px"></div>
          </div>
          <div class="modal-footer">
            <button class="btn btn-ghost" onclick="closeModal('scan-modal')">Cancel</button>
            <button class="btn btn-primary" id="import-btn" style="display:none" onclick="importScanned()">Import Selected</button>
          </div>
        </div>
      </div>
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
      UIHelpers.markdown_css() <>
      UIHelpers.skeleton_css() <>
      UIHelpers.hub_layout_css() <>
      UIHelpers.nav_active_css() <>
      UIHelpers.ai_draft_css() <>
      UIHelpers.skill_picker_css() <>
      UIHelpers.dropdown_css() <>
      UIHelpers.spinner_css() <>
      UIHelpers.pulse_css() <>
      ~S"""

      body { height: 100vh; display: flex; flex-direction: column; overflow: hidden; }
      .hub-actions-bar { display: flex; align-items: center; justify-content: flex-end; gap: 6px; padding: 6px 20px; border-bottom: 1px solid var(--border); background: var(--bg-primary); flex-shrink: 0; }
      .sidebar-sub-items { padding-left: 12px; overflow: hidden; }
      .sidebar-sub-items.collapsed { display: none; }
      .sidebar-project { display: flex; align-items: center; gap: 6px; padding: 4px 10px; font-size: 0.73rem; color: var(--text-muted); cursor: default; border-radius: var(--radius-sm); }
      .sidebar-project:hover { background: var(--bg-hover); color: var(--text-primary); }
      .sidebar-project .project-dot { width: 6px; height: 6px; border-radius: 50%; background: var(--accent); flex-shrink: 0; }
      .sidebar-project .project-name { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
      .sidebar-project .project-actions { display: none; gap: 2px; }
      .sidebar-project:hover .project-actions { display: flex; }
      .sidebar-project .project-action-btn { background: none; border: none; color: var(--text-muted); cursor: pointer; font-size: 0.7rem; padding: 1px 3px; border-radius: 2px; }
      .sidebar-project .project-action-btn:hover { color: var(--text-primary); background: var(--bg-tertiary); }
      .sidebar-item.drag-over { outline: 2px dashed var(--accent); outline-offset: -2px; background: color-mix(in srgb, var(--accent) 15%, transparent); }
      .sidebar-project.dragging { opacity: 0.4; }
      .sidebar-project[draggable="true"] { cursor: grab; }
      .sidebar-project[draggable="true"]:active { cursor: grabbing; }
      .sidebar-all-projects-title { display: flex; align-items: center; justify-content: space-between; }
      .sidebar-all-projects-title .sidebar-title { flex: 1; }
      .scan-card { background: var(--bg-secondary); border: 1px solid var(--border); border-radius: var(--radius-sm); padding: 10px 12px; margin-bottom: 6px; }
      .modal-close { background: none; border: none; color: var(--text-muted); font-size: 1.3rem; cursor: pointer; padding: 0 4px; }
      .modal-close:hover { color: var(--text-primary); }
      .modal-body label { display: block; font-size: 0.8rem; font-weight: 500; color: var(--text-secondary); margin-bottom: 10px; }
      .modal-body input[type="text"], .modal-body textarea, .modal-body select {
        width: 100%; padding: 7px 10px; background: var(--bg-primary); border: 1px solid var(--border);
        border-radius: var(--radius-sm); color: var(--text-primary); font-size: 0.85rem; font-family: inherit;
        outline: none; margin-top: 4px; transition: border-color var(--transition);
      }
      .modal-body input:focus, .modal-body textarea:focus, .modal-body select:focus { border-color: var(--accent); }
      .modal-body textarea { resize: vertical; min-height: 60px; }
      .modal-footer { display: flex; justify-content: flex-end; gap: 8px; margin-top: 16px; }
      .modal-sm { width: 460px; }

      /* Product checklist */
      .project-checklist { max-height: 200px; overflow-y: auto; border: 1px solid var(--border); border-radius: var(--radius-sm); padding: 6px; background: var(--bg-primary); }
      .project-check-item { display: block; padding: 3px 0; font-size: 0.8rem; cursor: pointer; color: var(--text-secondary); }
      .project-check-item input { margin-right: 6px; accent-color: var(--accent); }

      /* Empty state */
      .empty-state {
        display: flex; flex-direction: column; align-items: center; justify-content: center;
        height: 60vh; color: var(--text-muted); gap: 16px; text-align: center;
      }
      .empty-state h2 { color: var(--text-secondary); font-size: 1.2rem; }
      .empty-icon { opacity: 0.3; margin-bottom: 8px; }

      /* --- Spec Sheet (from review_ui) --- */
      .spec-sheet { padding: 24px; }
      .product-header-card { background: var(--bg-secondary); border: 1px solid var(--border); border-radius: var(--radius); padding: 18px 20px; margin-bottom: 20px; }
      .product-header-top { display: flex; align-items: center; justify-content: space-between; gap: 12px; flex-wrap: wrap; }
      .product-header-top h2 { font-size: 1.15rem; font-weight: 700; }
      .product-actions { display: flex; gap: 6px; flex-wrap: wrap; align-items: center; }
      .action-group { display: flex; gap: 4px; align-items: center; }
      .action-group + .action-group { padding-left: 6px; border-left: 1px solid var(--border); }
      .tab-loading { display: flex; align-items: center; justify-content: center; gap: 8px; padding: 40px; color: var(--text-muted); font-size: 0.85rem; }
      .scope-indicator { padding: 8px 16px; font-size: 0.8rem; color: var(--text-muted); background: var(--bg-secondary); border-bottom: 1px solid var(--border); display: flex; align-items: center; }
      .kanban-wrapper { display: flex; flex-direction: column; height: 100%; }
      .product-desc { font-size: 0.85rem; color: var(--text-secondary); margin-top: 8px; line-height: 1.5; }
      .project-tags { display: flex; gap: 6px; flex-wrap: wrap; margin-top: 10px; }
      .project-tag { display: flex; align-items: center; gap: 4px; font-size: 0.72rem; padding: 2px 8px; background: var(--bg-tertiary); border: 1px solid var(--border); border-radius: 10px; color: var(--text-secondary); }
      .project-tag-dot { width: 6px; height: 6px; border-radius: 50%; background: var(--accent); }
      .overall-bar { display: flex; align-items: center; gap: 10px; margin-top: 12px; }
      .overall-label { font-size: 0.75rem; color: var(--text-muted); flex-shrink: 0; }
      .overall-track { flex: 1; height: 6px; background: var(--bg-tertiary); border-radius: 3px; overflow: hidden; }
      .overall-fill { height: 100%; border-radius: 3px; transition: width 0.4s; }
      .overall-value { font-size: 0.8rem; font-weight: 700; min-width: 36px; text-align: right; }

      /* Category rings */
      .rings-row { display: flex; gap: 12px; flex-wrap: wrap; margin-bottom: 20px; padding: 0; }
      .ring-card { display: flex; flex-direction: column; align-items: center; gap: 6px; padding: 12px 16px; background: var(--bg-secondary); border: 1px solid var(--border); border-radius: var(--radius); cursor: pointer; transition: all var(--transition); min-width: 100px; }
      .ring-card:hover { border-color: var(--accent); }
      .ring-card.active { border-color: var(--accent); background: rgba(88,166,255,0.05); }
      .ring-svg { width: 56px; height: 56px; }
      .ring-label { font-size: 0.75rem; font-weight: 600; color: var(--text-secondary); text-align: center; max-width: 90px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
      .ring-count { font-size: 0.65rem; color: var(--text-muted); }

      /* Category sections */
      .category-section { margin-bottom: 12px; }
      .category-header { display: flex; align-items: center; gap: 8px; padding: 10px 14px; background: var(--bg-secondary); border: 1px solid var(--border); border-radius: var(--radius-sm); cursor: pointer; transition: all var(--transition); }
      .category-header:hover { border-color: var(--accent); }
      .category-chevron { font-size: 0.7rem; transition: transform 0.2s; color: var(--text-muted); }
      .category-chevron.collapsed { transform: rotate(-90deg); }
      .category-title { font-weight: 600; font-size: 0.88rem; }
      .category-stats { font-size: 0.75rem; color: var(--text-muted); margin-left: auto; }
      .category-body { padding: 8px 0 0; }
      .category-body.collapsed { display: none; }
      .add-feature-btn { display: block; width: 100%; padding: 8px; border: 1px dashed var(--border); background: transparent; color: var(--text-muted); font-size: 0.78rem; cursor: pointer; border-radius: var(--radius-sm); margin-top: 6px; transition: all var(--transition); }
      .add-feature-btn:hover { border-color: var(--accent); color: var(--accent); }

      /* Feature cards */
      .feature-card { background: var(--bg-secondary); border: 1px solid var(--border); border-radius: var(--radius-sm); padding: 10px 14px; margin-bottom: 6px; transition: all var(--transition); }
      .feature-card:hover { border-color: var(--accent); }
      .feature-card-top { display: flex; align-items: flex-start; gap: 10px; }
      .feature-status-badge { flex-shrink: 0; padding: 3px 8px; border-radius: 10px; font-size: 0.7rem; font-weight: 600; white-space: nowrap; }
      .badge-partial { background: rgba(210,153,34,0.15); color: var(--yellow); }
      .badge-in_progress { background: rgba(88,166,255,0.15); color: var(--accent); }
      .badge-planned { background: rgba(209,134,22,0.15); color: var(--orange); }
      .badge-missing { background: rgba(248,81,73,0.15); color: var(--red); }
      .badge-n_a { background: var(--bg-tertiary); color: var(--text-muted); }
      .feature-info { flex: 1; min-width: 0; }
      .feature-name { font-weight: 600; font-size: 0.88rem; }
      .feature-desc { font-size: 0.75rem; color: var(--text-muted); margin-top: 2px; display: -webkit-box; -webkit-line-clamp: 1; -webkit-box-orient: vertical; overflow: hidden; }
      .feature-meta { display: flex; flex-wrap: wrap; gap: 4px; margin-top: 6px; }
      .feature-project-tag { font-size: 0.68rem; padding: 1px 6px; border-radius: 8px; background: var(--bg-tertiary); color: var(--text-secondary); border: 1px solid var(--border); }
      .gap-warning { font-size: 0.68rem; color: var(--yellow); font-weight: 600; }
      .feature-deps { display: flex; flex-wrap: wrap; gap: 4px; margin-top: 6px; align-items: center; }
      .feature-deps-label { font-size: 0.68rem; color: var(--text-muted); }
      .dep-tag { font-size: 0.68rem; padding: 1px 6px; border-radius: 8px; background: var(--bg-tertiary); color: var(--text-secondary); border: 1px solid var(--border); cursor: pointer; }
      .dep-tag:hover { border-color: var(--accent); }
      .dep-blocked { font-size: 0.65rem; color: var(--red); font-weight: 600; }
      .feature-history { font-size: 0.7rem; color: var(--text-muted); margin-top: 6px; }
      .history-source { opacity: 0.6; }
      .feature-actions { display: flex; gap: 4px; flex-shrink: 0; align-items: flex-start; margin-left: 8px; }
      .feature-action-btn { background: none; border: 1px solid var(--border); color: var(--text-muted); padding: 2px 6px; border-radius: 4px; cursor: pointer; font-size: 0.75rem; transition: all var(--transition); }
      .feature-action-btn:hover { border-color: var(--accent); color: var(--accent); }
      .verify-btn { background: rgba(188,140,255,0.1); border: 1px solid rgba(188,140,255,0.3); color: var(--purple); padding: 2px 8px; border-radius: 4px; cursor: pointer; font-size: 0.7rem; font-weight: 500; transition: all var(--transition); }
      .verify-btn:hover { background: rgba(188,140,255,0.2); }

      /* Detail modal rows */
      .detail-project-row { display: flex; align-items: center; justify-content: space-between; padding: 8px 0; border-bottom: 1px solid var(--border-light); }
      .detail-project-name { font-weight: 500; font-size: 0.85rem; }
      .detail-status-btn { cursor: pointer; border: none; padding: 4px 10px; border-radius: 10px; font-size: 0.75rem; font-weight: 600; transition: all var(--transition); }
      .detail-status-btn:hover { filter: brightness(1.2); }

      /* Gap section */
      .gap-section { background: var(--bg-secondary); border: 1px solid var(--border); border-radius: var(--radius); margin-top: 20px; overflow: hidden; }
      .gap-section-header { display: flex; align-items: center; justify-content: space-between; padding: 12px 18px; cursor: pointer; }
      .gap-section-header:hover { background: var(--bg-hover); }
      .gap-section-title { font-weight: 600; font-size: 0.88rem; }
      .gap-section-count { font-size: 0.75rem; color: var(--text-muted); }
      .gap-section-body { padding: 0 18px 14px; }
      .gap-row { display: flex; align-items: center; gap: 10px; padding: 8px 12px; background: var(--bg-secondary); border: 1px solid var(--border); border-radius: var(--radius-sm); margin-bottom: 6px; }
      .gap-row-feature { font-weight: 600; font-size: 0.82rem; flex: 1; }
      .gap-row-project { font-size: 0.75rem; color: var(--text-muted); }
      .gap-row-action { padding: 3px 8px; border-radius: 4px; border: 1px solid var(--border); background: var(--bg-tertiary); color: var(--text-secondary); font-size: 0.7rem; cursor: pointer; }
      .gap-row-action:hover { border-color: var(--accent); color: var(--accent); }

      /* Skill picker — see UIHelpers.skill_picker_css() */
      .ai-hint { font-size: 0.75rem; color: var(--text-muted); margin-top: 8px; font-style: italic; }

      /* --- Issues Tab (kanban) --- */
      .kanban { display: flex; gap: 0; flex: 1; overflow-x: auto; overflow-y: hidden; height: 100%; }
      .kb-column { flex: 1 1 0; min-width: 160px; display: flex; flex-direction: column; border-right: 1px solid var(--border-light); height: 100%; }
      .kb-column:last-child { border-right: none; }
      .kb-column.collapsed { flex: 0 0 36px; min-width: 36px; max-width: 36px; cursor: pointer; }
      .kb-column.collapsed .kb-column-body, .kb-column.collapsed .kb-quick-add { display: none; }
      .kb-column.collapsed .kb-column-header { writing-mode: vertical-lr; text-orientation: mixed; padding: 10px 4px; flex-direction: column; align-items: center; gap: 8px; flex: 1; }
      .kb-column.collapsed .kb-title-group { flex-direction: column; gap: 6px; }
      .kb-column.collapsed .kb-count { writing-mode: horizontal-tb; }
      .kb-column-header { padding: 8px 10px 6px; display: flex; align-items: center; justify-content: space-between; flex-shrink: 0; border-bottom: 2px solid var(--column-accent, var(--border-light)); background: var(--bg-secondary); }
      .kb-title-group { display: flex; align-items: center; gap: 5px; }
      .kb-dot { width: 7px; height: 7px; border-radius: 50%; background: var(--column-accent, var(--text-muted)); flex-shrink: 0; }
      .kb-title { font-size: 0.7rem; font-weight: 600; color: var(--text-secondary); text-transform: uppercase; letter-spacing: 0.04em; }
      .kb-count { font-size: 0.68rem; color: var(--text-primary); font-weight: 600; background: var(--bg-tertiary); padding: 1px 6px; border-radius: 10px; min-width: 18px; text-align: center; }
      .kb-collapse-btn { background: none; border: none; color: var(--text-muted); cursor: pointer; padding: 2px; border-radius: 4px; display: flex; align-items: center; opacity: 0; transition: opacity 0.15s; }
      .kb-column-header:hover .kb-collapse-btn { opacity: 1; }
      .kb-collapse-btn:hover { color: var(--text-primary); background: var(--bg-tertiary); }
      .kb-column-body { flex: 1; overflow-y: auto; padding: 4px; min-height: 40px; }
      .kb-column-body.drag-over { background: rgba(88,166,255,0.06); outline: 2px dashed var(--accent); outline-offset: -4px; border-radius: 4px; }
      .kb-empty { display: flex; align-items: center; justify-content: center; padding: 16px 8px; color: var(--text-muted); font-size: 0.75rem; }
      .kb-quick-add { padding: 3px 4px 4px; border-top: 1px solid var(--border-light); flex-shrink: 0; background: var(--bg-secondary); }
      .kb-quick-input { width: 100%; padding: 5px 7px; background: transparent; border: 1px dashed var(--border); border-radius: var(--radius-sm); color: var(--text-primary); font-size: 0.75rem; outline: none; font-family: inherit; transition: all var(--transition); }
      .kb-quick-input:focus { border-color: var(--accent); border-style: solid; background: var(--bg-primary); }
      .kb-quick-input::placeholder { color: var(--text-muted); }

      /* Issue cards */
      .issue-card { background: var(--bg-secondary); border: 1px solid var(--border); border-radius: var(--radius-sm); padding: 6px 8px; margin-bottom: 3px; cursor: grab; transition: all var(--transition); position: relative; border-left: 3px solid transparent; }
      .card-delete { position: absolute; top: 3px; right: 3px; background: none; border: none; color: var(--text-muted); cursor: pointer; font-size: 14px; width: 20px; height: 20px; display: flex; align-items: center; justify-content: center; border-radius: 4px; opacity: 0; transition: all var(--transition); }
      .issue-card:hover .card-delete { opacity: 0.6; }
      .card-delete:hover { opacity: 1 !important; color: var(--red); background: rgba(248,81,73,0.15); }
      .issue-card:hover { border-color: var(--border); border-left-color: var(--accent); background: var(--bg-tertiary); }
      .issue-card.dragging { opacity: 0.4; }
      .plan-badge { display: inline-block; font-size: 0.65rem; padding: 1px 6px; border-radius: 3px; margin-top: 2px; }
      .plan-badge.planning { background: rgba(88,166,255,0.15); color: var(--accent); }
      .plan-badge.review { background: rgba(210,153,34,0.15); color: #d29922; }
      .plan-badge.approved { background: rgba(63,185,80,0.15); color: #3fb950; }
      .issue-card-id { font-size: 0.62rem; color: var(--text-muted); font-weight: 500; font-family: 'SF Mono', SFMono-Regular, Consolas, monospace; margin-bottom: 1px; }
      .issue-card-title { font-size: 0.78rem; font-weight: 500; color: var(--text-primary); line-height: 1.3; margin-bottom: 4px; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
      .issue-card-meta { display: flex; align-items: center; gap: 4px; flex-wrap: wrap; }
      .priority-dot { width: 6px; height: 6px; border-radius: 50%; display: inline-block; }
      .priority-1 { background: var(--red); } .priority-2 { background: var(--orange); } .priority-3 { background: var(--yellow); } .priority-4 { background: var(--accent); } .priority-0 { background: var(--text-muted); }
      .label-tag { font-size: 0.62rem; padding: 1px 4px; border-radius: 6px; background: var(--bg-tertiary); color: var(--text-secondary); border: 1px solid var(--border); }
      .card-project { font-size: 0.6rem; padding: 1px 4px; border-radius: 6px; background: rgba(88,166,255,0.1); color: var(--accent); border: 1px solid rgba(88,166,255,0.2); }
      .card-skills { font-size: 0.58rem; color: var(--purple); background: rgba(188,140,255,0.1); padding: 1px 4px; border-radius: 6px; }
      .card-age { font-size: 0.58rem; color: var(--text-muted); opacity: 0.6; margin-left: auto; }
      .card-age.stale { color: var(--red); opacity: 0.8; }

      /* --- Activity Tab --- */
      .activity-feed { padding: 24px; max-width: 800px; }
      .activity-item { display: flex; gap: 12px; padding: 12px 14px; background: var(--bg-secondary); border: 1px solid var(--border); border-radius: var(--radius-sm); margin-bottom: 8px; transition: all var(--transition); }
      .activity-item:hover { border-color: var(--accent); }
      .activity-icon { flex-shrink: 0; width: 32px; height: 32px; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 0.9rem; }
      .activity-icon.running { background: rgba(88,166,255,0.15); color: var(--accent); animation: pulse 2s infinite; }
      .activity-icon.done { background: rgba(63,185,80,0.15); color: var(--green); }
      .activity-icon.failed { background: rgba(248,81,73,0.15); color: var(--red); }
      .activity-icon.todo { background: rgba(210,153,34,0.15); color: var(--yellow); }
      .activity-body { flex: 1; min-width: 0; }
      .activity-title { font-size: 0.85rem; font-weight: 500; margin-bottom: 2px; }
      .activity-title a { color: var(--text-primary); text-decoration: none; }
      .activity-title a:hover { color: var(--accent); }
      .activity-meta { font-size: 0.72rem; color: var(--text-muted); display: flex; gap: 10px; flex-wrap: wrap; }
      .activity-empty { text-align: center; color: var(--text-muted); padding: 40px; font-size: 0.85rem; }

      /* --- Knowledge Base Tab --- */
      .kb-browser { padding: 24px; max-width: 900px; }
      .kb-toolbar { display: flex; align-items: center; gap: 12px; margin-bottom: 16px; flex-wrap: wrap; }
      .kb-search-bar { display: flex; gap: 6px; flex: 1; min-width: 200px; }
      .kb-search-bar input { flex: 1; padding: 6px 10px; background: var(--bg-secondary); border: 1px solid var(--border); border-radius: var(--radius-sm); color: var(--text-primary); font-size: 0.82rem; }
      .kb-search-bar input:focus { outline: none; border-color: var(--accent); }
      .kb-notes-list { display: grid; gap: 8px; }
      .kb-note-card { padding: 12px 14px; background: var(--bg-secondary); border: 1px solid var(--border); border-radius: var(--radius-sm); cursor: pointer; transition: all var(--transition); }
      .kb-note-card:hover { border-color: var(--accent); background: var(--bg-tertiary, var(--bg-secondary)); }
      .kb-note-title { font-size: 0.88rem; font-weight: 500; color: var(--text-primary); margin-bottom: 2px; }
      .kb-note-folder { font-size: 0.72rem; color: var(--text-muted); margin-bottom: 4px; }
      .kb-note-snippet { font-size: 0.78rem; color: var(--text-secondary); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
      .kb-note-viewer { background: var(--bg-primary); }
      .kb-note-header { display: flex; align-items: center; gap: 12px; margin-bottom: 12px; padding-bottom: 8px; border-bottom: 1px solid var(--border); }
      .kb-note-path { flex: 1; font-size: 0.75rem; color: var(--text-muted); overflow: hidden; text-overflow: ellipsis; }
      .kb-frontmatter { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 12px; }
      .kb-fm-tag { display: inline-block; padding: 2px 8px; background: var(--bg-secondary); border: 1px solid var(--border); border-radius: 12px; font-size: 0.72rem; color: var(--text-secondary); }
      .kb-note-content { padding: 16px; background: var(--bg-secondary); border: 1px solid var(--border); border-radius: var(--radius-sm); overflow: auto; max-height: 60vh; font-size: 0.85rem; line-height: 1.55; color: var(--text-secondary); }

      /* KB Sync indicator on issue cards */
      .kb-sync-dot { display: inline-block; width: 7px; height: 7px; border-radius: 50%; margin-left: 2px; vertical-align: middle; }
      .kb-sync-dot.synced { background: var(--green); title: 'Synced to KB'; }
      .kb-sync-dot.not-synced { background: var(--text-muted); opacity: 0.4; }
      .kb-sync-time { font-size: 0.6rem; color: var(--text-muted); margin-left: 4px; }

      /* Note editor */
      .kb-editor { padding: 24px; max-width: 900px; }
      .kb-editor-header { display: flex; align-items: center; gap: 12px; margin-bottom: 16px; }
      .kb-editor-header h3 { margin: 0; font-size: 0.95rem; flex: 1; }
      .kb-editor-field { margin-bottom: 12px; }
      .kb-editor-field label { display: block; font-size: 0.78rem; color: var(--text-secondary); margin-bottom: 4px; font-weight: 500; }
      .kb-editor-field input, .kb-editor-field textarea { width: 100%; padding: 8px 10px; background: var(--bg-secondary); border: 1px solid var(--border); border-radius: var(--radius-sm); color: var(--text-primary); font-size: 0.85rem; font-family: inherit; box-sizing: border-box; }
      .kb-editor-field input:focus, .kb-editor-field textarea:focus { outline: none; border-color: var(--accent); }
      .kb-editor-field textarea { min-height: 300px; resize: vertical; font-family: 'SF Mono', SFMono-Regular, Consolas, monospace; font-size: 0.82rem; line-height: 1.5; }
      .kb-editor-actions { display: flex; gap: 8px; margin-top: 12px; }

      /* Version history */
      .kb-version-list { margin-top: 12px; }
      .kb-version-item { display: flex; align-items: center; gap: 12px; padding: 8px 12px; background: var(--bg-secondary); border: 1px solid var(--border); border-radius: var(--radius-sm); margin-bottom: 6px; font-size: 0.8rem; cursor: pointer; transition: all var(--transition); }
      .kb-version-item:hover { border-color: var(--accent); background: var(--bg-tertiary); }
      .kb-version-timestamp { font-family: 'SF Mono', SFMono-Regular, Consolas, monospace; color: var(--text-secondary); min-width: 140px; }
      .kb-version-size { color: var(--text-muted); font-size: 0.72rem; min-width: 60px; }
      .kb-version-actions { margin-left: auto; display: flex; gap: 6px; }
      .kb-diff-view { margin-top: 12px; padding: 16px; background: var(--bg-secondary); border: 1px solid var(--border); border-radius: var(--radius-sm); overflow: auto; max-height: 50vh; }
      .kb-diff-view .diff-add { color: var(--green); background: rgba(63,185,80,0.1); }
      .kb-diff-view .diff-del { color: var(--red); background: rgba(248,81,73,0.1); }
      .kb-diff-view pre { margin: 0; font-size: 0.8rem; line-height: 1.5; white-space: pre-wrap; }

      /* Auto-dispatch controls (in Issues tab actions) */
      .auto-dispatch-bar { display: flex; align-items: center; gap: 8px; font-size: 0.75rem; color: var(--text-muted); }
      .auto-dispatch-bar label { display: flex; align-items: center; gap: 4px; cursor: pointer; }
      .auto-dispatch-bar input[type="checkbox"] { accent-color: var(--accent); width: 14px; height: 14px; cursor: pointer; }
      .auto-dispatch-bar select { background: var(--bg-primary); color: var(--text-primary); border: 1px solid var(--border); border-radius: var(--radius-sm); padding: 1px 4px; font-size: 0.75rem; cursor: pointer; }
      """
  end

  defp javascript do
    alias SymphonyElixir.Server.UIHelpers

    UIHelpers.esc_js() <>
      UIHelpers.markdown_js() <>
      UIHelpers.toast_js() <>
      UIHelpers.color_maps_js() <>
      UIHelpers.time_utils_js() <>
      UIHelpers.dropdown_js() <>
      UIHelpers.pipeline_indicator_js() <>
      UIHelpers.create_issue_modal_js("hi") <>
      globals_js() <>
      UIHelpers.load_skills_js() <>
      UIHelpers.skill_picker_js() <>
      UIHelpers.kanban_drag_drop_js() <>
      init_js() <>
      data_loading_js() <>
      sidebar_js() <>
      tabs_js() <>
      spec_sheet_js() <>
      kanban_js() <>
      activity_js() <>
      kb_browser_js() <>
      kb_editor_js() <>
      kb_versions_js() <>
      modal_product_js() <>
      modal_feature_js() <>
      modal_agent_js() <>
      modal_issue_js() <>
      modal_project_js() <>
      scan_import_js() <>
      keyboard_shortcuts_js() <>
      auto_refresh_js()
  end

  defp globals_js do
    ~S"""
      const API = '/board/api';
      let allProducts = [];
      let allProjects = [];
      let currentProd = null;
      let selectedProductId = null;
      let activeTab = 'spec';
      let boardData = null;
      let activityData = [];
      let collapsedCategories = {};
      let activeFilter = null;
      let detailHistoryExpanded = {};
      let gapSectionCollapsed = false;
      let draggedCard = null;
      let _apiLock = false;

      // ========== SHARED MODAL HELPERS ==========
      function openModal(id) { document.getElementById(id).style.display = 'flex'; }
      function closeModal(id) { document.getElementById(id).style.display = 'none'; }

      // Kanban state
      const TERMINAL_STATES = ['Done','Archived','Cancelled'];
      let collapsedColumns = JSON.parse(localStorage.getItem('symphony_hub_columns') || 'null');
      if (!collapsedColumns) { collapsedColumns = {}; TERMINAL_STATES.forEach(function(s) { collapsedColumns[s] = true; }); }

      // Spec sheet constants
      const STATUS_ORDER = ['missing','planned','in_progress','done','n_a'];
      const STATUS_LABELS = { done:'Done', partial:'Partial', in_progress:'In Progress', planned:'Planned', missing:'Missing', n_a:'N/A' };
      const STATUS_ICONS = { done:'\u2705', partial:'\uD83D\uDFE1', in_progress:'\uD83D\uDD35', planned:'\uD83D\uDFE0', missing:'\uD83D\uDD34', n_a:'\u2B1C' };
      const BADGE_CLASSES = { 'backlog':'badge-backlog','todo':'badge-todo','in progress':'badge-in-progress','review':'badge-review','done':'badge-done','cancelled':'badge-cancelled','archived':'badge-archived' };


      // Kanban config for shared drag-drop
      window._kanbanOpts = {
        cardSelector: '.issue-card',
        bodySelector: '.kb-column-body',
        getQuickAddExtras: function() {
          var extras = {};
          if (currentProd && currentProd.project_ids && currentProd.project_ids.length > 0) extras.project_id = currentProd.project_ids[0];
          if (currentProd && selectedProductId !== '__all__') extras.product_id = selectedProductId;
          return extras;
        }
      };
      async function kanbanAfterMutation() { await refreshAfterMutation(); }
    """
  end

  defp init_js do
    ~S"""
      // ========== INIT ==========

      async function init() {
        restoreState();
        await Promise.all([loadProducts(), loadProjects(), loadAllSkills(), loadBoardSnapshot()]);
        renderSidebar();
        renderTabBar();
        if (selectedProductId && selectedProductId !== '__all__') {
          await selectProduct(selectedProductId);
        } else {
          selectAllIssues();
        }
      }

      function restoreState() {
        selectedProductId = localStorage.getItem('symphony_hub_product') || null;
        activeTab = localStorage.getItem('symphony_hub_tab') || 'spec';
        // URL params override localStorage
        var params = new URLSearchParams(window.location.search);
        if (params.get('product')) selectedProductId = params.get('product');
        if (params.get('tab')) activeTab = params.get('tab');
      }

      function saveState() {
        localStorage.setItem('symphony_hub_product', selectedProductId || '');
        localStorage.setItem('symphony_hub_tab', activeTab);
        var url = '/board';
        if (selectedProductId) url += '?product=' + selectedProductId + '&tab=' + activeTab;
        history.replaceState(null, '', url);
      }

    """
  end

  defp data_loading_js do
    ~S"""
      // ========== DATA LOADING ==========

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

      // loadAllSkills() provided by UIHelpers.load_skills_js()

      async function loadBoardSnapshot() {
        try {
          var res = await fetch(API + '/snapshot');
          boardData = await res.json();
        } catch (e) { boardData = null; }
      }


      async function loadActivity() {
        if (!selectedProductId || selectedProductId === '__all__') { activityData = []; return; }
        try {
          var res = await fetch(API + '/products/' + selectedProductId + '/activity');
          var data = await res.json();
          activityData = data.issues || [];
        } catch (e) { activityData = []; }
      }

    """
  end

  defp sidebar_js do
    ~S"""
      // ========== SIDEBAR ==========

      function countIssuesForProduct(prod) {
        if (!boardData || !boardData.columns) return 0;
        var count = 0;
        var pids = prod.project_ids || [];
        boardData.columns.forEach(function(col) {
          col.issues.forEach(function(issue) {
            if (issue.product_id === prod.id) { count++; return; }
            if ((issue.labels || []).some(function(l) { return l === 'product:' + prod.id; })) { count++; return; }
            if (issue.project_id && pids.indexOf(issue.project_id) >= 0) { count++; return; }
          });
        });
        return count;
      }

      function renderSidebar() {
        var container = document.getElementById('sidebar-products');

        var html = '';
        allProducts.forEach(function(p) {
          var isActive = selectedProductId === p.id;
          var issueCount = countIssuesForProduct(p);
          var pids = p.project_ids || [];
          html += '<div class="sidebar-item' + (isActive ? ' active' : '') + '" data-product-id="' + p.id + '" onclick="handleProductClick(\'' + p.id + '\')" title="' + esc(p.name) + '" ondragover="onProductDragOver(event)" ondragleave="onProductDragLeave(event)" ondrop="onProductDrop(event)">' +
            '<span class="sidebar-item-name">' + esc(p.name) + '</span>' +
            '<span class="sidebar-badge">' + issueCount + '</span>' +
          '</div>';
          // Nested projects under this product
          if (pids.length > 0) {
            html += '<div class="sidebar-sub-items' + (isActive ? '' : ' collapsed') + '">';
            pids.forEach(function(pid) {
              var proj = allProjects.find(function(x) { return x.id === pid; });
              if (!proj) return;
              html += renderSidebarProjectItem(proj, p.id);
            });
            html += '</div>';
          }
        });
        if (allProducts.length === 0) {
          html = '<div style="padding:8px;color:var(--text-muted);font-size:0.78rem">No products yet. <button class="btn btn-ghost btn-sm" onclick="openNewProductModal()" style="margin-top:4px">Create one</button></div>';
        }
        container.innerHTML = html;
        // Highlight All Issues item if active
        var allItem = document.getElementById('all-issues-item');
        if (allItem) allItem.classList.toggle('active', selectedProductId === '__all__');
        // Update All Issues badge
        updateAllIssuesBadge();
        // Render all projects section
        renderAllProjectsList();
      }

      function renderSidebarProjectItem(proj, parentProductId) {
        var cloneBtn = (proj.repo_url && !proj.path) ? '<button class="project-action-btn" onclick="event.stopPropagation(); cloneProject(\'' + proj.id + '\')" title="Clone">\u2B07</button>' : '';
        var unlinkBtn = parentProductId ? '<button class="project-action-btn" onclick="event.stopPropagation(); unlinkProjectFromProduct(\'' + proj.id + '\', \'' + parentProductId + '\')" title="Unlink from product">\u21C6</button>' : '';
        var draggable = parentProductId ? '' : ' draggable="true" ondragstart="onProjectDragStart(event)" ondragend="onProjectDragEnd(event)"';
        return '<div class="sidebar-project" data-project-id="' + proj.id + '" title="' + esc(proj.path || proj.description || proj.name) + '"' + draggable + '>' +
          '<span class="project-dot"></span>' +
          '<span class="project-name">' + esc(proj.name) + '</span>' +
          '<span class="project-actions">' +
            unlinkBtn +
            cloneBtn +
            '<button class="project-action-btn" onclick="event.stopPropagation(); editProjectInline(\'' + proj.id + '\')" title="Edit">\u270E</button>' +
            '<button class="project-action-btn" onclick="event.stopPropagation(); deleteProjectInline(\'' + proj.id + '\')" title="Delete">\u2715</button>' +
          '</span>' +
        '</div>';
      }

      var projectsFilterUnassigned = false;

      function toggleProjectsFilter() {
        projectsFilterUnassigned = !projectsFilterUnassigned;
        var btn = document.getElementById('projects-filter-btn');
        if (btn) btn.textContent = projectsFilterUnassigned ? 'Unassigned' : 'All';
        renderAllProjectsList();
      }

      function renderAllProjectsList() {
        var section = document.getElementById('all-projects-section');
        var container = document.getElementById('sidebar-all-projects');
        if (!section || !container) return;
        if (allProjects.length === 0) { section.style.display = 'none'; return; }
        section.style.display = '';
        var list = allProjects;
        if (projectsFilterUnassigned) {
          var assignedIds = new Set();
          allProducts.forEach(function(p) { (p.project_ids || []).forEach(function(pid) { assignedIds.add(pid); }); });
          list = allProjects.filter(function(p) { return !assignedIds.has(p.id); });
        }
        if (list.length === 0) { container.innerHTML = '<div style="padding:6px 10px;color:var(--text-muted);font-size:0.73rem">All projects assigned</div>'; return; }
        container.innerHTML = list.map(function(p) { return renderSidebarProjectItem(p, null); }).join('');
      }

      // ========== SIDEBAR DRAG & DROP (Project -> Product) ==========
      var draggedProjectId = null;

      function onProjectDragStart(e) {
        var el = e.target.closest('.sidebar-project');
        if (!el) return;
        draggedProjectId = el.dataset.projectId;
        el.classList.add('dragging');
        e.dataTransfer.effectAllowed = 'link';
        e.dataTransfer.setData('text/plain', draggedProjectId);
      }

      function onProjectDragEnd(e) {
        draggedProjectId = null;
        var el = e.target.closest('.sidebar-project');
        if (el) el.classList.remove('dragging');
        document.querySelectorAll('.sidebar-item.drag-over').forEach(function(el) { el.classList.remove('drag-over'); });
      }

      function onProductDragOver(e) {
        if (!draggedProjectId) return;
        e.preventDefault();
        e.dataTransfer.dropEffect = 'link';
        e.currentTarget.classList.add('drag-over');
      }

      function onProductDragLeave(e) {
        e.currentTarget.classList.remove('drag-over');
      }

      async function onProductDrop(e) {
        e.preventDefault();
        e.currentTarget.classList.remove('drag-over');
        var projectId = e.dataTransfer.getData('text/plain');
        var productId = e.currentTarget.dataset.productId;
        if (!projectId || !productId) return;
        // Find the product and add the project if not already there
        var prod = allProducts.find(function(p) { return p.id === productId; });
        if (!prod) return;
        var pids = prod.project_ids || [];
        if (pids.indexOf(projectId) >= 0) { showToast('Project already in this product'); return; }
        pids.push(projectId);
        try {
          await fetch(API + '/products/' + productId, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ project_ids: pids }) });
          await loadProducts();
          renderSidebar();
          if (selectedProductId === productId) await selectProduct(productId);
          showToast('Project assigned to product', { type: 'success' });
        } catch (err) { showToast('Failed to assign project', { type: 'error' }); }
      }

      async function unlinkProjectFromProduct(projectId, productId) {
        var prod = allProducts.find(function(p) { return p.id === productId; });
        if (!prod) return;
        var pids = (prod.project_ids || []).filter(function(pid) { return pid !== projectId; });
        try {
          await fetch(API + '/products/' + productId, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ project_ids: pids }) });
          await loadProducts();
          renderSidebar();
          if (selectedProductId === productId) await selectProduct(productId);
          showToast('Project unlinked', { type: 'success' });
        } catch (err) { showToast('Failed to unlink project', { type: 'error' }); }
      }

      function handleProductClick(prodId) {
        // Click active product to deselect
        if (selectedProductId === prodId) {
          selectedProductId = null; currentProd = null; activeTab = 'spec';
          saveState(); renderSidebar(); renderTabBar(); showWelcome();
        } else {
          selectProduct(prodId);
        }
      }

      async function refreshAfterMutation() {
        await loadBoardSnapshot();
        renderSidebar();
        if (activeTab === 'issues') renderKanban();
      }

      function updateAllIssuesBadge() {
        if (boardData && boardData.columns) {
          var total = 0;
          boardData.columns.forEach(function(c) { total += c.issues.length; });
          document.getElementById('all-issues-badge').textContent = total;
        }
      }

      async function selectProduct(prodId) {
        selectedProductId = prodId;
        saveState();

        if (!prodId) { showWelcome(); renderSidebar(); return; }

        try {
          var res = await fetch(API + '/products/' + prodId);
          if (!res.ok) { showToast('Product not found', { type: 'error' }); selectedProductId = null; currentProd = null; saveState(); showWelcome(); renderSidebar(); return; }
          currentProd = await res.json();
        } catch (e) { showToast('Failed to load product', { type: 'error' }); return; }
        activeFilter = null;
        loadCollapseState();
        renderSidebar();
        renderTabBar();
        loadTabContent();
      }

      function selectAllIssues() {
        selectedProductId = '__all__';
        currentProd = null;
        activeTab = 'issues';
        saveState();
        renderSidebar();
        // Highlight All Issues item
        document.querySelectorAll('.sidebar-item').forEach(function(el) { el.classList.remove('active'); });
        var allItem = document.getElementById('all-issues-item');
        if (allItem) allItem.classList.add('active');
        renderTabBar();
        loadTabContent();
      }

      function showWelcome() {
        document.getElementById('tab-content').innerHTML =
          '<div class="empty-state"><div class="empty-icon"><svg viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/></svg></div>' +
          '<h2>Welcome to Symphony</h2>' +
          '<p>' + (allProducts.length > 0 ? 'Select a product from the sidebar to get started.' : 'Create a product to group projects and track features.') + '</p>' +
          '<button class="btn btn-primary" onclick="openNewProductModal()">Create Product</button></div>';
      }

    """
  end

  defp tabs_js do
    ~S"""
      // ========== TABS ==========

      function switchTab(tab) {
        activeTab = tab;
        saveState();
        renderTabBar();
        loadTabContent();
      }

      function renderTabBar() {
        var noProduct = !currentProd || selectedProductId === '__all__';
        document.querySelectorAll('.tab-item').forEach(function(el) {
          el.classList.toggle('active', el.dataset.tab === activeTab);
          // Disable spec & activity when no product selected (kb works for all)
          if (el.dataset.tab === 'spec' || el.dataset.tab === 'activity') {
            el.classList.toggle('tab-disabled', noProduct);
          }
        });
        // Update issues badge from boardData
        updateIssuesBadge();
      }

      async function loadTabContent() {
        var content = document.getElementById('tab-content');
        switch (activeTab) {
          case 'spec':
            if (!currentProd) { showWelcome(); return; }
            content.innerHTML = '<div class="spec-sheet"><div id="product-header"></div><div id="category-rings"></div><div id="category-sections"></div><div id="inline-gap-section"></div></div>';
            renderSpecSheet();
            break;
          case 'issues':
            if (!boardData) {
              content.innerHTML = '<div class="tab-loading"><span class="spinner"></span> Loading issues...</div>';
              await loadBoardSnapshot();
            }
            content.innerHTML = '<div class="kanban-wrapper">' +
              (currentProd && selectedProductId !== '__all__' ? '<div class="scope-indicator">Showing issues for <strong>' + esc(currentProd.name) + '</strong> <button class="btn btn-ghost btn-sm" onclick="selectAllIssues()" style="margin-left:8px">Show all</button></div>' : '') +
              '<div class="kanban" id="kanban-board" style="height:100%"></div></div>';
            renderKanban();
            break;
          case 'activity':
            if (!currentProd || selectedProductId === '__all__') {
              content.innerHTML = '<div class="empty-state" style="height:40vh"><h2>Select a product</h2><p>Activity shows recent agent work for a specific product.</p></div>';
              break;
            }
            content.innerHTML = '<div class="activity-feed" id="activity-feed"><div class="tab-loading"><span class="spinner"></span> Loading activity...</div></div>';
            await loadActivity();
            renderActivity();
            break;
          case 'kb':
            content.innerHTML = '<div class="kb-browser" id="kb-browser">' +
              '<div class="kb-toolbar">' +
                '<div class="kb-search-bar">' +
                  '<input type="text" id="kb-search-input" placeholder="Search knowledge base..." onkeydown="if(event.key===\'Enter\')searchKB()">' +
                  '<button class="btn btn-ghost btn-sm" onclick="searchKB()">Search</button>' +
                '</div>' +
                '<div class="kb-scope">' +
                  (currentProd && selectedProductId !== '__all__' ? '<span class="scope-indicator" style="font-size:0.82rem">Scoped to <strong>' + esc(currentProd.name) + '</strong></span>' : '<span style="font-size:0.82rem;color:var(--text-muted)">All products</span>') +
                '</div>' +
                '<div style="display:flex;gap:6px;margin-left:auto">' +
                  '<button class="btn btn-ghost btn-sm" onclick="openKBEditor()">+ New Note</button>' +
                  (currentProd && selectedProductId !== '__all__' ? '<button class="btn btn-primary btn-sm" onclick="batchSendToKB()">Send All to KB</button>' : '') +
                '</div>' +
              '</div>' +
              '<div id="kb-results" class="kb-results"></div>' +
              '<div id="kb-note-viewer" class="kb-note-viewer" style="display:none"></div>' +
              '<div id="kb-editor" class="kb-editor" style="display:none"></div>' +
            '</div>';
            loadKBNotes();
            break;
        }
        renderTabActions();
      }

      function renderTabActions() {
        var actions = document.getElementById('tab-actions');
        if (activeTab === 'issues') {
          actions.innerHTML = '<div class="auto-dispatch-bar">' +
            '<label><input type="checkbox" id="auto-toggle" onchange="handleAutoToggle()"><span>Auto-dispatch</span></label>' +
            '<label>Max <select id="max-todo-select" onchange="handleMaxTodoChange()">' +
              '<option value="1">1</option><option value="2">2</option><option value="3" selected>3</option>' +
            '</select></label>' +
            '<label><input type="checkbox" id="segregate-toggle" onchange="handleSegregateToggle()"><span>Per-project</span></label>' +
            '</div>';
          loadAutoSettings();
        } else {
          actions.innerHTML = '';
        }
      }

    """
  end

  defp spec_sheet_js do
    ~S"""
      // ========== SPEC SHEET TAB ==========

      function getProjectById(id) {
        return allProjects.find(function(p) { return p.id === id; }) || { id: id, name: id };
      }

      function computeOverallStatus(statuses, projectIds) {
        var pids = projectIds || Object.keys(statuses || {});
        var applicable = pids.filter(function(pid) { return (statuses[pid] || 'missing') !== 'n_a'; });
        if (applicable.length === 0) return 'n_a';
        var vals = applicable.map(function(pid) { return statuses[pid] || 'missing'; });
        if (vals.every(function(v) { return v === 'done'; })) return 'done';
        if (vals.some(function(v) { return v === 'in_progress'; })) return 'in_progress';
        if (vals.some(function(v) { return v === 'done'; })) return 'partial';
        if (vals.some(function(v) { return v === 'planned'; })) return 'planned';
        return 'missing';
      }

      function getApplicableProjects(feature, projectIds) {
        var pids = projectIds || Object.keys(feature.statuses || {});
        return pids.filter(function(pid) { return (feature.statuses[pid] || 'missing') !== 'n_a'; });
      }

      function scoreColor(pct) {
        if (pct === 0) return 'var(--text-muted)';
        if (pct >= 80) return 'var(--green)';
        if (pct >= 50) return 'var(--yellow)';
        return 'var(--red)';
      }

      function computeCategoryStats(features) {
        var total = 0, done = 0;
        features.forEach(function(f) {
          var app = getApplicableProjects(f);
          app.forEach(function(pid) { total++; if (f.statuses[pid] === 'done') done++; });
        });
        return { total: total, done: done, pct: total > 0 ? Math.round(done / total * 100) : 100 };
      }

      function getCategories(features) {
        var cats = {};
        features.forEach(function(f) { var cat = f.category || 'Uncategorized'; if (!cats[cat]) cats[cat] = []; cats[cat].push(f); });
        var keys = Object.keys(cats).sort(function(a, b) {
          if (a === 'Uncategorized') return 1; if (b === 'Uncategorized') return -1; return a.localeCompare(b);
        });
        return keys.map(function(k) { return { name: k, features: cats[k] }; });
      }

      function renderDonutSVG(pct, color) {
        var r = 22, c = 28, stroke = 5, circ = 2 * Math.PI * r;
        var offset = circ - (pct / 100) * circ;
        return '<svg class="ring-svg" viewBox="0 0 56 56"><circle cx="'+c+'" cy="'+c+'" r="'+r+'" fill="none" stroke="var(--bg-tertiary)" stroke-width="'+stroke+'"/><circle cx="'+c+'" cy="'+c+'" r="'+r+'" fill="none" stroke="'+color+'" stroke-width="'+stroke+'" stroke-dasharray="'+circ.toFixed(1)+'" stroke-dashoffset="'+offset.toFixed(1)+'" stroke-linecap="round" transform="rotate(-90 '+c+' '+c+')" style="transition:stroke-dashoffset 0.4s"/><text x="'+c+'" y="'+c+'" text-anchor="middle" dominant-baseline="central" fill="'+color+'" font-size="13" font-weight="700">'+pct+'%</text></svg>';
      }

      function renderSpecSheet() {
        if (!currentProd) return;
        var prod = currentProd, pids = prod.project_ids || [], features = prod.features || [];
        renderProductHeader(prod, pids, features);
        renderCategoryRings(prod, pids, features);
        renderCategorySections(prod, pids, features);
        renderInlineGapSection(prod, pids, features);
        updateCategoryDatalist(features);
      }

      function renderProductHeader(prod, pids, features) {
        var el = document.getElementById('product-header');
        if (!el) return;
        var total = 0, done = 0;
        features.forEach(function(f) {
          var fps = Object.keys(f.statuses || {});
          fps.forEach(function(pid) { var s = f.statuses[pid]; if (s !== 'n_a') { total++; if (s === 'done') done++; } });
        });
        var pct = total > 0 ? Math.round(done / total * 100) : 100;
        var html = '<div class="product-header-card"><div class="product-header-top"><h2>' + esc(prod.name) + '</h2>' +
          '<div class="product-actions">' +
            '<div class="action-group">' +
              '<button class="btn btn-primary btn-sm" onclick="openProductTaskModal()">+ Create Task</button>' +
              '<button class="btn btn-ghost btn-sm" onclick="openAddFeatureModal()">+ Feature</button>' +
            '</div>' +
            '<div class="action-group">' +
              '<div class="dropdown" id="agent-dropdown">' +
                '<button class="btn btn-accent-soft btn-sm" onclick="toggleDropdown(\'agent-dropdown\')">Agent Actions \u25BE</button>' +
                '<div class="dropdown-menu">' +
                  '<button class="dropdown-item" onclick="analyzeExistingFeatures(); closeDropdowns()" id="analyze-existing-btn">Discover Existing Features</button>' +
                  '<button class="dropdown-item" onclick="analyzeGaps(); closeDropdowns()" id="analyze-gaps-btn">Analyze Gaps</button>' +
                  '<button class="dropdown-item" onclick="openCodeReviewModal(); closeDropdowns()">Code Review</button>' +
                  '<button class="dropdown-item" onclick="openGenerateModal(); closeDropdowns()">Generate Features</button>' +
                  '<button class="dropdown-item" onclick="openGenDefModal(); closeDropdowns()">Generate Definition</button>' +
                '</div>' +
              '</div>' +
            '</div>' +
            '<div class="action-group">' +
              '<button class="btn btn-ghost btn-sm" onclick="openEditProductModal()">Edit</button>' +
              '<button class="btn btn-danger btn-sm" onclick="deleteCurrentProduct()">Delete</button>' +
            '</div>' +
          '</div></div>';
        if (prod.description) html += '<div class="product-desc">' + esc(prod.description) + '</div>';
        if (pids.length > 0) {
          html += '<div class="project-tags">';
          pids.forEach(function(pid) { var p = getProjectById(pid); html += '<span class="project-tag"><span class="project-tag-dot"></span>' + esc(p.name) + '</span>'; });
          html += '</div>';
        }
        html += '<div class="overall-bar"><span class="overall-label">Overall Completeness</span><div class="overall-track"><div class="overall-fill" style="width:'+pct+'%;background:'+scoreColor(pct)+'"></div></div><span class="overall-value" style="color:'+scoreColor(pct)+'">'+pct+'%</span></div></div>';
        el.innerHTML = html;
      }

      function renderCategoryRings(prod, pids, features) {
        var el = document.getElementById('category-rings'); if (!el) return;
        var categories = getCategories(features);
        if (categories.length <= 1 && features.length < 5) { el.innerHTML = ''; return; }
        var html = '<div class="rings-row">';
        categories.forEach(function(cat) {
          var stats = computeCategoryStats(cat.features); var color = scoreColor(stats.pct);
          var isActive = activeFilter === cat.name;
          html += '<div class="ring-card' + (isActive ? ' active' : '') + '" onclick="filterCategory(\'' + esc(cat.name).replace(/'/g, "\\'") + '\')">' + renderDonutSVG(stats.pct, color) + '<div class="ring-label" title="' + esc(cat.name) + '">' + esc(cat.name) + '</div><div class="ring-count">' + cat.features.length + ' feature' + (cat.features.length !== 1 ? 's' : '') + '</div></div>';
        });
        html += '</div>'; el.innerHTML = html;
      }

      function renderCategorySections(prod, pids, features) {
        var el = document.getElementById('category-sections'); if (!el) return;
        var categories = getCategories(features); var html = '';
        categories.forEach(function(cat) {
          if (activeFilter && activeFilter !== cat.name) return;
          var stats = computeCategoryStats(cat.features);
          var collapsed = collapsedCategories[cat.name]; var catId = 'cat-' + cat.name.replace(/\W/g, '_');
          var doneCount = cat.features.filter(function(f) { return computeOverallStatus(f.statuses) === 'done'; }).length;
          html += '<div class="category-section"><div class="category-header" onclick="toggleCategory(\'' + esc(cat.name).replace(/'/g, "\\'") + '\')">' +
            '<span class="category-chevron' + (collapsed ? ' collapsed' : '') + '">\u25BC</span>' +
            '<span class="category-title">' + esc(cat.name) + '</span>' +
            '<span class="category-stats">' + doneCount + '/' + cat.features.length + ' done \u00b7 ' + stats.pct + '%</span></div>' +
            '<div class="category-body' + (collapsed ? ' collapsed' : '') + '" id="' + catId + '">';
          cat.features.forEach(function(f) { html += renderFeatureCard(f, pids); });
          html += '<button class="add-feature-btn" onclick="openAddFeatureModal(\'' + esc(cat.name).replace(/'/g, "\\'") + '\')">+ Add Feature</button></div></div>';
        });
        if (features.length === 0) html += '<div style="text-align:center;padding:40px;color:var(--text-muted)"><p>No features defined yet.</p><button class="btn btn-primary" onclick="openAddFeatureModal()">Add Feature</button></div>';
        el.innerHTML = html;
      }

      function renderInlineGapSection(prod, pids, features) {
        var el = document.getElementById('inline-gap-section'); if (!el) return;
        var gaps = [];
        features.forEach(function(f) {
          var fps = Object.keys(f.statuses || {});
          fps.forEach(function(pid) {
            var s = f.statuses[pid];
            if (s === 'missing' || s === 'planned') {
              gaps.push({ feature_id: f.id, feature_name: f.name, project_id: pid, project_name: getProjectById(pid).name, status: s, category: f.category || 'Uncategorized',
                blocked: (f.depends_on || []).some(function(depId) { var depF = features.find(function(x) { return x.id === depId; }); return depF && computeOverallStatus(depF.statuses) !== 'done'; })
              });
            }
          });
        });
        if (gaps.length === 0) { el.innerHTML = ''; return; }
        var html = '<div class="gap-section"><div class="gap-section-header" onclick="toggleGapSection()"><span class="gap-section-title">\u26A0 Gap Analysis (' + gaps.length + ' items)</span><span class="gap-section-count">' + gaps.filter(function(g) { return g.status === 'missing'; }).length + ' missing \u00b7 ' + gaps.filter(function(g) { return g.status === 'planned'; }).length + ' planned</span></div>';
        if (!gapSectionCollapsed) {
          html += '<div class="gap-section-body">';
          gaps.forEach(function(g) {
            html += '<div class="gap-row"><span class="gap-row-feature">' + STATUS_ICONS[g.status] + ' ' + esc(g.feature_name) + (g.blocked ? ' <span class="dep-blocked">\u26D4</span>' : '') + '</span><span class="gap-row-project">' + esc(g.project_name) + '</span>' +
              '<button class="gap-row-action" onclick="quickSetStatus(\'' + g.feature_id + '\',\'' + g.project_id + '\',\'in_progress\')">\u25B6 Start</button>' +
              '<button class="gap-row-action" onclick="quickSetStatus(\'' + g.feature_id + '\',\'' + g.project_id + '\',\'done\')">\u2705 Done</button>' +
              '<button class="gap-row-action" onclick="quickSetStatus(\'' + g.feature_id + '\',\'' + g.project_id + '\',\'n_a\')">\u2B1C N/A</button></div>';
          });
          html += '</div>';
        }
        html += '</div>'; el.innerHTML = html;
      }

      function toggleGapSection() { gapSectionCollapsed = !gapSectionCollapsed; renderSpecSheet(); }

      async function quickSetStatus(featureId, projectId, status) {
        await fetch(API + '/products/' + currentProd.id + '/features/' + featureId + '/status', { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ project_id: projectId, status: status, source: 'gap_action' }) });
        var res = await fetch(API + '/products/' + currentProd.id); currentProd = await res.json(); renderSpecSheet();
      }

      function renderFeatureCard(f, pids) {
        var overall = computeOverallStatus(f.statuses);
        var applicable = getApplicableProjects(f);
        var missingCount = applicable.filter(function(pid) { return (f.statuses[pid] || 'missing') === 'missing'; }).length;
        var html = '<div class="feature-card"><div class="feature-card-top"><span class="feature-status-badge badge-' + overall + '">' + STATUS_ICONS[overall] + ' ' + STATUS_LABELS[overall] + '</span><div class="feature-info"><div class="feature-name">' + esc(f.name) + '</div>' +
          (f.description ? '<div class="feature-desc">' + esc(f.description) + '</div>' : '') + '<div class="feature-meta">';
        applicable.forEach(function(pid) { var p = getProjectById(pid); var pStatus = f.statuses[pid] || 'missing'; html += '<span class="feature-project-tag" title="' + STATUS_LABELS[pStatus] + '">' + STATUS_ICONS[pStatus] + ' ' + esc(p.name) + '</span>'; });
        if (missingCount > 0 && overall !== 'missing') html += '<span class="gap-warning">\u26A0 ' + missingCount + ' gap' + (missingCount > 1 ? 's' : '') + '</span>';
        html += '</div>';
        var deps = (f.depends_on || []).filter(function(depId) { return currentProd.features.some(function(x) { return x.id === depId; }); });
        if (deps.length > 0) {
          html += '<div class="feature-deps"><span class="feature-deps-label">Depends on:</span>';
          deps.forEach(function(depId) {
            var depF = currentProd.features.find(function(x) { return x.id === depId; }); var depStatus = computeOverallStatus(depF.statuses);
            html += '<span class="dep-tag" onclick="openFeatureDetail(\'' + depId + '\')" title="' + STATUS_LABELS[depStatus] + '">' + STATUS_ICONS[depStatus] + ' ' + esc(depF.name) + '</span>';
            if (depStatus !== 'done') html += '<span class="dep-blocked">\u26D4 blocked</span>';
          });
          html += '</div>';
        }
        var history = f.status_history || [];
        if (history.length > 0) {
          var last = history[0]; var projName = getProjectById(last.project_id).name;
          html += '<div class="feature-history">Last updated: ' + esc(projName) + ' \u2192 ' + STATUS_LABELS[last.status] + ' \u00b7 ' + timeAgo(last.changed_at) + ' <span class="history-source">(' + esc(last.source === 'manual' ? 'manually' : 'by ' + last.source) + ')</span></div>';
        }
        html += '</div><div class="feature-actions">' +
          '<button class="verify-btn" onclick="checkFeature(\'' + f.id + '\')" title="Verify">Verify</button>' +
          '<button class="feature-action-btn" onclick="openFeatureDetail(\'' + f.id + '\')" title="Details">\uD83D\uDD0D</button>' +
          '<button class="feature-action-btn" onclick="editFeature(\'' + f.id + '\')" title="Edit">\u270E</button>' +
          '<button class="feature-action-btn" onclick="deleteFeature(\'' + f.id + '\')" title="Delete">\u00D7</button>' +
        '</div></div></div>';
        return html;
      }

      function filterCategory(catName) { activeFilter = activeFilter === catName ? null : catName; renderSpecSheet(); }
      function toggleCategory(catName) { collapsedCategories[catName] = !collapsedCategories[catName]; saveCollapseState(); renderSpecSheet(); }
      function saveCollapseState() { if (!currentProd) return; try { localStorage.setItem('symphony_collapse_' + currentProd.id, JSON.stringify(collapsedCategories)); } catch(e) {} }
      function loadCollapseState() { if (!currentProd) { collapsedCategories = {}; return; } try { var s = localStorage.getItem('symphony_collapse_' + currentProd.id); collapsedCategories = s ? JSON.parse(s) : {}; } catch(e) { collapsedCategories = {}; } }
      function updateCategoryDatalist(features) { var cats = {}; features.forEach(function(f) { if (f.category) cats[f.category] = true; }); var dl = document.getElementById('category-list'); if (dl) dl.innerHTML = Object.keys(cats).map(function(c) { return '<option value="' + esc(c) + '">'; }).join(''); }

    """
  end

  defp kanban_js do
    ~S"""
      // ========== ISSUES TAB (KANBAN) ==========

      function issueMatchesProduct(issue) {
        if (!currentProd || selectedProductId === '__all__') return true;
        if (issue.product_id === selectedProductId) return true;
        if ((issue.labels || []).some(function(l) { return l === 'product:' + selectedProductId; })) return true;
        if (issue.project_id && (currentProd.project_ids || []).indexOf(issue.project_id) >= 0) return true;
        return false;
      }

      function renderKanban() {
        var board = document.getElementById('kanban-board');
        if (!board || !boardData || !boardData.columns) return;
        board.innerHTML = '';
        boardData.columns.forEach(function(col) {
          var issues = col.issues.filter(issueMatchesProduct);
          var color = stateColor(col.state);
          var isCollapsed = !!collapsedColumns[col.state];
          var column = document.createElement('div');
          column.className = 'kb-column' + (isCollapsed ? ' collapsed' : '');
          column.style.setProperty('--column-accent', color);
          if (isCollapsed) { column.onclick = function() { toggleKbColumn(col.state); }; column.title = 'Click to expand'; }
          var html = '<div class="kb-column-header"><div class="kb-title-group"><span class="kb-dot"></span><span class="kb-title">' + esc(col.state) + '</span><span class="kb-count">' + issues.length + '</span></div>';
          if (!isCollapsed) html += '<button class="kb-collapse-btn" onclick="event.stopPropagation(); toggleKbColumn(\'' + esc(col.state) + '\')" title="Collapse"><svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2"><polyline points="15 18 9 12 15 6"/></svg></button>';
          html += '</div>';
          if (!isCollapsed) {
            html += '<div class="kb-column-body" data-state="' + esc(col.state) + '" ondragover="handleDragOver(event)" ondragleave="handleDragLeave(event)" ondrop="handleDrop(event)">';
            if (issues.length === 0) html += '<div class="kb-empty">No issues</div>';
            else issues.forEach(function(i) { html += renderIssueCard(i); });
            html += '</div>';
            html += '<div class="kb-quick-add"><input class="kb-quick-input" placeholder="+ Add..." data-state="' + esc(col.state) + '" onkeydown="handleQuickAdd(event)"></div>';
          }
          column.innerHTML = html;
          board.appendChild(column);
        });
        updateIssuesBadge();
      }

      function updateIssuesBadge() {
        if (!boardData || !boardData.columns) return;
        var count = 0;
        boardData.columns.forEach(function(col) { count += col.issues.filter(issueMatchesProduct).length; });
        document.getElementById('issues-tab-badge').textContent = count;
      }

      var DELETABLE_STATES = ['Backlog', 'Cancelled', 'Archived', 'Done'];

      function renderIssueCard(issue) {
        var labels = (issue.labels || []).slice(0, 2).map(function(l) { return '<span class="label-tag">' + esc(l) + '</span>'; }).join('');
        var proj = issue.project_id ? allProjects.find(function(p) { return p.id === issue.project_id; }) : null;
        var projBadge = proj ? '<span class="card-project">' + esc(proj.name) + '</span>' : '';
        var borderColor = PRIORITY_COLORS[issue.priority] || 'transparent';
        var skillCount = (issue.skill_ids || []).length + (issue.skill_group_ids || []).length;
        var skillBadge = skillCount > 0 ? '<span class="card-skills">\u26A1 ' + skillCount + '</span>' : '';
        var ageHtml = '';
        if (issue.created_at) { var days = Math.floor((Date.now() - new Date(issue.created_at).getTime()) / 86400000); if (days > 14) ageHtml = '<span class="card-age stale">' + days + 'd</span>'; else if (days > 3) ageHtml = '<span class="card-age">' + days + 'd</span>'; }
        var planBadge = '';
        if (issue.plan_status === 'planning') planBadge = '<span class="plan-badge planning" title="Planning phase">\u{1F4CB} Planning</span>';
        else if (issue.plan_status === 'plan_review') planBadge = '<span class="plan-badge review" title="Plan awaiting review">\u{1F4CB} Plan Ready</span>';
        else if (issue.plan_status === 'approved') planBadge = '<span class="plan-badge approved" title="Plan approved, executing">\u{1F4CB} Executing</span>';
        var delBtn = DELETABLE_STATES.includes(issue.state)
          ? '<button class="card-delete" onclick="event.stopPropagation(); deleteIssueFromHub(\'' + issue.id + '\', \'' + esc(issue.identifier) + '\')" title="Delete">&times;</button>'
          : '';
        return '<div class="issue-card" draggable="true" data-id="' + issue.id + '" style="border-left-color:' + borderColor + '" ondragstart="handleDragStart(event)" ondragend="handleDragEnd(event)" onclick="window.location.href=\'/board/issues/' + issue.id + '\'">' +
          delBtn +
          '<div class="issue-card-id">' + esc(issue.identifier) + '</div>' +
          '<div class="issue-card-title">' + esc(issue.title) + '</div>' +
          planBadge +
          '<div class="issue-card-meta"><span class="priority-dot priority-' + (issue.priority || 0) + '"></span>' + projBadge + labels + skillBadge + ageHtml +
          (issue.kb_synced_at ? '<span class="kb-sync-dot synced" title="Synced to KB: ' + new Date(issue.kb_synced_at).toLocaleString() + '"></span>' : '') +
          '</div></div>';
      }

      function toggleKbColumn(state) {
        collapsedColumns[state] = !collapsedColumns[state];
        localStorage.setItem('symphony_hub_columns', JSON.stringify(collapsedColumns));
        renderKanban();
      }

      // Drag & Drop and Quick Add — provided by shared kanban_drag_drop_js()

      // Delete issue from hub
      async function deleteIssueFromHub(id, identifier) {
        if (!confirm('Delete ' + identifier + '?')) return;
        try {
          await fetch(API + '/issues/' + id, { method: 'DELETE' });
          await refreshAfterMutation();
          showToast('Deleted ' + identifier, { type: 'success' });
        } catch (err) { showToast('Delete failed: ' + err.message, { type: 'error' }); }
      }


      // Auto-dispatch
      async function loadAutoSettings() {
        try {
          var res = await fetch(API + '/settings/auto-add'); var data = await res.json();
          var el = document.getElementById('auto-toggle'); if (el) el.checked = data.auto_add_enabled === 'true';
          var maxEl = document.getElementById('max-todo-select'); if (maxEl) maxEl.value = data.max_todo_parallel || '3';
          var segEl = document.getElementById('segregate-toggle'); if (segEl) segEl.checked = data.segregate_by_project === 'true';
        } catch(e) {}
      }
      async function handleAutoToggle() {
        var enabled = document.getElementById('auto-toggle').checked;
        await fetch(API + '/settings/auto-add', { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ auto_add_enabled: enabled ? 'true' : 'false' }) });
      }
      async function handleMaxTodoChange() {
        var val = document.getElementById('max-todo-select').value;
        await fetch(API + '/settings/auto-add', { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ max_todo_parallel: val }) });
      }
      async function handleSegregateToggle() {
        var enabled = document.getElementById('segregate-toggle').checked;
        await fetch(API + '/settings/auto-add', { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ segregate_by_project: enabled ? 'true' : 'false' }) });
      }

    """
  end

  defp activity_js do
    ~S"""
      // ========== ACTIVITY TAB ==========

      function renderActivity() {
        var el = document.getElementById('activity-feed');
        if (!el) return;
        if (activityData.length === 0) { el.innerHTML = '<div class="activity-empty">No recent activity for this product.</div>'; return; }
        var html = '<h3 style="font-size:0.9rem;margin-bottom:12px;color:var(--text-secondary)">Recent Agent Activity</h3>';
        activityData.forEach(function(issue) {
          var stateClass = 'todo';
          var icon = '\uD83D\uDCCB';
          var s = (issue.state || '').toLowerCase();
          if (s === 'in progress') { stateClass = 'running'; icon = '\u26A1'; }
          else if (s === 'done') { stateClass = 'done'; icon = '\u2705'; }
          else if (s === 'cancelled') { stateClass = 'failed'; icon = '\u274C'; }
          html += '<div class="activity-item"><div class="activity-icon ' + stateClass + '">' + icon + '</div><div class="activity-body">' +
            '<div class="activity-title"><a href="/board/issues/' + issue.id + '">' + esc(issue.identifier) + '</a> ' + esc(issue.title) + '</div>' +
            '<div class="activity-meta">' +
              '<span class="badge ' + (BADGE_CLASSES[s] || 'badge-default') + '">' + esc(issue.state) + '</span>' +
              '<span>' + timeAgo(issue.updated_at || issue.created_at) + '</span>' +
              (issue.labels ? '<span>' + issue.labels.slice(0, 3).map(function(l) { return esc(l); }).join(', ') + '</span>' : '') +
            '</div></div></div>';
        });
        el.innerHTML = html;
        document.getElementById('activity-tab-badge').textContent = activityData.length;
      }

    """
  end

  defp kb_browser_js do
    ~S"""
      // ========== KNOWLEDGE BASE TAB ==========

      var kbNotes = [];

      async function loadKBNotes() {
        var resultsEl = document.getElementById('kb-results');
        if (!resultsEl) return;
        resultsEl.innerHTML = '<div class="tab-loading"><span class="spinner"></span> Loading notes...</div>';

        // Search with product scope if a product is selected
        var query = '';
        if (currentProd && selectedProductId !== '__all__') {
          query = currentProd.name;
        }

        try {
          var res = await fetch('/board/api/vault/search?q=' + encodeURIComponent(query));
          var data = await res.json();
          kbNotes = data.results || [];
          renderKBNotes();
        } catch (err) {
          resultsEl.innerHTML = '<div class="empty-state" style="height:30vh"><h2>KB unavailable</h2><p>' + esc(err.message) + '</p></div>';
        }
      }

      async function searchKB() {
        var input = document.getElementById('kb-search-input');
        if (!input) return;
        var query = input.value.trim();
        var resultsEl = document.getElementById('kb-results');
        if (!resultsEl) return;
        resultsEl.innerHTML = '<div class="tab-loading"><span class="spinner"></span> Searching...</div>';
        // Hide note viewer
        var viewer = document.getElementById('kb-note-viewer');
        if (viewer) viewer.style.display = 'none';

        try {
          var res = await fetch('/board/api/vault/search?q=' + encodeURIComponent(query));
          var data = await res.json();
          kbNotes = data.results || [];
          renderKBNotes();
        } catch (err) {
          resultsEl.innerHTML = '<div class="empty-state"><p>Search failed: ' + esc(err.message) + '</p></div>';
        }
      }

      function renderKBNotes() {
        var resultsEl = document.getElementById('kb-results');
        if (!resultsEl) return;
        var badge = document.getElementById('kb-tab-badge');
        if (badge) { badge.textContent = kbNotes.length; badge.style.display = kbNotes.length > 0 ? '' : 'none'; }

        if (kbNotes.length === 0) {
          resultsEl.innerHTML = '<div class="empty-state" style="height:30vh">' +
            '<h2>No notes found</h2>' +
            '<p>Send issue reports to the Knowledge Base using the "Send to KB" button on completed issues, or run extract-logic tasks.</p></div>';
          return;
        }

        var html = '<div class="kb-notes-list">';
        kbNotes.forEach(function(note) {
          var pathParts = note.path.replace(/\\\\/g, '/').split('/');
          var folder = pathParts.length > 1 ? pathParts.slice(0, -1).join('/') : '';
          html += '<div class="kb-note-card" onclick="viewKBNote(\'' + esc(note.path) + '\')">' +
            '<div class="kb-note-title">' + esc(note.title) + '</div>' +
            (folder ? '<div class="kb-note-folder">' + esc(folder) + '</div>' : '') +
            (note.snippet ? '<div class="kb-note-snippet">' + esc(note.snippet) + '</div>' : '') +
          '</div>';
        });
        html += '</div>';
        resultsEl.innerHTML = html;
      }

      async function viewKBNote(notePath) {
        var viewer = document.getElementById('kb-note-viewer');
        var resultsEl = document.getElementById('kb-results');
        if (!viewer || !resultsEl) return;

        viewer.style.display = '';
        viewer.innerHTML = '<div class="tab-loading"><span class="spinner"></span> Loading note...</div>';

        try {
          var res = await fetch('/board/api/vault/note?path=' + encodeURIComponent(notePath));
          if (!res.ok) throw new Error('Note not found');
          var data = await res.json();

          var fm = data.frontmatter || {};
          var fmHtml = '';
          Object.keys(fm).forEach(function(k) {
            var v = Array.isArray(fm[k]) ? fm[k].join(', ') : fm[k];
            fmHtml += '<span class="kb-fm-tag"><strong>' + esc(k) + ':</strong> ' + esc(v) + '</span>';
          });

          viewer.innerHTML = '<div class="kb-note-header">' +
            '<button class="btn btn-ghost btn-sm" onclick="closeKBNote()">Back</button>' +
            '<span class="kb-note-path">' + esc(notePath) + '</span>' +
            '<button class="btn btn-ghost btn-sm" onclick="openKBEditorForNote(\'' + esc(notePath) + '\')">Edit</button>' +
            '<button class="btn btn-ghost btn-sm" onclick="openAppendToNote(\'' + esc(notePath) + '\')">Append</button>' +
            '<button class="btn btn-ghost btn-sm" onclick="showVersionHistory(\'' + esc(notePath) + '\')">History</button>' +
            '<button class="btn btn-ghost btn-sm" style="color:var(--red)" onclick="deleteKBNote(\'' + esc(notePath) + '\')">Delete</button>' +
          '</div>' +
          (fmHtml ? '<div class="kb-frontmatter">' + fmHtml + '</div>' : '') +
          '<div class="kb-note-content markdown-body">' + renderMarkdown(data.content || '') + '</div>' +
          '<div id="kb-version-panel" style="display:none"></div>';
        } catch (err) {
          viewer.innerHTML = '<div class="kb-note-header"><button class="btn btn-ghost btn-sm" onclick="closeKBNote()">Back</button></div>' +
            '<div class="empty-state"><p>Failed to load note: ' + esc(err.message) + '</p></div>';
        }
      }

      function closeKBNote() {
        var viewer = document.getElementById('kb-note-viewer');
        if (viewer) viewer.style.display = 'none';
      }

      async function deleteKBNote(notePath) {
        if (!confirm('Delete this note from the Knowledge Base?')) return;
        try {
          var res = await fetch('/board/api/vault/note', {
            method: 'DELETE',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ path: notePath })
          });
          if (res.ok) {
            showToast('Note deleted', { type: 'success' });
            closeKBNote();
            loadKBNotes();
          } else {
            var data = await res.json();
            showToast('Delete failed: ' + (data.error || 'unknown'), { type: 'error' });
          }
        } catch (err) {
          showToast('Delete failed: ' + err.message, { type: 'error' });
        }
      }

    """
  end

  defp kb_editor_js do
    ~S"""
      // ========== NOTE EDITOR (Gap 2) ==========

      var editingNotePath = null;

      function openKBEditor(productName) {
        var editor = document.getElementById('kb-editor');
        var results = document.getElementById('kb-results');
        var viewer = document.getElementById('kb-note-viewer');
        if (!editor) return;
        editingNotePath = null;
        if (results) results.style.display = 'none';
        if (viewer) viewer.style.display = 'none';
        editor.style.display = '';
        var prodName = productName || (currentProd && selectedProductId !== '__all__' ? currentProd.name : '');
        editor.innerHTML = '<div class="kb-editor-header">' +
          '<h3>New Note</h3>' +
          '<button class="btn btn-ghost btn-sm" onclick="closeKBEditor()">Cancel</button>' +
        '</div>' +
        '<div class="kb-editor-field"><label>Title</label><input type="text" id="kb-edit-title" placeholder="Note title..."></div>' +
        '<div class="kb-editor-field"><label>Product</label><input type="text" id="kb-edit-product" value="' + esc(prodName) + '" placeholder="Product name (optional)"></div>' +
        '<div class="kb-editor-field"><label>Tags (comma-separated)</label><input type="text" id="kb-edit-tags" placeholder="symphony, business-rule"></div>' +
        '<div class="kb-editor-field"><label>Content (Markdown)</label><textarea id="kb-edit-content" placeholder="Write your note in Markdown..."></textarea></div>' +
        '<div class="kb-editor-actions">' +
          '<button class="btn btn-primary btn-sm" onclick="saveKBNote()">Save Note</button>' +
          '<button class="btn btn-ghost btn-sm" onclick="closeKBEditor()">Cancel</button>' +
        '</div>';
        document.getElementById('kb-edit-title').focus();
      }

      async function openKBEditorForNote(notePath) {
        var editor = document.getElementById('kb-editor');
        var viewer = document.getElementById('kb-note-viewer');
        if (!editor) return;
        editingNotePath = notePath;
        if (viewer) viewer.style.display = 'none';
        editor.style.display = '';
        editor.innerHTML = '<div class="tab-loading"><span class="spinner"></span> Loading note...</div>';
        try {
          var res = await fetch('/board/api/vault/note?path=' + encodeURIComponent(notePath));
          if (!res.ok) throw new Error('Failed to load note');
          var data = await res.json();
          var fm = data.frontmatter || {};
          var title = notePath.split('/').pop().replace('.md', '');
          var product = fm.product || '';
          var tags = Array.isArray(fm.tags) ? fm.tags.join(', ') : (fm.tags || '');
          editor.innerHTML = '<div class="kb-editor-header">' +
            '<h3>Edit Note</h3>' +
            '<button class="btn btn-ghost btn-sm" onclick="closeKBEditor()">Cancel</button>' +
          '</div>' +
          '<div class="kb-editor-field"><label>Title</label><input type="text" id="kb-edit-title" value="' + esc(title) + '"></div>' +
          '<div class="kb-editor-field"><label>Product</label><input type="text" id="kb-edit-product" value="' + esc(product) + '"></div>' +
          '<div class="kb-editor-field"><label>Tags (comma-separated)</label><input type="text" id="kb-edit-tags" value="' + esc(tags) + '"></div>' +
          '<div class="kb-editor-field"><label>Content (Markdown)</label><textarea id="kb-edit-content">' + esc(data.content || '') + '</textarea></div>' +
          '<div class="kb-editor-actions">' +
            '<button class="btn btn-primary btn-sm" onclick="saveKBNote()">Save Note</button>' +
            '<button class="btn btn-ghost btn-sm" onclick="closeKBEditor()">Cancel</button>' +
          '</div>';
        } catch (err) {
          editor.innerHTML = '<p style="color:var(--red)">Failed to load: ' + esc(err.message) + '</p>' +
            '<button class="btn btn-ghost btn-sm" onclick="closeKBEditor()">Back</button>';
        }
      }

      async function saveKBNote() {
        var title = (document.getElementById('kb-edit-title').value || '').trim();
        if (!title) { document.getElementById('kb-edit-title').focus(); showToast('Title is required', { type: 'error' }); return; }
        var product = (document.getElementById('kb-edit-product').value || '').trim() || null;
        var tagsStr = (document.getElementById('kb-edit-tags').value || '').trim();
        var tags = tagsStr ? tagsStr.split(',').map(function(t) { return t.trim(); }).filter(Boolean) : [];
        var content = document.getElementById('kb-edit-content').value || '';
        try {
          var res = await fetch('/board/api/vault/create', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ title: title, content: content, product_name: product, tags: tags })
          });
          var data = await res.json();
          if (data.ok) {
            showToast(editingNotePath ? 'Note updated' : 'Note created', { type: 'success' });
            closeKBEditor();
            loadKBNotes();
          } else {
            showToast('Save failed: ' + (data.error || 'unknown'), { type: 'error' });
          }
        } catch (err) {
          showToast('Save failed: ' + err.message, { type: 'error' });
        }
      }

      function closeKBEditor() {
        var editor = document.getElementById('kb-editor');
        var results = document.getElementById('kb-results');
        if (editor) editor.style.display = 'none';
        if (results) results.style.display = '';
        editingNotePath = null;
      }

      // ========== APPEND TO NOTE ==========

      async function openAppendToNote(notePath) {
        var viewer = document.getElementById('kb-note-viewer');
        if (!viewer) return;
        var existing = document.getElementById('kb-append-form');
        if (existing) { existing.remove(); return; }
        var form = document.createElement('div');
        form.id = 'kb-append-form';
        form.style.marginTop = '12px';
        form.innerHTML = '<div class="kb-editor-field"><label>Append Content</label>' +
          '<textarea id="kb-append-content" style="min-height:120px" placeholder="Content to append..."></textarea></div>' +
          '<div class="kb-editor-actions">' +
            '<button class="btn btn-primary btn-sm" onclick="doAppendToNote(\'' + esc(notePath) + '\')">Append</button>' +
            '<button class="btn btn-ghost btn-sm" onclick="document.getElementById(\'kb-append-form\').remove()">Cancel</button>' +
          '</div>';
        viewer.appendChild(form);
        document.getElementById('kb-append-content').focus();
      }

      async function doAppendToNote(notePath) {
        var content = (document.getElementById('kb-append-content').value || '').trim();
        if (!content) { showToast('Content is required', { type: 'error' }); return; }
        try {
          var res = await fetch('/board/api/vault/append', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ path: notePath, content: content })
          });
          var data = await res.json();
          if (data.ok) {
            showToast('Content appended', { type: 'success' });
            viewKBNote(notePath);
          } else {
            showToast('Append failed: ' + (data.error || 'unknown'), { type: 'error' });
          }
        } catch (err) {
          showToast('Append failed: ' + err.message, { type: 'error' });
        }
      }

    """
  end

  defp kb_versions_js do
    ~S"""
      // ========== BATCH SEND TO KB (Gap 6) ==========

      async function batchSendToKB() {
        if (!currentProd || selectedProductId === '__all__') {
          showToast('Select a product first', { type: 'error' });
          return;
        }
        // Find all completed/done issues for this product
        var doneIssues = [];
        if (boardData && boardData.columns) {
          boardData.columns.forEach(function(col) {
            if (col.state === 'Done' || col.state === 'Review') {
              col.issues.forEach(function(i) {
                if (i.product_id === selectedProductId) doneIssues.push(i);
              });
            }
          });
        }
        if (doneIssues.length === 0) {
          showToast('No completed issues found for this product', { type: 'error' });
          return;
        }
        var unsynced = doneIssues.filter(function(i) { return !i.kb_synced_at; });
        var msg = unsynced.length > 0
          ? 'Send ' + unsynced.length + ' unsynced issue(s) to KB? (' + doneIssues.length + ' total completed)'
          : 'All ' + doneIssues.length + ' issue(s) already synced. Re-send all?';
        if (!confirm(msg)) return;
        var idsToSend = unsynced.length > 0 ? unsynced.map(function(i) { return i.id; }) : doneIssues.map(function(i) { return i.id; });
        showToast('Sending ' + idsToSend.length + ' issue(s) to KB...', { type: 'info' });
        try {
          var res = await fetch('/board/api/vault/send-batch', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ issue_ids: idsToSend })
          });
          var data = await res.json();
          if (data.ok) {
            showToast('Sent ' + (data.total_notes_written || 0) + ' note(s) to KB', { type: 'success' });
            await loadBoardSnapshot();
            renderKanban();
            loadKBNotes();
          } else {
            showToast('Batch send failed: ' + (data.error || 'unknown'), { type: 'error' });
          }
        } catch (err) {
          showToast('Batch send failed: ' + err.message, { type: 'error' });
        }
      }

      // ========== VERSION HISTORY (Gap 7) ==========

      async function showVersionHistory(notePath) {
        var panel = document.getElementById('kb-version-panel');
        if (!panel) return;
        if (panel.style.display !== 'none') { panel.style.display = 'none'; return; }
        panel.style.display = '';
        panel.innerHTML = '<div class="tab-loading"><span class="spinner"></span> Loading versions...</div>';
        try {
          var res = await fetch('/board/api/vault/versions?path=' + encodeURIComponent(notePath));
          var data = await res.json();
          var versions = data.versions || [];
          if (versions.length === 0) {
            panel.innerHTML = '<div style="padding:12px;color:var(--text-muted);font-size:0.82rem">No previous versions found.</div>';
            return;
          }
          var html = '<div style="padding:12px 0"><h4 style="margin:0 0 8px;font-size:0.88rem">Version History (' + versions.length + ')</h4><div class="kb-version-list">';
          versions.forEach(function(v) {
            var sizeKb = (v.size / 1024).toFixed(1);
            var ts = v.timestamp.replace('T', ' ');
            html += '<div class="kb-version-item">' +
              '<span class="kb-version-timestamp">' + esc(ts) + '</span>' +
              '<span class="kb-version-size">' + sizeKb + ' KB</span>' +
              '<div class="kb-version-actions">' +
                '<button class="btn btn-ghost btn-sm" onclick="viewVersion(\'' + esc(v.path) + '\', \'' + esc(notePath) + '\')">View</button>' +
                '<button class="btn btn-ghost btn-sm" onclick="diffVersion(\'' + esc(v.path) + '\', \'' + esc(notePath) + '\')">Diff</button>' +
                '<button class="btn btn-ghost btn-sm" style="color:var(--orange)" onclick="restoreVersion(\'' + esc(v.path) + '\', \'' + esc(notePath) + '\')">Restore</button>' +
              '</div>' +
            '</div>';
          });
          html += '</div></div>';
          panel.innerHTML = html;
        } catch (err) {
          panel.innerHTML = '<div style="padding:12px;color:var(--red)">Failed to load versions: ' + esc(err.message) + '</div>';
        }
      }

      async function viewVersion(versionPath, notePath) {
        var panel = document.getElementById('kb-version-panel');
        if (!panel) return;
        try {
          var res = await fetch('/board/api/vault/version?path=' + encodeURIComponent(versionPath));
          if (!res.ok) throw new Error('Version not found');
          var data = await res.json();
          var diffEl = document.getElementById('kb-version-diff');
          if (diffEl) diffEl.remove();
          var div = document.createElement('div');
          div.id = 'kb-version-diff';
          div.className = 'kb-diff-view';
          div.innerHTML = '<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px">' +
            '<strong style="font-size:0.82rem">Version: ' + esc(versionPath.split('/').pop()) + '</strong>' +
            '<button class="btn btn-ghost btn-sm" onclick="document.getElementById(\'kb-version-diff\').remove()">Close</button>' +
          '</div>' +
          '<div class="kb-note-content markdown-body" style="max-height:40vh">' + renderMarkdown(data.content || '') + '</div>';
          panel.appendChild(div);
        } catch (err) {
          showToast('Failed to load version: ' + err.message, { type: 'error' });
        }
      }

      async function diffVersion(versionPath, notePath) {
        var panel = document.getElementById('kb-version-panel');
        if (!panel) return;
        try {
          var resCurrent = await fetch('/board/api/vault/note?path=' + encodeURIComponent(notePath));
          var resVersion = await fetch('/board/api/vault/version?path=' + encodeURIComponent(versionPath));
          if (!resCurrent.ok || !resVersion.ok) throw new Error('Failed to load');
          var currentData = await resCurrent.json();
          var versionData = await resVersion.json();
          var currentLines = (currentData.content || '').split('\\n');
          var versionLines = (versionData.content || '').split('\\n');
          var diffHtml = computeSimpleDiff(versionLines, currentLines);
          var diffEl = document.getElementById('kb-version-diff');
          if (diffEl) diffEl.remove();
          var div = document.createElement('div');
          div.id = 'kb-version-diff';
          div.className = 'kb-diff-view';
          div.innerHTML = '<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px">' +
            '<strong style="font-size:0.82rem">Diff: version vs current</strong>' +
            '<button class="btn btn-ghost btn-sm" onclick="document.getElementById(\'kb-version-diff\').remove()">Close</button>' +
          '</div><pre>' + diffHtml + '</pre>';
          panel.appendChild(div);
        } catch (err) {
          showToast('Diff failed: ' + err.message, { type: 'error' });
        }
      }

      function computeSimpleDiff(oldLines, newLines) {
        var html = '';
        var maxLen = Math.max(oldLines.length, newLines.length);
        for (var i = 0; i < maxLen; i++) {
          var oldLine = i < oldLines.length ? oldLines[i] : null;
          var newLine = i < newLines.length ? newLines[i] : null;
          if (oldLine === newLine) {
            html += ' ' + esc(oldLine || '') + '\\n';
          } else {
            if (oldLine !== null) html += '<span class="diff-del">-' + esc(oldLine) + '</span>\\n';
            if (newLine !== null) html += '<span class="diff-add">+' + esc(newLine) + '</span>\\n';
          }
        }
        return html;
      }

      async function restoreVersion(versionPath, notePath) {
        if (!confirm('Restore this version? The current version will be saved to history first.')) return;
        try {
          var res = await fetch('/board/api/vault/restore', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ version_path: versionPath, note_path: notePath })
          });
          var data = await res.json();
          if (data.ok) {
            showToast('Version restored', { type: 'success' });
            viewKBNote(notePath);
          } else {
            showToast('Restore failed: ' + (data.error || 'unknown'), { type: 'error' });
          }
        } catch (err) {
          showToast('Restore failed: ' + err.message, { type: 'error' });
        }
      }

    """
  end

  defp modal_product_js do
    ~S"""
      // ========== MODALS: PRODUCT CRUD ==========

      function openNewProductModal() {
        document.getElementById('prod-modal-title').textContent = 'New Product';
        document.getElementById('product-form-id').value = '';
        document.getElementById('product-form-name').value = '';
        document.getElementById('product-form-desc').value = '';
        document.getElementById('product-form-labels').value = '';
        document.getElementById('prod-ai-draft-input').value = '';
        document.getElementById('prod-delete-btn').style.display = 'none';
        renderProjectChecklist([]);
        openModal('prod-modal');
        document.getElementById('prod-ai-draft-input').focus();
      }

      function openEditProductModal() {
        if (!currentProd) return;
        document.getElementById('prod-modal-title').textContent = 'Edit Product';
        document.getElementById('product-form-id').value = currentProd.id;
        document.getElementById('product-form-name').value = currentProd.name || '';
        document.getElementById('product-form-desc').value = currentProd.description || '';
        document.getElementById('product-form-labels').value = (currentProd.labels || []).join(', ');
        document.getElementById('prod-ai-draft-input').value = '';
        document.getElementById('prod-delete-btn').style.display = '';
        renderProjectChecklist(currentProd.project_ids || []);
        openModal('prod-modal');
        document.getElementById('product-form-name').focus();
      }

      function closeProdModal() { closeModal('prod-modal'); }

      function renderProjectChecklist(selectedIds) {
        var container = document.getElementById('project-checklist');
        if (allProjects.length === 0) { container.innerHTML = '<div style="color:var(--text-muted);padding:8px;font-size:0.8rem">No projects yet. <a href="/board/projects" style="color:var(--accent)">Go to Projects</a> to add some.</div>'; return; }
        container.innerHTML = allProjects.map(function(p) { var checked = selectedIds.indexOf(p.id) !== -1 ? 'checked' : ''; return '<label class="project-check-item"><input type="checkbox" value="' + p.id + '" ' + checked + '> ' + esc(p.name) + '</label>'; }).join('');
      }

      async function saveProduct() {
        var editId = document.getElementById('product-form-id').value;
        var name = document.getElementById('product-form-name').value.trim();
        if (!name) { document.getElementById('product-form-name').focus(); return; }
        var desc = document.getElementById('product-form-desc').value.trim();
        var labelsStr = document.getElementById('product-form-labels').value;
        var labels = labelsStr ? labelsStr.split(',').map(function(l) { return l.trim(); }).filter(Boolean) : [];
        var checks = document.querySelectorAll('#project-checklist input[type=checkbox]:checked');
        var projectIds = Array.from(checks).map(function(c) { return c.value; });
        var payload = { name: name, description: desc || null, project_ids: projectIds, labels: labels };
        var res;
        if (editId) res = await fetch(API + '/products/' + editId, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
        else res = await fetch(API + '/products', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
        if (res.status === 409) { showToast('A product with that name already exists', { type: 'error' }); return; }
        closeModal('prod-modal');
        showToast(editId ? 'Product updated' : 'Product created', { type: 'success' });
        await loadProducts();
        renderSidebar();
        if (editId) await selectProduct(editId);
        else if (allProducts.length > 0) await selectProduct(allProducts[allProducts.length - 1].id);
      }

      async function deleteCurrentProduct() {
        if (!currentProd) return;
        if (!confirm('Delete product "' + currentProd.name + '"?')) return;
        await fetch(API + '/products/' + currentProd.id, { method: 'DELETE' });
        selectedProductId = null; currentProd = null;
        await loadProducts(); renderSidebar(); saveState(); showWelcome();
      }

    """
  end

  defp modal_feature_js do
    ~S"""
      // ========== MODALS: FEATURE CRUD ==========

      function renderDepsChecklist(selectedIds, excludeId) {
        var container = document.getElementById('feature-deps-checklist');
        var features = (currentProd && currentProd.features) ? currentProd.features : [];
        var available = features.filter(function(f) { return f.id !== excludeId; });
        if (available.length === 0) { container.innerHTML = '<div style="color:var(--text-muted);padding:8px;font-size:0.8rem">No other features.</div>'; return; }
        container.innerHTML = available.map(function(f) { var checked = selectedIds.indexOf(f.id) !== -1 ? 'checked' : ''; return '<label class="project-check-item"><input type="checkbox" value="' + f.id + '" ' + checked + '> ' + esc(f.name) + '</label>'; }).join('');
      }

      function openAddFeatureModal(defaultCategory) {
        document.getElementById('feature-modal-title').textContent = 'Add Feature';
        document.getElementById('feature-edit-id').value = '';
        document.getElementById('feature-name').value = '';
        document.getElementById('feature-desc').value = '';
        document.getElementById('feature-category').value = defaultCategory && defaultCategory !== 'Uncategorized' ? defaultCategory : '';
        renderDepsChecklist([], null);
        openModal('feature-modal');
        document.getElementById('feature-name').focus();
      }

      function editFeature(fid) {
        var f = currentProd.features.find(function(x) { return x.id === fid; }); if (!f) return;
        document.getElementById('feature-modal-title').textContent = 'Edit Feature';
        document.getElementById('feature-edit-id').value = fid;
        document.getElementById('feature-name').value = f.name || '';
        document.getElementById('feature-desc').value = f.description || '';
        document.getElementById('feature-category').value = f.category || '';
        renderDepsChecklist(f.depends_on || [], fid);
        openModal('feature-modal');
        document.getElementById('feature-name').focus();
      }

      function closeFeatureModal() { closeModal('feature-modal'); }

      async function saveFeature() {
        var editId = document.getElementById('feature-edit-id').value;
        var name = document.getElementById('feature-name').value.trim(); if (!name) { document.getElementById('feature-name').focus(); return; }
        var desc = document.getElementById('feature-desc').value.trim();
        var category = document.getElementById('feature-category').value.trim();
        var depChecks = document.querySelectorAll('#feature-deps-checklist input[type=checkbox]:checked');
        var dependsOn = Array.from(depChecks).map(function(c) { return c.value; });
        var payload = { name: name, description: desc || null, category: category || null, depends_on: dependsOn };
        var fRes;
        if (editId) fRes = await fetch(API + '/products/' + currentProd.id + '/features/' + editId, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
        else fRes = await fetch(API + '/products/' + currentProd.id + '/features', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
        if (fRes.status === 409) { showToast('A feature with that name already exists', { type: 'error' }); return; }
        closeFeatureModal();
        var res = await fetch(API + '/products/' + currentProd.id); currentProd = await res.json(); renderSpecSheet();
      }

      async function deleteFeature(fid) {
        if (!confirm('Delete this feature?')) return;
        await fetch(API + '/products/' + currentProd.id + '/features/' + fid, { method: 'DELETE' });
        var res = await fetch(API + '/products/' + currentProd.id); currentProd = await res.json(); renderSpecSheet();
      }

      // Feature Detail Modal
      function openFeatureDetail(fid) {
        var f = currentProd.features.find(function(x) { return x.id === fid; }); if (!f) return;
        var featurePids = Object.keys(f.statuses || {});
        document.getElementById('detail-modal-title').textContent = f.name;
        var html = '';
        if (f.description) html += '<p style="font-size:0.85rem;color:var(--text-secondary);margin-bottom:16px">' + esc(f.description) + '</p>';
        featurePids.forEach(function(pid) {
          var p = getProjectById(pid); var status = f.statuses[pid] || 'missing';
          html += '<div class="detail-project-row"><span class="detail-project-name">' + esc(p.name) + '</span><button class="detail-status-btn badge-' + status + '" onclick="cycleDetailStatus(\'' + fid + '\',\'' + pid + '\',\'' + status + '\')" title="Click to change">' + STATUS_ICONS[status] + ' ' + STATUS_LABELS[status] + '</button></div>';
        });
        var history = f.status_history || [];
        if (history.length > 0) {
          var limit = detailHistoryExpanded[fid] ? history.length : 10;
          html += '<div style="margin-top:16px;border-top:1px solid var(--border);padding-top:12px"><h4 style="font-size:0.8rem;color:var(--text-muted);margin-bottom:8px">History (' + history.length + ')</h4>';
          history.slice(0, limit).forEach(function(h) { html += '<div style="font-size:0.75rem;color:var(--text-muted);padding:3px 0">' + esc(getProjectById(h.project_id).name) + ' \u2192 ' + STATUS_LABELS[h.status] + ' <span class="history-source">(' + esc(h.source) + ')</span> \u00b7 ' + timeAgo(h.changed_at) + '</div>'; });
          if (history.length > 10) { html += '<div style="padding-top:4px"><button class="btn btn-ghost btn-sm" onclick="toggleDetailHistory(\'' + fid + '\')">' + (detailHistoryExpanded[fid] ? 'Show less' : 'Show all ' + history.length) + '</button></div>'; }
          html += '</div>';
        }
        document.getElementById('detail-modal-body').innerHTML = html;
        openModal('detail-modal');
      }

      function closeDetailModal() { closeModal('detail-modal'); }
      function toggleDetailHistory(fid) { detailHistoryExpanded[fid] = !detailHistoryExpanded[fid]; openFeatureDetail(fid); }

      async function cycleDetailStatus(featureId, projectId, current) {
        var idx = STATUS_ORDER.indexOf(current); var next = STATUS_ORDER[(idx + 1) % STATUS_ORDER.length];
        await fetch(API + '/products/' + currentProd.id + '/features/' + featureId + '/status', { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ project_id: projectId, status: next, source: 'manual' }) });
        var res = await fetch(API + '/products/' + currentProd.id); currentProd = await res.json(); renderSpecSheet(); openFeatureDetail(featureId);
      }

    """
  end

  defp modal_agent_js do
    ~S"""
      // ========== MODALS: AGENT ACTIONS ==========

      // Skill picker — shared from UIHelpers.skill_picker_js()

      // Analyze Gaps
      async function analyzeGaps() {
        if (!currentProd) return;
        if (!confirm('Create agent task for gap analysis?')) return;
        var btn = document.getElementById('analyze-gaps-btn'); var origText = btn.textContent; btn.textContent = 'Creating...'; btn.disabled = true;
        try { var res = await fetch(API + '/products/' + currentProd.id + '/analyze-gaps', { method: 'POST' }); var data = await res.json(); showToast(data.message || 'Task created', { type: 'success' }); }
        catch (e) { showToast('Failed: ' + e.message, { type: 'error' }); }
        finally { btn.textContent = origText; btn.disabled = false; }
      }

      // Generate Features
      function openGenerateModal() { if (!currentProd) return; document.getElementById('generate-prompt').value = ''; document.getElementById('generate-skills').style.display = 'none'; openModal('generate-modal'); document.getElementById('generate-prompt').focus(); }
      function closeGenerateModal() { closeModal('generate-modal'); }
      async function generateFeatures() {
        var prompt = document.getElementById('generate-prompt').value.trim(); if (!prompt) { document.getElementById('generate-prompt').focus(); return; }
        var skills = getSelectedSkills('generate-skills'); var btn = document.getElementById('generate-btn'); btn.innerHTML = '<span class="spinner"></span> Creating...'; btn.disabled = true;
        try { var res = await fetch(API + '/products/' + currentProd.id + '/generate-features', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ prompt: prompt, skill_ids: skills.skill_ids, skill_group_ids: skills.skill_group_ids }) }); var data = await res.json(); if (data.error) { showToast(data.message || data.error, { type: 'error' }); return; } closeGenerateModal(); showToast(data.issue.identifier + ' created', { type: 'success' }); }
        catch (e) { showToast('Failed: ' + e.message, { type: 'error' }); }
        finally { btn.innerHTML = 'Create Agent Task'; btn.disabled = false; }
      }

      // Check Feature
      async function checkFeature(featureId) {
        if (!currentProd) return;
        var feature = currentProd.features.find(function(f) { return f.id === featureId; }); if (!feature) return;
        var toCheck = (currentProd.project_ids || []).filter(function(pid) { var s = feature.statuses[pid] || 'missing'; return s !== 'done' && s !== 'n_a'; });
        if (toCheck.length === 0) { showToast('All projects are done or N/A', { type: 'info' }); return; }
        if (!confirm('Create ' + toCheck.length + ' check issue(s)?')) return;
        try { var res = await fetch(API + '/products/' + currentProd.id + '/features/' + featureId + '/check', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({}) }); var data = await res.json(); var res2 = await fetch(API + '/products/' + currentProd.id); currentProd = await res2.json(); renderSpecSheet(); showToast('Created ' + (data.issues || []).length + ' check issue(s)', { type: 'success' }); }
        catch (e) { showToast('Failed: ' + e.message, { type: 'error' }); }
      }

      // Analyze Existing
      async function analyzeExistingFeatures() {
        if (!currentProd) return;
        if (!confirm('Create agent task to discover implemented features?')) return;
        var btn = document.getElementById('analyze-existing-btn'); var origText = btn.textContent; btn.textContent = 'Creating...'; btn.disabled = true;
        try { var res = await fetch(API + '/products/' + currentProd.id + '/analyze-existing-features', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({}) }); var data = await res.json(); showToast(data.issue.identifier + ' created', { type: 'success' }); }
        catch (e) { showToast('Failed: ' + e.message, { type: 'error' }); }
        finally { btn.textContent = origText; btn.disabled = false; }
      }

      // Code Review
      function openCodeReviewModal() { if (!currentProd) return; document.getElementById('review-focus').value = ''; document.getElementById('review-skills').style.display = 'none'; openModal('code-review-modal'); document.getElementById('review-focus').focus(); }
      function closeCodeReviewModal() { closeModal('code-review-modal'); }
      async function startCodeReview() {
        var focus = document.getElementById('review-focus').value.trim(); var skills = getSelectedSkills('review-skills'); var btn = document.getElementById('code-review-btn'); btn.innerHTML = '<span class="spinner"></span> Creating...'; btn.disabled = true;
        try { var res = await fetch(API + '/products/' + currentProd.id + '/code-review', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ focus: focus, skill_ids: skills.skill_ids, skill_group_ids: skills.skill_group_ids }) }); var data = await res.json(); if (data.error) { showToast(data.message || data.error, { type: 'error' }); return; } closeCodeReviewModal(); showToast(data.issue.identifier + ' created', { type: 'success' }); }
        catch (e) { showToast('Failed: ' + e.message, { type: 'error' }); }
        finally { btn.innerHTML = 'Start Code Review'; btn.disabled = false; }
      }

      // Generate Definition
      function openGenDefModal() { if (!currentProd) return; document.getElementById('gendef-context').value = ''; document.getElementById('gendef-skills').style.display = 'none'; openModal('gendef-modal'); document.getElementById('gendef-context').focus(); }
      function closeGenDefModal() { closeModal('gendef-modal'); }
      async function generateDefinition() {
        var context = document.getElementById('gendef-context').value.trim(); var skills = getSelectedSkills('gendef-skills'); var btn = document.getElementById('gendef-btn'); btn.innerHTML = '<span class="spinner"></span> Creating...'; btn.disabled = true;
        try { var res = await fetch(API + '/products/' + currentProd.id + '/generate-definition', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ context: context, skill_ids: skills.skill_ids, skill_group_ids: skills.skill_group_ids }) }); var data = await res.json(); if (data.error) { showToast(data.message || data.error, { type: 'error' }); return; } closeGenDefModal(); showToast(data.issue.identifier + ' created', { type: 'success' }); }
        catch (e) { showToast('Failed: ' + e.message, { type: 'error' }); }
        finally { btn.innerHTML = 'Generate Definition'; btn.disabled = false; }
      }

      // Product Task
      function openProductTaskModal() { if (!currentProd) return; document.getElementById('ptask-title').value = ''; document.getElementById('ptask-prompt').value = ''; document.getElementById('ptask-priority').value = '2'; document.getElementById('ptask-skills').style.display = 'none'; openModal('product-task-modal'); document.getElementById('ptask-title').focus(); }
      function closeProductTaskModal() { closeModal('product-task-modal'); }
      async function createProductTask() {
        var title = document.getElementById('ptask-title').value.trim(); var prompt = document.getElementById('ptask-prompt').value.trim();
        if (!title) { document.getElementById('ptask-title').focus(); return; } if (!prompt) { document.getElementById('ptask-prompt').focus(); return; }
        var priority = parseInt(document.getElementById('ptask-priority').value) || 2; var skills = getSelectedSkills('ptask-skills'); var btn = document.getElementById('ptask-btn'); btn.innerHTML = '<span class="spinner"></span> Creating...'; btn.disabled = true;
        try { var res = await fetch(API + '/products/' + currentProd.id + '/tasks', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ title: title, prompt: prompt, priority: priority, skill_ids: skills.skill_ids, skill_group_ids: skills.skill_group_ids }) }); var data = await res.json(); if (data.error) { showToast(data.message || data.error, { type: 'error' }); return; } closeProductTaskModal(); showToast(data.issue.identifier + ' created', { type: 'success' }); }
        catch (e) { showToast('Failed: ' + e.message, { type: 'error' }); }
        finally { btn.innerHTML = 'Create Task'; btn.disabled = false; }
      }

    """
  end

  defp modal_issue_js do
    ~S"""
      // ========== ISSUE CREATE MODAL ==========

      // Hooks for the shared AI draft (prefix "hi")
      function hiAiDraftExtras() {
        return {};
      }
      function hiAiDraftApply(draft) {
        var skillIds = draft.skill_ids || [];
        if (skillIds.length > 0) {
          renderSkillPicker('hi-skills', skillIds, []);
          document.getElementById('hi-skills').style.display = '';
        }
      }

      async function aiDraftProduct() {
        var input = document.getElementById('prod-ai-draft-input');
        var hint = input.value.trim();
        if (!hint) { input.focus(); return; }
        var btn = document.getElementById('prod-ai-draft-btn');
        btn.textContent = 'Drafting...'; btn.disabled = true; input.disabled = true;
        try {
          var res = await fetch(API + '/ai/draft-product', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ hint: hint }) });
          var draft = await res.json();
          if (draft.error) { showToast('Draft failed: ' + draft.error, { type: 'error' }); return; }
          document.getElementById('product-form-name').value = draft.name || hint;
          document.getElementById('product-form-desc').value = draft.description || '';
          document.getElementById('product-form-labels').value = (draft.labels || []).join(', ');
          input.value = '';
          showToast('Product drafted by AI', { type: 'success' });
        } catch (e) { showToast('Draft failed: ' + e.message, { type: 'error' }); }
        finally { btn.textContent = 'AI Draft'; btn.disabled = false; input.disabled = false; }
      }

      async function aiDraftProject() {
        var input = document.getElementById('project-ai-draft-input');
        var hint = input.value.trim();
        if (!hint) { input.focus(); return; }
        var btn = document.getElementById('project-ai-draft-btn');
        btn.textContent = 'Drafting...'; btn.disabled = true; input.disabled = true;
        try {
          var res = await fetch(API + '/ai/draft-project', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ hint: hint }) });
          var draft = await res.json();
          if (draft.error) { showToast('Draft failed: ' + draft.error, { type: 'error' }); return; }
          document.getElementById('project-form-name').value = draft.name || hint;
          document.getElementById('project-form-desc').value = draft.description || '';
          document.getElementById('project-form-labels').value = (draft.tags || []).join(', ');
          document.getElementById('project-form-priority').value = (draft.priority || 0).toString();
          input.value = '';
          showToast('Project drafted by AI', { type: 'success' });
        } catch (e) { showToast('Draft failed: ' + e.message, { type: 'error' }); }
        finally { btn.textContent = 'AI Draft'; btn.disabled = false; input.disabled = false; }
      }

      async function openIssueCreateModal() {
        hiReset();
        renderSkillPicker('hi-skills', [], []);
        document.getElementById('hi-skills').style.display = 'none';
        var defaultProdId = (currentProd && selectedProductId !== '__all__') ? selectedProductId : null;
        await Promise.all([hiPopulateStates(), hiPopulateProducts(defaultProdId), hiPopulateProjects()]);
        // Filter projects to selected product and default to first project
        if (defaultProdId) hiFilterProjects(null);
        if (currentProd && currentProd.project_ids && currentProd.project_ids.length > 0) {
          document.getElementById('hi-project').value = currentProd.project_ids[0];
        }
        document.getElementById('hi-modal').style.display = 'flex';
        setTimeout(function() { document.getElementById('hi-ai-draft-input').focus(); }, 100);
      }

      function closeIssueModal() { document.getElementById('hi-modal').style.display = 'none'; }

      async function handleIssueSubmit(e) {
        e.preventDefault();
        var d = hiCollectData();
        var skills = getSelectedSkills('hi-skills');
        var data = {
          title: d.title,
          description: d.description,
          state: d.state,
          priority: parseInt(d.priority) || 0,
          labels: (d.labels || '').split(',').map(function(l) { return l.trim(); }).filter(Boolean),
          product_id: d.product_id,
          project_id: d.project_id,
          propose_followups: d.propose_followups,
          plan_status: d.plan_status,
          skill_ids: skills.skill_ids, skill_group_ids: skills.skill_group_ids
        };
        try {
          var res = await fetch(API + '/issues', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) });
          if (!res.ok) { var err = await res.json().catch(function() { return {}; }); showToast('Save failed: ' + (err.error || 'unknown'), { type: 'error' }); return; }
          closeIssueModal();
          await refreshAfterMutation();
        } catch (err) { showToast('Save failed', { type: 'error' }); }
      }

    """
  end

  defp modal_project_js do
    ~S"""
      // ========== PROJECT CRUD ==========

      function openNewProjectModal() {
        document.getElementById('project-modal-title').textContent = 'New Project';
        document.getElementById('project-form-id').value = '';
        document.getElementById('project-form-name').value = '';
        document.getElementById('project-form-desc').value = '';
        document.getElementById('project-form-path').value = '';
        document.getElementById('project-form-repo').value = '';
        document.getElementById('project-form-labels').value = '';
        document.getElementById('project-form-priority').value = '0';
        document.getElementById('project-ai-draft-input').value = '';
        document.getElementById('project-form-submit').textContent = 'Create Project';
        openModal('project-modal');
        document.getElementById('project-ai-draft-input').focus();
      }

      function editProjectInline(id) {
        var p = allProjects.find(function(x) { return x.id === id; }); if (!p) return;
        document.getElementById('project-modal-title').textContent = 'Edit: ' + p.name;
        document.getElementById('project-form-id').value = p.id;
        document.getElementById('project-form-name').value = p.name || '';
        document.getElementById('project-form-desc').value = p.description || '';
        document.getElementById('project-form-path').value = p.path || '';
        document.getElementById('project-form-repo').value = p.repo_url || '';
        document.getElementById('project-form-labels').value = (p.tags || []).join(', ');
        document.getElementById('project-form-priority').value = (p.priority || 0).toString();
        document.getElementById('project-ai-draft-input').value = '';
        document.getElementById('project-form-submit').textContent = 'Save Changes';
        openModal('project-modal');
        document.getElementById('project-form-name').focus();
      }

      function closeProjectModal() { closeModal('project-modal'); }

      async function handleProjectSubmit(e) {
        e.preventDefault();
        var id = document.getElementById('project-form-id').value;
        var labelsStr = document.getElementById('project-form-labels').value;
        var tags = labelsStr ? labelsStr.split(',').map(function(t) { return t.trim(); }).filter(Boolean) : [];
        var payload = {
          name: document.getElementById('project-form-name').value,
          description: document.getElementById('project-form-desc').value,
          path: document.getElementById('project-form-path').value || null,
          repo_url: document.getElementById('project-form-repo').value || null,
          tags: tags,
          priority: parseInt(document.getElementById('project-form-priority').value) || 0
        };
        try {
          var res;
          if (id) res = await fetch(API + '/projects/' + id, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
          else res = await fetch(API + '/projects', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
          if (!res.ok) { var err = await res.json().catch(function() { return {}; }); showToast('Save failed: ' + (err.error || 'unknown'), { type: 'error' }); return; }
          closeModal('project-modal');
          showToast(id ? 'Project updated' : 'Project created', { type: 'success' });
          await loadProjects(); renderSidebar();
        } catch (err) { showToast('Save failed: ' + err.message, { type: 'error' }); }
      }

      async function deleteProjectInline(id) {
        var p = allProjects.find(function(x) { return x.id === id; }); if (!p) return;
        if (!confirm('Delete project "' + p.name + '" and all its issues?')) return;
        try {
          await fetch(API + '/projects/' + id, { method: 'DELETE' });
          showToast('Project deleted', { type: 'success' });
          await loadProjects(); renderSidebar();
        } catch (err) { showToast('Delete failed: ' + err.message, { type: 'error' }); }
      }

      async function cloneProject(id) {
        var p = allProjects.find(function(x) { return x.id === id; }); if (!p) return;
        if (!confirm('Clone repository for "' + p.name + '"?\n' + p.repo_url)) return;
        try {
          var res = await fetch(API + '/projects/' + id + '/clone', { method: 'POST' });
          var data = await res.json();
          if (res.ok) { showToast('Cloned to: ' + data.path, { type: 'success' }); await loadProjects(); renderSidebar(); }
          else { showToast('Clone failed: ' + (data.error || 'unknown'), { type: 'error' }); }
        } catch (err) { showToast('Clone failed: ' + err.message, { type: 'error' }); }
      }

      async function browseFolder(targetInputId) {
        try {
          var res = await fetch(API + '/browse-folder', { method: 'POST' });
          var data = await res.json();
          if (data.path) document.getElementById(targetInputId).value = data.path;
        } catch (err) { showToast('Failed to open folder dialog', { type: 'error' }); }
      }

    """
  end

  defp scan_import_js do
    ~S"""
      // Import / Scan
      var scannedCandidates = [];

      function openScanModal() {
        document.getElementById('scan-root-path').value = '';
        document.getElementById('scan-results').innerHTML = '';
        document.getElementById('import-btn').style.display = 'none';
        scannedCandidates = [];
        openModal('scan-modal');
      }

      function closeScanModal() { closeModal('scan-modal'); }

      async function scanDirectory() {
        var rootPath = document.getElementById('scan-root-path').value.trim(); if (!rootPath) return;
        var btn = document.getElementById('scan-btn');
        var results = document.getElementById('scan-results');
        var aiSummarize = document.getElementById('scan-ai-summarize').checked;
        btn.disabled = true; btn.textContent = 'Scanning...';
        results.innerHTML = '<div style="color:var(--text-muted)">' + (aiSummarize ? 'Scanning and running AI analysis...' : 'Scanning directories...') + '</div>';
        try {
          var res = await fetch(API + '/projects/scan', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ root_path: rootPath, git_pull: document.getElementById('scan-git-pull').checked, ai_summarize: aiSummarize }) });
          var data = await res.json();
          if (!res.ok) { results.innerHTML = '<div style="color:var(--red)">Error: ' + esc(data.error || 'unknown') + '</div>'; return; }
          scannedCandidates = data.candidates || [];
          var existingPaths = new Set(allProjects.map(function(p) { return p.path; }).filter(Boolean));
          scannedCandidates.forEach(function(c) { c._selected = !existingPaths.has(c.path); c._existing = existingPaths.has(c.path); });
          renderScanResults();
        } catch (err) { results.innerHTML = '<div style="color:var(--red)">Scan failed: ' + esc(err.message) + '</div>'; }
        finally { btn.disabled = false; btn.textContent = 'Scan'; }
      }

      function renderScanResults() {
        var results = document.getElementById('scan-results');
        if (scannedCandidates.length === 0) { results.innerHTML = '<div style="color:var(--text-muted)">No projects found.</div>'; document.getElementById('import-btn').style.display = 'none'; return; }
        var selectedCount = scannedCandidates.filter(function(c) { return c._selected; }).length;
        var selectable = scannedCandidates.filter(function(c) { return !c._existing; });
        var html = '<div style="margin-bottom:8px;display:flex;justify-content:space-between;align-items:center"><span style="font-size:0.85rem;color:var(--text-secondary)">Found ' + scannedCandidates.length + ' (' + selectedCount + ' selected)</span>' +
          (selectable.length > 0 ? '<label style="font-size:0.8rem;color:var(--text-muted);cursor:pointer"><input type="checkbox" ' + (selectedCount === selectable.length ? 'checked' : '') + ' onchange="toggleAllScan(this.checked)"> Select all</label>' : '') + '</div>';
        html += scannedCandidates.map(function(c, i) {
          var disabled = c._existing; var badge = disabled ? '<span style="font-size:0.7rem;background:var(--bg-tertiary);color:var(--text-muted);padding:2px 6px;border-radius:4px;margin-left:8px">already imported</span>' : '';
          var tagsHtml = (c.tags && c.tags.length) ? '<div style="display:flex;flex-wrap:wrap;gap:4px;margin-top:4px">' + c.tags.map(function(t) { return '<span style="font-size:0.65rem;padding:1px 6px;border-radius:8px;background:rgba(88,166,255,0.1);color:var(--accent)">' + esc(t) + '</span>'; }).join('') + '</div>' : '';
          return '<div class="scan-card" style="' + (disabled ? 'opacity:0.5' : '') + '"><div style="display:flex;align-items:flex-start;gap:10px"><input type="checkbox" ' + (c._selected ? 'checked' : '') + ' ' + (disabled ? 'disabled' : '') + ' onchange="toggleScanItem(' + i + ',this.checked)" style="margin-top:4px"><div style="flex:1;min-width:0"><strong style="font-size:0.9rem">' + esc(c.name) + '</strong>' + badge + (c.description ? '<div style="font-size:0.8rem;color:var(--text-secondary);margin-top:2px">' + esc(c.description) + '</div>' : '') + tagsHtml + '<div style="font-size:0.75rem;color:var(--text-muted);margin-top:4px">\uD83D\uDCC1 ' + esc(c.path) + '</div></div></div></div>';
        }).join('');
        results.innerHTML = html;
        document.getElementById('import-btn').style.display = selectedCount > 0 ? '' : 'none';
        document.getElementById('import-btn').textContent = 'Import ' + selectedCount + ' Project' + (selectedCount !== 1 ? 's' : '');
      }

      function toggleScanItem(idx, checked) { scannedCandidates[idx]._selected = checked; renderScanResults(); }
      function toggleAllScan(checked) { scannedCandidates.forEach(function(c) { if (!c._existing) c._selected = checked; }); renderScanResults(); }

      async function importScanned() {
        var toImport = scannedCandidates.filter(function(c) { return c._selected && !c._existing; }).map(function(c) { return { name: c.name, slug: c.slug, path: c.path, description: c.description, repo_url: c.repo_url, tags: c.tags || [] }; });
        if (toImport.length === 0) return;
        var btn = document.getElementById('import-btn'); btn.disabled = true; btn.textContent = 'Importing...';
        try {
          var res = await fetch(API + '/projects/import', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ projects: toImport }) });
          if (res.ok) { closeScanModal(); showToast('Imported ' + toImport.length + ' project' + (toImport.length !== 1 ? 's' : ''), { type: 'success' }); await loadProjects(); renderSidebar(); }
          else { var err = await res.json().catch(function() { return {}; }); showToast('Import failed: ' + (err.error || 'unknown'), { type: 'error' }); }
        } catch (err) { showToast('Import failed: ' + err.message, { type: 'error' }); }
        finally { btn.disabled = false; }
      }

    """
  end

  defp keyboard_shortcuts_js do
    ~S"""
      // ========== KEYBOARD SHORTCUTS ==========

      document.addEventListener('keydown', function(e) {
        var inInput = ['INPUT','TEXTAREA','SELECT'].includes(document.activeElement.tagName);
        if (e.key === 'Escape') {
          closeProdModal(); closeFeatureModal(); closeGenerateModal(); closeCodeReviewModal();
          closeGenDefModal(); closeProductTaskModal(); closeDetailModal(); closeIssueModal();
          closeProjectModal(); closeScanModal();
        }
        if (inInput) return;
        if (e.key === '1') { e.preventDefault(); switchTab('spec'); }
        if (e.key === '2') { e.preventDefault(); switchTab('issues'); }
        if (e.key === '3') { e.preventDefault(); switchTab('activity'); }
        if (e.key === 'n' && !e.ctrlKey && !e.metaKey) { e.preventDefault(); openIssueCreateModal(); }
        if (e.key === '?') showToast('1/2/3=Tabs  n=New Issue  Esc=Close', { duration: 3000 });
      });

    """
  end

  defp auto_refresh_js do
    ~S"""
      // ========== AUTO-REFRESH ==========

      async function refreshCurrentView() {
        if (draggedCard) return;
        await loadBoardSnapshot();
        renderSidebar();
        if (activeTab === 'issues') { renderKanban(); }
        if (activeTab === 'activity' && selectedProductId && selectedProductId !== '__all__') { await loadActivity(); renderActivity(); }
        if (activeTab === 'spec' && currentProd) {
          var res = await fetch(API + '/products/' + currentProd.id);
          if (res.ok) { currentProd = await res.json(); renderSpecSheet(); }
        }
      }

      setInterval(refreshCurrentView, 10000);

      // Refresh immediately when tab regains focus
      document.addEventListener('visibilitychange', function() {
        if (!document.hidden) refreshCurrentView();
      });

      // ========== START ==========
      init();
    """
  end
end

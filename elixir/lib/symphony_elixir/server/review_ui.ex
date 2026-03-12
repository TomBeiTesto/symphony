defmodule SymphonyElixir.Server.ReviewUI do
  @moduledoc """
  Product feature spec sheet view.

  Visualizes products as a spec-sheet: category ring summaries at top,
  collapsible feature cards grouped by category, with project tags and
  overall status per feature. Includes AI-assisted analysis actions.
  """

  @doc "Render the product spec sheet HTML page."
  @spec render() :: String.t()
  def render do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Symphony Products</title>
      <style>
    #{css()}
      </style>
    </head>
    <body>
      <header class="topbar">
        <div class="topbar-left">
          <nav class="breadcrumb"><a href="/board">Board</a><span class="sep">/</span></nav>
          <h1>Products</h1>
          <select id="product-select" class="prod-select" onchange="selectProduct()">
            <option value="">Select product...</option>
          </select>
        </div>
        <div class="topbar-right">
          <button class="btn btn-ghost" onclick="openNewProductModal()">+ New Product</button>
        </div>
      </header>

      <main class="main" id="main">
        <div class="empty-state" id="empty-state">
          <div class="empty-icon">
            <svg viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/></svg>
          </div>
          <h2>Product Spec Sheets</h2>
          <p>Create a product to group projects and track feature completeness across them.</p>
          <button class="btn btn-primary" onclick="openNewProductModal()">Create Product</button>
        </div>

        <div class="spec-sheet" id="spec-sheet" style="display:none">
          <div id="product-header"></div>
          <div id="category-rings"></div>
          <div id="category-sections"></div>
          <div id="inline-gap-section"></div>
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

      <!-- Add/Edit Feature Modal -->
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
            <label>Category
              <input type="text" id="feature-category" placeholder="e.g. Security, Data Pipeline, Infrastructure" list="category-list">
              <datalist id="category-list"></datalist>
            </label>
            <label>Dependencies
              <div id="feature-deps-checklist" class="project-checklist" style="max-height:150px"></div>
            </label>
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
            <label>Agent Skills <button type="button" class="skill-picker-toggle" onclick="toggleSkillPicker('generate-skills')">select skills...</button></label>
            <div class="skill-picker" id="generate-skills" style="display:none"></div>
            <div class="ai-hint">This creates an issue on the board. An agent will pick it up, analyze the projects, and propose features as follow-up issues.</div>
          </div>
          <div class="modal-footer">
            <button class="btn btn-ghost" onclick="closeGenerateModal()">Cancel</button>
            <button class="btn btn-primary" id="generate-btn" onclick="generateFeatures()">Create Agent Task</button>
          </div>
        </div>
      </div>

      <!-- Code Review Modal -->
      <div class="modal-overlay" id="code-review-modal" style="display:none">
        <div class="modal">
          <div class="modal-header">
            <h2>Code Review</h2>
            <button class="modal-close" onclick="closeCodeReviewModal()">&times;</button>
          </div>
          <div class="modal-body">
            <label>Focus areas (optional)
              <textarea id="review-focus" rows="4" placeholder="e.g. Security vulnerabilities, error handling, test coverage, performance bottlenecks..."></textarea>
            </label>
            <label>Agent Skills <button type="button" class="skill-picker-toggle" onclick="toggleSkillPicker('review-skills')">select skills...</button></label>
            <div class="skill-picker" id="review-skills" style="display:none"></div>
            <div class="ai-hint">This creates an issue on the board. An agent will review all project codebases and propose follow-up issues for findings.</div>
          </div>
          <div class="modal-footer">
            <button class="btn btn-ghost" onclick="closeCodeReviewModal()">Cancel</button>
            <button class="btn btn-primary" id="code-review-btn" onclick="startCodeReview()">Start Code Review</button>
          </div>
        </div>
      </div>

      <!-- Generate Definition Modal -->
      <div class="modal-overlay" id="gendef-modal" style="display:none">
        <div class="modal">
          <div class="modal-header">
            <h2>Generate Product Definition</h2>
            <button class="modal-close" onclick="closeGenDefModal()">&times;</button>
          </div>
          <div class="modal-body">
            <label>Additional context (optional)
              <textarea id="gendef-context" rows="3" placeholder="e.g. This product focuses on our B2C platform, specifically the async messaging layer..."></textarea>
            </label>
            <label>Agent Skills <button type="button" class="skill-picker-toggle" onclick="toggleSkillPicker('gendef-skills')">select skills...</button></label>
            <div class="skill-picker" id="gendef-skills" style="display:none"></div>
            <div class="ai-hint">An agent will analyze the selected projects and generate a product name, description, and scope definition.</div>
          </div>
          <div class="modal-footer">
            <button class="btn btn-ghost" onclick="closeGenDefModal()">Cancel</button>
            <button class="btn btn-primary" id="gendef-btn" onclick="generateDefinition()">Generate Definition</button>
          </div>
        </div>
      </div>

      <!-- Product Task Modal -->
      <div class="modal-overlay" id="product-task-modal" style="display:none">
        <div class="modal">
          <div class="modal-header">
            <h2>Create Product Task</h2>
            <button class="modal-close" onclick="closeProductTaskModal()">&times;</button>
          </div>
          <div class="modal-body">
            <label>Task title
              <input type="text" id="ptask-title" placeholder="e.g. Generate runbook, Create architecture diagram, Write API docs...">
            </label>
            <label>Description / prompt
              <textarea id="ptask-prompt" rows="5" placeholder="Describe what the agent should do. It will have access to all project codebases in this product."></textarea>
            </label>
            <label>Priority
              <select id="ptask-priority">
                <option value="1">High</option>
                <option value="2" selected>Medium</option>
                <option value="3">Low</option>
              </select>
            </label>
            <label>Agent Skills <button type="button" class="skill-picker-toggle" onclick="toggleSkillPicker('ptask-skills')">select skills...</button></label>
            <div class="skill-picker" id="ptask-skills" style="display:none"></div>
            <div class="ai-hint">Creates an issue on the board scoped to this product. The agent will have access to all project codebases and will report findings as follow-up issues.</div>
          </div>
          <div class="modal-footer">
            <button class="btn btn-ghost" onclick="closeProductTaskModal()">Cancel</button>
            <button class="btn btn-primary" id="ptask-btn" onclick="createProductTask()">Create Task</button>
          </div>
        </div>
      </div>

      <!-- Feature Detail Modal (per-project statuses) -->
      <div class="modal-overlay" id="detail-modal" style="display:none">
        <div class="modal">
          <div class="modal-header">
            <h2 id="detail-modal-title">Feature Details</h2>
            <button class="modal-close" onclick="closeDetailModal()">&times;</button>
          </div>
          <div class="modal-body" id="detail-modal-body"></div>
          <div class="modal-footer">
            <button class="btn btn-ghost" onclick="closeDetailModal()">Close</button>
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

    UIHelpers.base_css() <>
      UIHelpers.topbar_css() <>
      UIHelpers.button_css() <>
      UIHelpers.form_css() <>
      UIHelpers.modal_css() <>
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

      /* Spec Sheet */
      .spec-sheet { max-width: 1000px; margin: 0 auto; }

      /* Product Header */
      .product-header-card {
        background: var(--bg-secondary);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        padding: 20px 24px;
        margin-bottom: 20px;
      }
      .product-header-top {
        display: flex;
        justify-content: space-between;
        align-items: flex-start;
        gap: 16px;
        margin-bottom: 12px;
      }
      .product-header-top h2 {
        font-size: 1.3rem;
        font-weight: 700;
        margin: 0;
      }
      .product-desc {
        color: var(--text-secondary);
        font-size: 0.9rem;
        line-height: 1.5;
        margin-bottom: 12px;
      }
      .product-actions {
        display: flex;
        gap: 8px;
        flex-shrink: 0;
      }
      .project-tags {
        display: flex;
        flex-wrap: wrap;
        gap: 6px;
      }
      .project-tag {
        display: inline-flex;
        align-items: center;
        gap: 4px;
        padding: 3px 10px;
        background: var(--bg-tertiary);
        border: 1px solid var(--border);
        border-radius: 12px;
        font-size: 0.75rem;
        color: var(--text-secondary);
      }
      .project-tag-dot {
        width: 6px;
        height: 6px;
        border-radius: 50%;
        background: var(--accent);
      }

      /* Overall progress bar */
      .overall-bar {
        display: flex;
        align-items: center;
        gap: 12px;
        margin-top: 16px;
        padding-top: 12px;
        border-top: 1px solid var(--border-light);
      }
      .overall-label {
        font-size: 0.8rem;
        color: var(--text-muted);
        font-weight: 500;
        white-space: nowrap;
      }
      .overall-track {
        flex: 1;
        height: 6px;
        background: var(--bg-tertiary);
        border-radius: 3px;
        overflow: hidden;
      }
      .overall-fill {
        height: 100%;
        border-radius: 3px;
        transition: width 0.3s ease;
      }
      .overall-value {
        font-size: 1rem;
        font-weight: 700;
        min-width: 45px;
        text-align: right;
      }

      /* Category Rings */
      .rings-row {
        display: flex;
        gap: 16px;
        margin-bottom: 24px;
        overflow-x: auto;
        padding-bottom: 4px;
      }
      .ring-card {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 6px;
        padding: 14px 18px;
        background: var(--bg-secondary);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        min-width: 110px;
        cursor: pointer;
        transition: all var(--transition);
      }
      .ring-card:hover {
        border-color: var(--accent);
        background: var(--bg-hover);
      }
      .ring-card.active {
        border-color: var(--accent);
        box-shadow: 0 0 0 1px var(--accent);
      }
      .ring-svg { width: 56px; height: 56px; }
      .ring-label {
        font-size: 0.72rem;
        color: var(--text-muted);
        font-weight: 500;
        text-align: center;
        max-width: 100px;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .ring-count {
        font-size: 0.65rem;
        color: var(--text-muted);
      }

      /* Category Sections */
      .category-section {
        margin-bottom: 16px;
      }
      .category-header {
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 10px 0;
        cursor: pointer;
        user-select: none;
      }
      .category-header:hover .category-title { color: var(--text-primary); }
      .category-chevron {
        font-size: 0.7rem;
        color: var(--text-muted);
        transition: transform 0.2s;
        width: 16px;
        text-align: center;
      }
      .category-chevron.collapsed { transform: rotate(-90deg); }
      .category-title {
        font-size: 0.9rem;
        font-weight: 600;
        color: var(--text-secondary);
        transition: color var(--transition);
      }
      .category-stats {
        font-size: 0.72rem;
        color: var(--text-muted);
        margin-left: auto;
      }
      .category-body { }
      .category-body.collapsed { display: none; }

      /* Feature Cards */
      .feature-card {
        background: var(--bg-secondary);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        padding: 14px 18px;
        margin-bottom: 8px;
        transition: border-color var(--transition);
      }
      .feature-card:hover {
        border-color: var(--border-light);
      }
      .feature-card-top {
        display: flex;
        align-items: flex-start;
        gap: 12px;
      }
      .feature-status-badge {
        display: inline-flex;
        align-items: center;
        gap: 5px;
        padding: 3px 10px;
        border-radius: 12px;
        font-size: 0.72rem;
        font-weight: 600;
        white-space: nowrap;
        flex-shrink: 0;
      }
      .badge-done { background: rgba(63,185,80,0.15); color: var(--green); }
      .badge-partial { background: rgba(210,153,34,0.15); color: var(--yellow); }
      .badge-in_progress { background: rgba(88,166,255,0.15); color: var(--accent); }
      .badge-planned { background: rgba(210,153,34,0.1); color: var(--yellow); }
      .badge-missing { background: rgba(248,81,73,0.1); color: var(--red); }
      .badge-n_a { background: rgba(72,79,88,0.2); color: var(--text-muted); }

      .feature-info { flex: 1; min-width: 0; }
      .feature-name {
        font-size: 0.9rem;
        font-weight: 600;
        color: var(--text-primary);
      }
      .feature-desc {
        font-size: 0.8rem;
        color: var(--text-muted);
        line-height: 1.4;
        margin-top: 4px;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }
      .feature-meta {
        display: flex;
        align-items: center;
        gap: 8px;
        margin-top: 8px;
        flex-wrap: wrap;
      }
      .feature-project-tag {
        display: inline-flex;
        align-items: center;
        padding: 2px 8px;
        background: var(--bg-tertiary);
        border-radius: 10px;
        font-size: 0.68rem;
        color: var(--text-muted);
      }
      .feature-actions {
        display: flex;
        gap: 4px;
        flex-shrink: 0;
        opacity: 0;
        transition: opacity var(--transition);
      }
      .feature-card:hover .feature-actions { opacity: 1; }
      .feature-action-btn {
        background: none;
        border: none;
        color: var(--text-muted);
        cursor: pointer;
        padding: 4px 6px;
        font-size: 0.75rem;
        border-radius: 4px;
      }
      .feature-action-btn:hover { color: var(--text-primary); background: var(--bg-hover); }

      .verify-btn {
        background: rgba(188,140,255,0.1);
        border: 1px solid rgba(188,140,255,0.2);
        color: var(--purple);
        padding: 2px 8px;
        border-radius: 4px;
        font-size: 0.68rem;
        cursor: pointer;
        transition: all var(--transition);
      }
      .verify-btn:hover {
        background: rgba(188,140,255,0.25);
        border-color: var(--purple);
      }
      .verify-btn:disabled { opacity: 0.5; cursor: not-allowed; }

      .gap-warning {
        display: inline-flex;
        align-items: center;
        gap: 4px;
        font-size: 0.68rem;
        color: var(--yellow);
        margin-left: auto;
      }

      /* Add feature button at bottom of sections */
      .add-feature-btn {
        background: none;
        border: 1px dashed var(--border);
        color: var(--text-muted);
        padding: 10px 16px;
        border-radius: var(--radius-sm);
        cursor: pointer;
        font-size: 0.8rem;
        transition: all var(--transition);
        width: 100%;
        text-align: center;
        margin-top: 4px;
      }
      .add-feature-btn:hover {
        border-color: var(--accent);
        color: var(--accent);
        background: rgba(88,166,255,0.05);
      }

      /* Modals */
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

      /* Detail modal per-project statuses */
      .detail-project-row {
        display: flex;
        align-items: center;
        gap: 12px;
        padding: 10px 12px;
        background: var(--bg-tertiary);
        border: 1px solid var(--border);
        border-radius: var(--radius-sm);
        margin-bottom: 6px;
      }
      .detail-project-name {
        flex: 1;
        font-size: 0.85rem;
        font-weight: 500;
      }
      .detail-status-btn {
        padding: 4px 12px;
        border-radius: 12px;
        border: 1px solid var(--border);
        background: var(--bg-secondary);
        color: var(--text-secondary);
        font-size: 0.72rem;
        font-weight: 600;
        cursor: pointer;
        transition: all var(--transition);
      }
      .detail-status-btn:hover { border-color: var(--accent); }

      /* Dependencies */
      .feature-deps {
        display: flex;
        align-items: center;
        gap: 4px;
        margin-top: 6px;
        font-size: 0.72rem;
        color: var(--text-muted);
      }
      .feature-deps-label { color: var(--purple); font-weight: 500; }
      .dep-tag {
        padding: 1px 6px;
        background: rgba(188,140,255,0.1);
        border: 1px solid rgba(188,140,255,0.15);
        border-radius: 8px;
        font-size: 0.68rem;
        color: var(--purple);
        cursor: pointer;
      }
      .dep-tag:hover { background: rgba(188,140,255,0.2); }
      .dep-blocked {
        color: var(--red);
        font-size: 0.72rem;
        font-weight: 500;
        margin-left: 4px;
      }

      /* History / last verified */
      .feature-history {
        font-size: 0.68rem;
        color: var(--text-muted);
        margin-top: 4px;
      }
      .history-source { color: var(--accent); }

      /* Inline gap section */
      .gap-section {
        margin-top: 24px;
        border: 1px solid rgba(248,81,73,0.2);
        border-radius: var(--radius);
        background: rgba(248,81,73,0.03);
      }
      .gap-section-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 12px 18px;
        cursor: pointer;
        user-select: none;
      }
      .gap-section-title {
        font-size: 0.9rem;
        font-weight: 600;
        color: var(--red);
      }
      .gap-section-count {
        font-size: 0.75rem;
        color: var(--text-muted);
      }
      .gap-section-body { padding: 0 18px 14px; }
      .gap-row {
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 8px 12px;
        background: var(--bg-secondary);
        border: 1px solid var(--border);
        border-radius: var(--radius-sm);
        margin-bottom: 6px;
      }
      .gap-row-feature { font-weight: 600; font-size: 0.82rem; flex: 1; }
      .gap-row-project { font-size: 0.75rem; color: var(--text-muted); }
      .gap-row-action {
        padding: 3px 8px;
        border-radius: 4px;
        border: 1px solid var(--border);
        background: var(--bg-tertiary);
        color: var(--text-secondary);
        font-size: 0.7rem;
        cursor: pointer;
      }
      .gap-row-action:hover { border-color: var(--accent); color: var(--accent); }

      /* AI hint text */
      .ai-hint { font-size: 0.75rem; color: var(--text-muted); margin-top: 8px; font-style: italic; }

      /* Skill Picker */
      .skill-picker {
        max-height: 200px; overflow-y: auto;
        border: 1px solid var(--border); border-radius: 6px;
        padding: 8px; margin-top: 4px;
        background: var(--bg-secondary);
      }
      .skill-picker-section { margin-bottom: 8px; }
      .skill-picker-section strong { display: block; font-size: 0.7rem; text-transform: uppercase; color: var(--text-muted); margin-bottom: 4px; letter-spacing: 0.5px; }
      .skill-pick-item { display: flex; align-items: center; gap: 6px; padding: 3px 0; font-size: 0.8rem; cursor: pointer; }
      .skill-pick-item input { margin: 0; cursor: pointer; }
      .skill-pick-name { color: var(--text-primary); }
      .skill-pick-count { color: var(--text-muted); font-size: 0.7rem; }
      .skill-pick-empty { font-size: 0.8rem; color: var(--text-muted); padding: 8px; text-align: center; }
      .skill-picker-toggle { font-size: 0.75rem; color: var(--accent); cursor: pointer; margin-top: 4px; border: none; background: none; padding: 0; }
      .skill-picker-toggle:hover { text-decoration: underline; }

      /* Spinner */
      .spinner {
        display: inline-block; width: 14px; height: 14px;
        border: 2px solid var(--text-muted); border-top-color: transparent;
        border-radius: 50%; animation: spin 0.8s linear infinite;
        vertical-align: middle; margin-right: 6px;
      }
      @keyframes spin { to { transform: rotate(360deg); } }
      @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.5; } }
      """
  end

  defp js do
    SymphonyElixir.Server.UIHelpers.esc_js() <>
      ~S"""

      const API = '/board/api';
      let allProducts = [];
      let allProjects = [];
      let allSkills = [];
      let allSkillGroups = [];
      let currentProd = null;
      let collapsedCategories = {};
      let activeFilter = null;
      let detailHistoryExpanded = {};

      const STATUS_ORDER = ['missing', 'planned', 'in_progress', 'done', 'n_a'];
      const STATUS_LABELS = {
        done: 'Done', partial: 'Partial', in_progress: 'In Progress',
        planned: 'Planned', missing: 'Missing', n_a: 'N/A'
      };
      const STATUS_ICONS = {
        done: '\u2705', partial: '\uD83D\uDFE1', in_progress: '\uD83D\uDD35',
        planned: '\uD83D\uDFE0', missing: '\uD83D\uDD34', n_a: '\u2B1C'
      };

      // --- Init & Data Loading ---

      async function init() {
        await Promise.all([loadProducts(), loadProjects(), loadSkills()]);
        populateProdSelect();
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

      async function loadSkills() {
        try {
          var [sRes, gRes] = await Promise.all([
            fetch(API + '/skills'),
            fetch(API + '/skill-groups')
          ]);
          var sData = await sRes.json();
          var gData = await gRes.json();
          allSkills = (sData.skills || []).sort(function(a, b) { return a.name.localeCompare(b.name); });
          allSkillGroups = (gData.skill_groups || []).sort(function(a, b) { return a.name.localeCompare(b.name); });
        } catch (e) {
          allSkills = [];
          allSkillGroups = [];
        }
      }

      function renderSkillPicker(containerId, selectedSkillIds, selectedGroupIds) {
        var el = document.getElementById(containerId);
        if (!el) return;
        var html = '';

        if (allSkillGroups.length > 0) {
          html += '<div class="skill-picker-section"><strong>Skill Groups</strong>';
          allSkillGroups.forEach(function(g) {
            var checked = selectedGroupIds.indexOf(g.id) >= 0 ? ' checked' : '';
            html += '<label class="skill-pick-item"><input type="checkbox" value="' + g.id + '" data-type="group"' + checked + '>' +
              '<span class="skill-pick-name">' + esc(g.name) + '</span>' +
              '<span class="skill-pick-count">(' + (g.skill_ids || []).length + ' skills)</span></label>';
          });
          html += '</div>';
        }

        if (allSkills.length > 0) {
          var categories = {};
          allSkills.forEach(function(s) {
            var cat = s.category || 'custom';
            if (!categories[cat]) categories[cat] = [];
            categories[cat].push(s);
          });
          Object.keys(categories).sort().forEach(function(cat) {
            html += '<div class="skill-picker-section"><strong>' + esc(cat.charAt(0).toUpperCase() + cat.slice(1)) + '</strong>';
            categories[cat].forEach(function(s) {
              var checked = selectedSkillIds.indexOf(s.id) >= 0 ? ' checked' : '';
              html += '<label class="skill-pick-item"><input type="checkbox" value="' + s.id + '" data-type="skill"' + checked + '>' +
                '<span class="skill-pick-name">' + esc(s.name) + '</span></label>';
            });
            html += '</div>';
          });
        }

        if (!html) html = '<div class="skill-pick-empty">No skills available. Create skills in the Skills library.</div>';
        el.innerHTML = html;
      }

      function getSelectedSkills(containerId) {
        var el = document.getElementById(containerId);
        if (!el) return { skill_ids: [], skill_group_ids: [] };
        var skillIds = [], groupIds = [];
        el.querySelectorAll('input[type=checkbox]:checked').forEach(function(cb) {
          if (cb.dataset.type === 'group') groupIds.push(cb.value);
          else skillIds.push(cb.value);
        });
        return { skill_ids: skillIds, skill_group_ids: groupIds };
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
          document.getElementById('spec-sheet').style.display = 'none';
          return;
        }
        var res = await fetch(API + '/products/' + id);
        currentProd = await res.json();
        activeFilter = null;
        loadCollapseState();
        document.getElementById('empty-state').style.display = 'none';
        document.getElementById('spec-sheet').style.display = '';
        renderSpecSheet();
      }

      function getProjectById(id) {
        return allProjects.find(function(p) { return p.id === id; }) || { id: id, name: id };
      }

      // --- Status Computation ---

      function computeOverallStatus(statuses, projectIds) {
        // Use the feature's own project keys if no explicit list provided
        var pids = projectIds || Object.keys(statuses || {});
        var applicable = pids.filter(function(pid) {
          return (statuses[pid] || 'missing') !== 'n_a';
        });
        if (applicable.length === 0) return 'n_a';
        var vals = applicable.map(function(pid) { return statuses[pid] || 'missing'; });
        if (vals.every(function(v) { return v === 'done'; })) return 'done';
        if (vals.some(function(v) { return v === 'in_progress'; })) return 'in_progress';
        if (vals.some(function(v) { return v === 'done'; })) return 'partial';
        if (vals.some(function(v) { return v === 'planned'; })) return 'planned';
        return 'missing';
      }

      function getApplicableProjects(feature, projectIds) {
        // Use the feature's own project keys if no explicit list provided
        var pids = projectIds || Object.keys(feature.statuses || {});
        return pids.filter(function(pid) {
          return (feature.statuses[pid] || 'missing') !== 'n_a';
        });
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
          app.forEach(function(pid) {
            total++;
            if (f.statuses[pid] === 'done') done++;
          });
        });
        return { total: total, done: done, pct: total > 0 ? Math.round(done / total * 100) : 100 };
      }

      function timeAgo(isoStr) {
        if (!isoStr) return '';
        var d = new Date(isoStr);
        var now = new Date();
        var secs = Math.floor((now - d) / 1000);
        if (secs < 60) return 'just now';
        var mins = Math.floor(secs / 60);
        if (mins < 60) return mins + 'm ago';
        var hrs = Math.floor(mins / 60);
        if (hrs < 24) return hrs + 'h ago';
        var days = Math.floor(hrs / 24);
        if (days < 30) return days + 'd ago';
        return d.toLocaleDateString();
      }

      function getCategories(features) {
        var cats = {};
        features.forEach(function(f) {
          var cat = f.category || 'Uncategorized';
          if (!cats[cat]) cats[cat] = [];
          cats[cat].push(f);
        });
        // Sort: named categories first (alphabetical), Uncategorized last
        var keys = Object.keys(cats).sort(function(a, b) {
          if (a === 'Uncategorized') return 1;
          if (b === 'Uncategorized') return -1;
          return a.localeCompare(b);
        });
        return keys.map(function(k) { return { name: k, features: cats[k] }; });
      }

      // --- SVG Donut Ring ---

      function renderDonutSVG(pct, color) {
        var r = 22, c = 28, stroke = 5;
        var circ = 2 * Math.PI * r;
        var offset = circ - (pct / 100) * circ;
        return '<svg class="ring-svg" viewBox="0 0 56 56">' +
          '<circle cx="' + c + '" cy="' + c + '" r="' + r + '" fill="none" stroke="var(--bg-tertiary)" stroke-width="' + stroke + '"/>' +
          '<circle cx="' + c + '" cy="' + c + '" r="' + r + '" fill="none" stroke="' + color + '" stroke-width="' + stroke + '" ' +
            'stroke-dasharray="' + circ.toFixed(1) + '" stroke-dashoffset="' + offset.toFixed(1) + '" ' +
            'stroke-linecap="round" transform="rotate(-90 ' + c + ' ' + c + ')" style="transition:stroke-dashoffset 0.4s"/>' +
          '<text x="' + c + '" y="' + c + '" text-anchor="middle" dominant-baseline="central" fill="' + color + '" font-size="13" font-weight="700">' + pct + '%</text>' +
        '</svg>';
      }

      // --- Main Render ---

      function renderSpecSheet() {
        if (!currentProd) return;
        var prod = currentProd;
        var pids = prod.project_ids || [];
        var features = prod.features || [];

        renderProductHeader(prod, pids, features);
        renderCategoryRings(prod, pids, features);
        renderCategorySections(prod, pids, features);
        renderInlineGapSection(prod, pids, features);
        updateCategoryDatalist(features);
      }

      function renderProductHeader(prod, pids, features) {
        var el = document.getElementById('product-header');

        // Overall stats — use each feature's own participating projects
        var total = 0, done = 0;
        features.forEach(function(f) {
          var featurePids = Object.keys(f.statuses || {});
          featurePids.forEach(function(pid) {
            var s = f.statuses[pid];
            if (s !== 'n_a') { total++; if (s === 'done') done++; }
          });
        });
        var pct = total > 0 ? Math.round(done / total * 100) : 100;

        var html = '<div class="product-header-card">' +
          '<div class="product-header-top">' +
            '<h2>' + esc(prod.name) + '</h2>' +
            '<div class="product-actions">' +
              '<button class="btn btn-accent btn-sm" onclick="analyzeExistingFeatures()" id="analyze-existing-btn">Analyze Features</button>' +
              '<button class="btn btn-accent btn-sm" onclick="analyzeGaps()" id="analyze-gaps-btn">Analyze Gaps</button>' +
              '<button class="btn btn-accent btn-sm" onclick="openCodeReviewModal()">Code Review</button>' +
              '<button class="btn btn-accent btn-sm" onclick="openGenerateModal()">Generate Features</button>' +
              '<button class="btn btn-accent btn-sm" onclick="openGenDefModal()">Generate Definition</button>' +
              '<button class="btn btn-primary btn-sm" onclick="openProductTaskModal()">+ Create Task</button>' +
              '<button class="btn btn-ghost btn-sm" onclick="openEditProductModal()">Edit</button>' +
              '<button class="btn btn-danger btn-sm" onclick="deleteCurrentProduct()">Delete</button>' +
            '</div>' +
          '</div>';

        if (prod.description) {
          html += '<div class="product-desc">' + esc(prod.description) + '</div>';
        }

        // Project tags
        if (pids.length > 0) {
          html += '<div class="project-tags">';
          pids.forEach(function(pid) {
            var p = getProjectById(pid);
            html += '<span class="project-tag"><span class="project-tag-dot"></span>' + esc(p.name) + '</span>';
          });
          html += '</div>';
        }

        // Overall progress bar
        html += '<div class="overall-bar">' +
          '<span class="overall-label">Overall Completeness</span>' +
          '<div class="overall-track"><div class="overall-fill" style="width:' + pct + '%;background:' + scoreColor(pct) + '"></div></div>' +
          '<span class="overall-value" style="color:' + scoreColor(pct) + '">' + pct + '%</span>' +
        '</div>';

        html += '</div>';
        el.innerHTML = html;
      }

      function renderCategoryRings(prod, pids, features) {
        var el = document.getElementById('category-rings');
        var categories = getCategories(features);

        if (categories.length <= 1 && features.length < 5) {
          el.innerHTML = '';
          return;
        }

        var html = '<div class="rings-row">';
        categories.forEach(function(cat) {
          var stats = computeCategoryStats(cat.features);
          var color = scoreColor(stats.pct);
          var isActive = activeFilter === cat.name;
          html += '<div class="ring-card' + (isActive ? ' active' : '') + '" onclick="filterCategory(\'' + esc(cat.name).replace(/'/g, "\\'") + '\')">' +
            renderDonutSVG(stats.pct, color) +
            '<div class="ring-label" title="' + esc(cat.name) + '">' + esc(cat.name) + '</div>' +
            '<div class="ring-count">' + cat.features.length + ' feature' + (cat.features.length !== 1 ? 's' : '') + '</div>' +
          '</div>';
        });
        html += '</div>';
        el.innerHTML = html;
      }

      function renderCategorySections(prod, pids, features) {
        var el = document.getElementById('category-sections');
        var categories = getCategories(features);

        var html = '';
        categories.forEach(function(cat) {
          if (activeFilter && activeFilter !== cat.name) return;

          var stats = computeCategoryStats(cat.features);
          var collapsed = collapsedCategories[cat.name];
          var catId = 'cat-' + cat.name.replace(/\W/g, '_');

          html += '<div class="category-section">';

          // Category header
          var doneCount = cat.features.filter(function(f) {
            return computeOverallStatus(f.statuses) === 'done';
          }).length;

          html += '<div class="category-header" onclick="toggleCategory(\'' + esc(cat.name).replace(/'/g, "\\'") + '\')">' +
            '<span class="category-chevron' + (collapsed ? ' collapsed' : '') + '">\u25BC</span>' +
            '<span class="category-title">' + esc(cat.name) + '</span>' +
            '<span class="category-stats">' + doneCount + '/' + cat.features.length + ' done \u00b7 ' + stats.pct + '%</span>' +
          '</div>';

          // Feature cards
          html += '<div class="category-body' + (collapsed ? ' collapsed' : '') + '" id="' + catId + '">';
          cat.features.forEach(function(f) {
            html += renderFeatureCard(f, pids);
          });

          // Add feature button
          html += '<button class="add-feature-btn" onclick="openAddFeatureModal(\'' + esc(cat.name).replace(/'/g, "\\'") + '\')">+ Add Feature</button>';

          html += '</div></div>';
        });

        // If no features at all
        if (features.length === 0) {
          html += '<div style="text-align:center;padding:40px;color:var(--text-muted)">' +
            '<p>No features defined yet.</p>' +
            '<button class="btn btn-primary" onclick="openAddFeatureModal()">Add Feature</button>' +
          '</div>';
        }

        el.innerHTML = html;
      }

      var gapSectionCollapsed = false;

      function renderInlineGapSection(prod, pids, features) {
        var el = document.getElementById('inline-gap-section');
        var gaps = [];

        features.forEach(function(f) {
          // Only check projects that participate in this feature
          var featurePids = Object.keys(f.statuses || {});
          featurePids.forEach(function(pid) {
            var s = f.statuses[pid];
            if (s === 'missing' || s === 'planned') {
              gaps.push({
                feature_id: f.id,
                feature_name: f.name,
                project_id: pid,
                project_name: getProjectById(pid).name,
                status: s,
                category: f.category || 'Uncategorized',
                // Check if blocked by dependencies
                blocked: (f.depends_on || []).some(function(depId) {
                  var depF = features.find(function(x) { return x.id === depId; });
                  return depF && computeOverallStatus(depF.statuses) !== 'done';
                })
              });
            }
          });
        });

        if (gaps.length === 0) {
          el.innerHTML = '';
          return;
        }

        var html = '<div class="gap-section">' +
          '<div class="gap-section-header" onclick="toggleGapSection()">' +
            '<span class="gap-section-title">\u26A0 Gap Analysis (' + gaps.length + ' items)</span>' +
            '<span class="gap-section-count">' + gaps.filter(function(g) { return g.status === 'missing'; }).length + ' missing \u00b7 ' + gaps.filter(function(g) { return g.status === 'planned'; }).length + ' planned</span>' +
          '</div>';

        if (!gapSectionCollapsed) {
          html += '<div class="gap-section-body">';
          gaps.forEach(function(g) {
            html += '<div class="gap-row">' +
              '<span class="gap-row-feature">' + STATUS_ICONS[g.status] + ' ' + esc(g.feature_name) +
                (g.blocked ? ' <span class="dep-blocked">\u26D4</span>' : '') +
              '</span>' +
              '<span class="gap-row-project">' + esc(g.project_name) + '</span>' +
              '<button class="gap-row-action" onclick="quickSetStatus(\'' + g.feature_id + '\',\'' + g.project_id + '\',\'in_progress\')">\u25B6 Start</button>' +
              '<button class="gap-row-action" onclick="quickSetStatus(\'' + g.feature_id + '\',\'' + g.project_id + '\',\'done\')">\u2705 Done</button>' +
              '<button class="gap-row-action" onclick="quickSetStatus(\'' + g.feature_id + '\',\'' + g.project_id + '\',\'n_a\')">\u2B1C N/A</button>' +
            '</div>';
          });
          html += '</div>';
        }

        html += '</div>';
        el.innerHTML = html;
      }

      function toggleGapSection() {
        gapSectionCollapsed = !gapSectionCollapsed;
        renderSpecSheet();
      }

      async function quickSetStatus(featureId, projectId, status) {
        await fetch(API + '/products/' + currentProd.id + '/features/' + featureId + '/status', {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ project_id: projectId, status: status, source: 'gap_action' })
        });
        var res = await fetch(API + '/products/' + currentProd.id);
        currentProd = await res.json();
        renderSpecSheet();
      }

      function renderFeatureCard(f, pids) {
        var overall = computeOverallStatus(f.statuses);
        var applicable = getApplicableProjects(f);
        var missingCount = applicable.filter(function(pid) {
          var s = f.statuses[pid] || 'missing';
          return s === 'missing';
        }).length;

        var html = '<div class="feature-card">' +
          '<div class="feature-card-top">' +
            '<span class="feature-status-badge badge-' + overall + '">' + STATUS_ICONS[overall] + ' ' + STATUS_LABELS[overall] + '</span>' +
            '<div class="feature-info">' +
              '<div class="feature-name">' + esc(f.name) + '</div>' +
              (f.description ? '<div class="feature-desc">' + esc(f.description) + '</div>' : '') +
              '<div class="feature-meta">';

        // Project tags for applicable projects
        applicable.forEach(function(pid) {
          var p = getProjectById(pid);
          var pStatus = f.statuses[pid] || 'missing';
          html += '<span class="feature-project-tag" title="' + STATUS_LABELS[pStatus] + '">' + STATUS_ICONS[pStatus] + ' ' + esc(p.name) + '</span>';
        });

        // Gap warning
        if (missingCount > 0 && overall !== 'missing') {
          html += '<span class="gap-warning">\u26A0 ' + missingCount + ' gap' + (missingCount > 1 ? 's' : '') + '</span>';
        }

        html += '</div>';

        // Dependencies (skip orphaned/deleted refs)
        var deps = (f.depends_on || []).filter(function(depId) {
          return currentProd.features.some(function(x) { return x.id === depId; });
        });
        if (deps.length > 0) {
          html += '<div class="feature-deps"><span class="feature-deps-label">Depends on:</span>';
          deps.forEach(function(depId) {
            var depF = currentProd.features.find(function(x) { return x.id === depId; });
            var depName = depF.name;
            var depStatus = computeOverallStatus(depF.statuses);
            html += '<span class="dep-tag" onclick="openFeatureDetail(\'' + depId + '\')" title="' + STATUS_LABELS[depStatus] + '">' + STATUS_ICONS[depStatus] + ' ' + esc(depName) + '</span>';
            if (depStatus !== 'done') {
              html += '<span class="dep-blocked">\u26D4 blocked</span>';
            }
          });
          html += '</div>';
        }

        // Last status change (from history)
        var history = f.status_history || [];
        if (history.length > 0) {
          var last = history[0];
          var ago = timeAgo(last.changed_at);
          var srcLabel = last.source === 'manual' ? 'manually' : 'by ' + last.source;
          var projName = getProjectById(last.project_id).name;
          html += '<div class="feature-history">Last updated: ' + esc(projName) + ' \u2192 ' + STATUS_LABELS[last.status] + ' \u00b7 ' + ago + ' <span class="history-source">(' + esc(srcLabel) + ')</span></div>';
        }

        html += '</div>' +
            '<div class="feature-actions">' +
              '<button class="verify-btn" onclick="checkFeature(\'' + f.id + '\')" title="Verify this feature across projects">Verify</button>' +
              '<button class="feature-action-btn" onclick="openFeatureDetail(\'' + f.id + '\')" title="Per-project details">\uD83D\uDD0D</button>' +
              '<button class="feature-action-btn" onclick="editFeature(\'' + f.id + '\')" title="Edit">\u270E</button>' +
              '<button class="feature-action-btn" onclick="deleteFeature(\'' + f.id + '\')" title="Delete">\u00D7</button>' +
            '</div>' +
          '</div>' +
        '</div>';

        return html;
      }

      // --- Category Filter & Toggle ---

      function filterCategory(catName) {
        if (activeFilter === catName) {
          activeFilter = null;
        } else {
          activeFilter = catName;
        }
        renderSpecSheet();
      }

      function toggleCategory(catName) {
        collapsedCategories[catName] = !collapsedCategories[catName];
        saveCollapseState();
        renderSpecSheet();
      }

      function saveCollapseState() {
        if (!currentProd) return;
        try { localStorage.setItem('symphony_collapse_' + currentProd.id, JSON.stringify(collapsedCategories)); } catch(e) {}
      }

      function loadCollapseState() {
        if (!currentProd) { collapsedCategories = {}; return; }
        try {
          var saved = localStorage.getItem('symphony_collapse_' + currentProd.id);
          collapsedCategories = saved ? JSON.parse(saved) : {};
        } catch(e) { collapsedCategories = {}; }
      }

      function updateCategoryDatalist(features) {
        var cats = {};
        features.forEach(function(f) { if (f.category) cats[f.category] = true; });
        var dl = document.getElementById('category-list');
        dl.innerHTML = Object.keys(cats).map(function(c) {
          return '<option value="' + esc(c) + '">';
        }).join('');
      }

      // --- Feature Detail Modal (per-project statuses) ---

      function openFeatureDetail(fid) {
        var f = currentProd.features.find(function(x) { return x.id === fid; });
        if (!f) return;
        var featurePids = Object.keys(f.statuses || {});

        document.getElementById('detail-modal-title').textContent = f.name;

        var html = '';
        if (f.description) {
          html += '<p style="font-size:0.85rem;color:var(--text-secondary);margin-bottom:16px">' + esc(f.description) + '</p>';
        }

        featurePids.forEach(function(pid) {
          var p = getProjectById(pid);
          var status = f.statuses[pid] || 'missing';
          html += '<div class="detail-project-row">' +
            '<span class="detail-project-name">' + esc(p.name) + '</span>' +
            '<button class="detail-status-btn badge-' + status + '" onclick="cycleDetailStatus(\'' + fid + '\',\'' + pid + '\',\'' + status + '\')" title="Click to change">' +
              STATUS_ICONS[status] + ' ' + STATUS_LABELS[status] +
            '</button>' +
          '</div>';
        });

        // History section
        var history = f.status_history || [];
        if (history.length > 0) {
          var historyLimit = detailHistoryExpanded[fid] ? history.length : 10;
          html += '<div style="margin-top:16px;border-top:1px solid var(--border);padding-top:12px">';
          html += '<h4 style="font-size:0.8rem;color:var(--text-muted);margin-bottom:8px">Change History (' + history.length + ')</h4>';
          history.slice(0, historyLimit).forEach(function(h) {
            var projName = getProjectById(h.project_id).name;
            var ago = timeAgo(h.changed_at);
            html += '<div style="font-size:0.75rem;color:var(--text-muted);padding:3px 0">' +
              esc(projName) + ' \u2192 ' + STATUS_LABELS[h.status] + ' <span class="history-source">(' + esc(h.source) + ')</span> \u00b7 ' + ago +
            '</div>';
          });
          if (history.length > 10) {
            if (detailHistoryExpanded[fid]) {
              html += '<div style="padding-top:4px"><button class="btn btn-ghost btn-sm" onclick="toggleDetailHistory(\'' + fid + '\')">Show less</button></div>';
            } else {
              html += '<div style="padding-top:4px"><button class="btn btn-ghost btn-sm" onclick="toggleDetailHistory(\'' + fid + '\')">Show all ' + history.length + ' entries</button></div>';
            }
          }
          html += '</div>';
        }

        document.getElementById('detail-modal-body').innerHTML = html;
        document.getElementById('detail-modal').style.display = '';
      }

      function closeDetailModal() {
        document.getElementById('detail-modal').style.display = 'none';
      }

      function toggleDetailHistory(fid) {
        detailHistoryExpanded[fid] = !detailHistoryExpanded[fid];
        openFeatureDetail(fid);
      }

      async function cycleDetailStatus(featureId, projectId, current) {
        var idx = STATUS_ORDER.indexOf(current);
        var next = STATUS_ORDER[(idx + 1) % STATUS_ORDER.length];

        await fetch(API + '/products/' + currentProd.id + '/features/' + featureId + '/status', {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ project_id: projectId, status: next, source: 'manual' })
        });

        var res = await fetch(API + '/products/' + currentProd.id);
        currentProd = await res.json();
        renderSpecSheet();
        openFeatureDetail(featureId);
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

      function closeProdModal() { document.getElementById('prod-modal').style.display = 'none'; }

      function renderProjectChecklist(selectedIds) {
        var container = document.getElementById('project-checklist');
        if (allProjects.length === 0) {
          container.innerHTML = '<div style="color:var(--text-muted);padding:8px;font-size:0.8rem">No projects yet. Create projects on the Board first.</div>';
          return;
        }
        container.innerHTML = allProjects.map(function(p) {
          var checked = selectedIds.indexOf(p.id) !== -1 ? 'checked' : '';
          return '<label class="project-check-item"><input type="checkbox" value="' + p.id + '" ' + checked + '> ' + esc(p.name) + (p.description ? ' <span style="color:var(--text-muted);font-size:0.75rem">\u2014 ' + esc(p.description) + '</span>' : '') + '</label>';
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

        var res;
        if (editId) {
          res = await fetch(API + '/products/' + editId, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
        } else {
          res = await fetch(API + '/products', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
        }

        if (res.status === 409) {
          alert('A product with that name already exists.');
          return;
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

      function renderDepsChecklist(selectedIds, excludeId) {
        var container = document.getElementById('feature-deps-checklist');
        var features = (currentProd && currentProd.features) ? currentProd.features : [];
        var available = features.filter(function(f) { return f.id !== excludeId; });
        if (available.length === 0) {
          container.innerHTML = '<div style="color:var(--text-muted);padding:8px;font-size:0.8rem">No other features to depend on.</div>';
          return;
        }
        container.innerHTML = available.map(function(f) {
          var checked = selectedIds.indexOf(f.id) !== -1 ? 'checked' : '';
          return '<label class="project-check-item"><input type="checkbox" value="' + f.id + '" ' + checked + '> ' + esc(f.name) + '</label>';
        }).join('');
      }

      function openAddFeatureModal(defaultCategory) {
        document.getElementById('feature-modal-title').textContent = 'Add Feature';
        document.getElementById('feature-edit-id').value = '';
        document.getElementById('feature-name').value = '';
        document.getElementById('feature-desc').value = '';
        document.getElementById('feature-category').value = defaultCategory && defaultCategory !== 'Uncategorized' ? defaultCategory : '';
        renderDepsChecklist([], null);
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
        document.getElementById('feature-category').value = f.category || '';
        renderDepsChecklist(f.depends_on || [], fid);
        document.getElementById('feature-modal').style.display = '';
        document.getElementById('feature-name').focus();
      }

      function closeFeatureModal() { document.getElementById('feature-modal').style.display = 'none'; }

      async function saveFeature() {
        var editId = document.getElementById('feature-edit-id').value;
        var name = document.getElementById('feature-name').value.trim();
        if (!name) { document.getElementById('feature-name').focus(); return; }

        var desc = document.getElementById('feature-desc').value.trim();
        var category = document.getElementById('feature-category').value.trim();
        var depChecks = document.querySelectorAll('#feature-deps-checklist input[type=checkbox]:checked');
        var dependsOn = Array.from(depChecks).map(function(c) { return c.value; });
        var payload = { name: name, description: desc || null, category: category || null, depends_on: dependsOn };

        var fRes;
        if (editId) {
          fRes = await fetch(API + '/products/' + currentProd.id + '/features/' + editId, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
        } else {
          fRes = await fetch(API + '/products/' + currentProd.id + '/features', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
        }

        if (fRes.status === 409) {
          alert('A feature with that name already exists in this product.');
          return;
        }

        closeFeatureModal();
        var res = await fetch(API + '/products/' + currentProd.id);
        currentProd = await res.json();
        renderSpecSheet();
      }

      async function deleteFeature(fid) {
        if (!confirm('Delete this feature?')) return;
        await fetch(API + '/products/' + currentProd.id + '/features/' + fid, { method: 'DELETE' });
        var res = await fetch(API + '/products/' + currentProd.id);
        currentProd = await res.json();
        renderSpecSheet();
      }

      // --- Analyze Gaps (AI) ---

      var lastAIGaps = [];

      async function analyzeGaps() {
        if (!currentProd) return;
        if (!confirm('This will create an agent task to analyze codebases and identify gaps in the feature matrix. Continue?')) return;

        var btn = document.getElementById('analyze-gaps-btn');
        btn.textContent = 'Creating task...';
        btn.disabled = true;

        try {
          var res = await fetch(API + '/products/' + currentProd.id + '/analyze-gaps', { method: 'POST' });
          var data = await res.json();
          alert(data.message || 'Gap analysis task created. The agent will pick it up and report findings as follow-ups.');
        } catch (e) {
          alert('Gap analysis failed: ' + e.message);
        } finally {
          btn.textContent = 'Analyze Gaps';
          btn.disabled = false;
        }
      }

      // --- Skill Picker Toggle ---

      function toggleSkillPicker(containerId) {
        var el = document.getElementById(containerId);
        if (!el) return;
        if (el.style.display === 'none') {
          renderSkillPicker(containerId, [], []);
          el.style.display = '';
        } else {
          el.style.display = 'none';
        }
      }

      // --- Generate Features ---

      function openGenerateModal() {
        if (!currentProd) return;
        document.getElementById('generate-prompt').value = '';
        document.getElementById('generate-skills').style.display = 'none';
        document.getElementById('generate-modal').style.display = '';
        document.getElementById('generate-prompt').focus();
      }

      function closeGenerateModal() { document.getElementById('generate-modal').style.display = 'none'; }

      async function generateFeatures() {
        var prompt = document.getElementById('generate-prompt').value.trim();
        if (!prompt) { document.getElementById('generate-prompt').focus(); return; }

        var skills = getSelectedSkills('generate-skills');
        var btn = document.getElementById('generate-btn');
        btn.innerHTML = '<span class="spinner"></span> Creating...';
        btn.disabled = true;

        try {
          var res = await fetch(API + '/products/' + currentProd.id + '/generate-features', {
            method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ prompt: prompt, skill_ids: skills.skill_ids, skill_group_ids: skills.skill_group_ids })
          });
          var data = await res.json();
          if (data.error) { alert('Error: ' + (data.message || data.error)); return; }
          closeGenerateModal();
          alert(data.issue.identifier + ' created on the board.\n\nThe agent will analyze the product and propose features as follow-up issues.\n\nCheck the board for progress.');
        } catch (e) {
          alert('Failed: ' + e.message);
        } finally {
          btn.innerHTML = 'Create Agent Task';
          btn.disabled = false;
        }
      }

      // --- Check/Verify Feature ---

      async function checkFeature(featureId) {
        if (!currentProd) return;
        var feature = currentProd.features.find(function(f) { return f.id === featureId; });
        if (!feature) return;

        var toCheck = (currentProd.project_ids || []).filter(function(pid) {
          var s = feature.statuses[pid] || 'missing';
          return s !== 'done' && s !== 'n_a';
        });

        if (toCheck.length === 0) {
          alert('All projects are already done or N/A for this feature.');
          return;
        }

        if (!confirm('This will create ' + toCheck.length + ' issue(s) to verify "' + feature.name + '" across projects.\n\nContinue?')) return;

        try {
          var res = await fetch(API + '/products/' + currentProd.id + '/features/' + featureId + '/check', {
            method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({})
          });
          var data = await res.json();
          if (data.error) { alert('Error: ' + (data.message || data.error)); return; }

          var res2 = await fetch(API + '/products/' + currentProd.id);
          currentProd = await res2.json();
          renderSpecSheet();

          var issues = data.issues || [];
          var ids = issues.map(function(i) { return i.identifier; }).join(', ');
          alert('Created ' + issues.length + ' check issue(s): ' + ids + '\n\nAgents will pick these up and report findings.');
        } catch (e) {
          alert('Check failed: ' + e.message);
        }
      }

      // --- Analyze Existing Features ---

      async function analyzeExistingFeatures() {
        if (!currentProd) return;
        if (!confirm('This will create an agent task to scan all project codebases and discover already-implemented features.\n\nContinue?')) return;

        var btn = document.getElementById('analyze-existing-btn');
        btn.textContent = 'Creating...';
        btn.disabled = true;

        try {
          var res = await fetch(API + '/products/' + currentProd.id + '/analyze-existing-features', {
            method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({})
          });
          var data = await res.json();
          if (data.error) { alert('Error: ' + (data.message || data.error)); return; }
          alert(data.issue.identifier + ' created on the board.\n\nThe agent will scan codebases and discover implemented features.');
        } catch (e) {
          alert('Failed: ' + e.message);
        } finally {
          btn.textContent = 'Analyze Features';
          btn.disabled = false;
        }
      }

      // --- Code Review ---

      function openCodeReviewModal() {
        if (!currentProd) return;
        document.getElementById('review-focus').value = '';
        document.getElementById('review-skills').style.display = 'none';
        document.getElementById('code-review-modal').style.display = '';
        document.getElementById('review-focus').focus();
      }

      function closeCodeReviewModal() { document.getElementById('code-review-modal').style.display = 'none'; }

      async function startCodeReview() {
        var focus = document.getElementById('review-focus').value.trim();
        var skills = getSelectedSkills('review-skills');
        var btn = document.getElementById('code-review-btn');
        btn.innerHTML = '<span class="spinner"></span> Creating...';
        btn.disabled = true;

        try {
          var res = await fetch(API + '/products/' + currentProd.id + '/code-review', {
            method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ focus: focus, skill_ids: skills.skill_ids, skill_group_ids: skills.skill_group_ids })
          });
          var data = await res.json();
          if (data.error) { alert('Error: ' + (data.message || data.error)); return; }
          closeCodeReviewModal();
          alert(data.issue.identifier + ' created on the board.\n\nThe agent will review all project codebases and report findings.');
        } catch (e) {
          alert('Failed: ' + e.message);
        } finally {
          btn.innerHTML = 'Start Code Review';
          btn.disabled = false;
        }
      }

      // --- Generate Definition ---

      function openGenDefModal() {
        if (!currentProd) return;
        document.getElementById('gendef-context').value = '';
        document.getElementById('gendef-skills').style.display = 'none';
        document.getElementById('gendef-modal').style.display = '';
        document.getElementById('gendef-context').focus();
      }

      function closeGenDefModal() { document.getElementById('gendef-modal').style.display = 'none'; }

      async function generateDefinition() {
        var context = document.getElementById('gendef-context').value.trim();
        var skills = getSelectedSkills('gendef-skills');
        var btn = document.getElementById('gendef-btn');
        btn.innerHTML = '<span class="spinner"></span> Creating...';
        btn.disabled = true;

        try {
          var res = await fetch(API + '/products/' + currentProd.id + '/generate-definition', {
            method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ context: context, skill_ids: skills.skill_ids, skill_group_ids: skills.skill_group_ids })
          });
          var data = await res.json();
          if (data.error) { alert('Error: ' + (data.message || data.error)); return; }
          closeGenDefModal();
          alert(data.issue.identifier + ' created on the board.\n\nThe agent will analyze the projects and propose a product definition. Check the board for progress.');
        } catch (e) {
          alert('Failed: ' + e.message);
        } finally {
          btn.innerHTML = 'Generate Definition';
          btn.disabled = false;
        }
      }

      // --- Product Task (generic) ---

      function openProductTaskModal() {
        if (!currentProd) return;
        document.getElementById('ptask-title').value = '';
        document.getElementById('ptask-prompt').value = '';
        document.getElementById('ptask-priority').value = '2';
        document.getElementById('ptask-skills').style.display = 'none';
        document.getElementById('product-task-modal').style.display = '';
        document.getElementById('ptask-title').focus();
      }

      function closeProductTaskModal() { document.getElementById('product-task-modal').style.display = 'none'; }

      async function createProductTask() {
        var title = document.getElementById('ptask-title').value.trim();
        var prompt = document.getElementById('ptask-prompt').value.trim();
        if (!title) { document.getElementById('ptask-title').focus(); return; }
        if (!prompt) { document.getElementById('ptask-prompt').focus(); return; }

        var priority = parseInt(document.getElementById('ptask-priority').value) || 2;
        var skills = getSelectedSkills('ptask-skills');
        var btn = document.getElementById('ptask-btn');
        btn.innerHTML = '<span class="spinner"></span> Creating...';
        btn.disabled = true;

        try {
          var res = await fetch(API + '/products/' + currentProd.id + '/tasks', {
            method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              title: title,
              prompt: prompt,
              priority: priority,
              skill_ids: skills.skill_ids,
              skill_group_ids: skills.skill_group_ids
            })
          });
          var data = await res.json();
          if (data.error) { alert('Error: ' + (data.message || data.error)); return; }
          closeProductTaskModal();
          alert(data.issue.identifier + ' created on the board.\n\nThe agent will pick it up and work on it. Check the board for progress.');
        } catch (e) {
          alert('Failed: ' + e.message);
        } finally {
          btn.innerHTML = 'Create Task';
          btn.disabled = false;
        }
      }

      // --- Keyboard shortcuts ---
      document.addEventListener('keydown', function(e) {
        if (e.key === 'Escape') {
          closeProdModal();
          closeFeatureModal();
          closeGenerateModal();
          closeCodeReviewModal();
          closeGenDefModal();
          closeProductTaskModal();
          closeDetailModal();
        }
      });

      init();
      """
  end
end

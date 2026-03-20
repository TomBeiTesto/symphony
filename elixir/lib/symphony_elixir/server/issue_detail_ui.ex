# credo:disable-for-this-file Credo.Check.Readability.MaxLineLength
defmodule SymphonyElixir.Server.IssueDetailUI do
  @moduledoc """
  Server-rendered issue detail page with live activity feed.
  
  Shows issue metadata and polls the orchestrator for real-time
  agent activity (tool use, messages, token usage).
  """

  alias SymphonyElixir.Server.UIHelpers
  import UIHelpers, only: [esc: 1]

  @doc "Render the issue detail HTML page."
  @spec render(map()) :: String.t()
  def render(issue) do
    body = """
      <div class="page-actions-bar">
        <div class="page-actions-left">
          <button onclick="history.back()" aria-label="Go back" style="background:none;border:none;color:var(--text-muted);font-size:1.1rem;margin-right:8px;cursor:pointer;padding:0">&larr;</button>
          <h2 class="issue-identifier">#{esc(issue.identifier)}</h2>
          <span class="badge" id="state-badge">#{esc(issue.state)}</span>
        </div>
        <div class="page-actions-right">
          <button class="btn-edit" id="edit-btn" onclick="toggleEdit()">Edit</button>
          <button class="btn btn-ghost" id="send-to-kb-btn" onclick="sendToKB()"
            style="display:none" title="Send issue and reports to Knowledge Base">Send to KB</button>
          <button class="btn btn-ghost" id="rerun-btn" onclick="toggleRerunPanel()"
            style="display:none" title="Rerun agent with additional guidance">Rerun</button>
          <button class="btn-delete" id="delete-btn" onclick="deleteIssue()">Delete</button>
          <span class="meta" id="agent-status" aria-live="polite" role="status">Loading...</span>
        </div>
      </div>
    
      <div class="rerun-bar" id="rerun-panel" style="display:none;">
        <div class="rerun-bar-inner">
          <div class="rerun-bar-left">
            <strong>Rerun with Feedback</strong>
            <span class="meta">The agent will read its previous output, then improve based on your guidance.</span>
          </div>
          <div class="rerun-bar-right">
            <textarea id="rerun-hint" rows="2" aria-label="Feedback for agent rerun" placeholder="e.g. The extraction missed the scheduling logic
              in scheduler.py. Also expand BR-003 with retry behavior details."></textarea>
            <div class="rerun-bar-actions">
              <button class="btn btn-primary btn-sm" onclick="rerunIssue()">Rerun Agent</button>
              <button class="btn btn-ghost btn-sm" onclick="toggleRerunPanel()">Cancel</button>
            </div>
          </div>
        </div>
      </div>
    
      <div class="content">
        <div class="main-grid">
          <!-- Left: Issue info + result -->
          <div class="left-column">
            <div class="panel issue-panel">
              <!-- View mode -->
              <div id="view-mode">
                <h2 id="issue-title">#{esc(issue.title)}</h2>
                <div class="issue-meta">
                  <span class="priority-badge priority-#{issue.priority || 0}"
                    id="issue-priority">P#{issue.priority || 0}</span>
                  <span id="issue-labels">#{render_labels(issue.labels || [])}</span>
                  <span id="issue-product" class="product-badge"></span>
                  <span id="issue-project" class="project-badge"></span>
                  <span class="meta">Created #{format_time(issue.created_at)}</span>
                </div>
                <div class="description"
                  id="description">#{render_markdown(issue.description || "No description.")}</div>
              </div>
              <!-- Edit mode -->
              <div id="edit-mode" style="display:none;">
                <div class="edit-field">
                  <label for="edit-title">Title</label>
                  <input type="text" id="edit-title" class="edit-input" value="#{esc(issue.title)}">
                </div>
                <div class="edit-row">
                  <div class="edit-field">
                    <label for="edit-state">State</label>
                    <select id="edit-state" class="edit-input"></select>
                  </div>
                  <div class="edit-field">
                    <label for="edit-priority">Priority</label>
                    <select id="edit-priority" class="edit-input">
                      <option value="0">None</option>
                      <option value="1">Urgent</option>
                      <option value="2">High</option>
                      <option value="3">Medium</option>
                      <option value="4">Low</option>
                    </select>
                  </div>
                </div>
                <div class="edit-field">
                  <label for="edit-labels">Labels (comma-separated)</label>
                  <input type="text" id="edit-labels" class="edit-input"
                    value="#{esc(Enum.join(issue.labels || [], ", "))}">
                </div>
                <div class="edit-row">
                  <div class="edit-field">
                    <label for="edit-product">Product</label>
                    <select id="edit-product" class="edit-input">
                      <option value="">No product</option>
                    </select>
                  </div>
                  <div class="edit-field">
                    <label for="edit-project">Project</label>
                    <select id="edit-project" class="edit-input">
                      <option value="">No project</option>
                    </select>
                  </div>
                </div>
                <div class="edit-field">
                  <label for="edit-description">Description</label>
                  <textarea id="edit-description"
                    class="edit-input edit-textarea">#{esc(issue.description || "")}</textarea>
                </div>
                <div class="edit-actions">
                  <button class="btn-save" onclick="saveEdit()">Save</button>
                  <button class="btn-cancel" onclick="toggleEdit()">Cancel</button>
                </div>
              </div>
            </div>
            <!-- Skills Panel -->
            <div class="panel skills-panel" id="skills-panel">
              <div class="skills-panel-header">
                <h3>Skills</h3>
                <button class="btn btn-ghost btn-sm" onclick="toggleSkillPicker()">+ Add</button>
              </div>
              <div class="skill-pills" id="skill-pills">
                <span class="meta">No skills assigned</span>
              </div>
              <div id="skill-picker" style="display:none;" class="skill-picker">
                <div class="picker-section">
                  <label class="picker-label">Skills</label>
                  <select id="add-skill-select" onchange="addSkillToIssue(this.value); this.value='';">
                    <option value="">Select a skill...</option>
                  </select>
                </div>
                <div class="picker-section">
                  <label class="picker-label">Skill Groups</label>
                  <select id="add-group-select" onchange="addGroupToIssue(this.value); this.value='';">
                    <option value="">Select a group...</option>
                  </select>
                </div>
              </div>
            </div>
            <!-- Pipeline Context Panel -->
            <div class="panel pipeline-ctx-panel" id="pipeline-ctx-panel" style="display:none;">
              <div class="pipeline-ctx-header">
                <h3>Pipeline Context</h3>
              </div>
              <div id="pipeline-ctx-content"></div>
            </div>
            <div class="panel plan-review-panel" id="plan-review-panel" style="display:none;">
              <div class="plan-review-header">
                <h3>Plan Review</h3>
                <span class="plan-status-badge" id="plan-status-badge"></span>
              </div>
              <div class="plan-text" id="plan-text"></div>
              <div class="plan-actions" id="plan-actions" style="display:none;">
                <button class="btn btn-primary" onclick="approvePlan()">Approve &amp; Execute</button>
                <button class="btn btn-ghost" onclick="showRejectForm()">Reject with Feedback</button>
              </div>
              <div class="plan-reject-form" id="plan-reject-form" style="display:none;">
                <textarea id="plan-feedback" placeholder="What should the agent change in its plan?"
                  rows="3"></textarea>
                <div style="display:flex;gap:8px;">
                  <button class="btn btn-primary btn-replan" onclick="rejectPlan()">Re-plan with Feedback</button>
                  <button class="btn btn-ghost" onclick="hideRejectForm()">Cancel</button>
                </div>
              </div>
            </div>
            <div class="panel result-panel" id="result-panel" style="display:none;">
              <h3>Agent Result</h3>
              <div class="result-text" id="result-text"></div>
            </div>
            <div class="panel followups-panel" id="followups-panel" style="display:none;">
              <h3 class="followups-title">Proposed Follow-ups</h3>
              <div id="followups-list"></div>
            </div>
            <div class="panel report-panel" id="report-panel" style="display:none;">
              <div class="report-header">
                <h3 id="report-title">Report</h3>
              </div>
              <div class="report-content" id="report-content"></div>
            </div>
          </div>
    
          <!-- Right: Agent activity -->
          <div class="panel activity-panel">
            <div class="activity-header">
              <h3>Agent Activity</h3>
              <div class="token-display" id="token-display"></div>
            </div>
            <div class="activity-feed" id="activity-feed" aria-live="polite" aria-atomic="false">
              <div class="empty-state">Waiting for agent...</div>
            </div>
          </div>
        </div>
      </div>
    
      <script>
    #{UIHelpers.esc_js()}
    #{UIHelpers.markdown_js()}
    #{UIHelpers.toast_js()}
    #{js(issue.id, issue.identifier)}
      </script>
    """

    title = "#{esc(issue.identifier)} - #{esc(issue.title)}"
    UIHelpers.page_template(title, "", css(), body)
  end

  defp render_labels([]), do: ""

  defp render_labels(labels) do
    labels
    |> Enum.map(fn l -> "<span class=\"label\">#{esc(to_string(l))}</span>" end)
    |> Enum.join(" ")
  end

  defp render_markdown(text) do
    text
    |> esc()
    |> String.replace("\n\n", "</p><p>")
    |> String.replace("\n", "<br>")
    |> then(&"<p>#{&1}</p>")
  end

  defp format_time(nil), do: ""

  defp format_time(dt) when is_binary(dt) do
    case DateTime.from_iso8601(dt) do
      {:ok, d, _} -> Calendar.strftime(d, "%Y-%m-%d %H:%M")
      _ -> dt
    end
  end

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  defp format_time(_), do: ""

  defp css do
    UIHelpers.markdown_css() <>
      UIHelpers.page_actions_css() <>
      UIHelpers.pulse_css() <>
      UIHelpers.label_css() <>
      ~S"""
      
      html, body { height: 100%; overflow: hidden; }
      body { display: flex; flex-direction: column; }
      h1 { color: var(--text-primary); font-size: 1.15rem; }
      .page-actions-bar { padding: 8px 20px; }
      .issue-identifier { font-size: 1rem; font-weight: 600; color: var(--text-primary); }
      .meta { color: var(--text-muted); font-size: 0.8rem; }
      .content { padding: 20px 24px; max-width: 1400px; margin: 0 auto; flex: 1; overflow: hidden; width: 100%; }
      .main-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; height: 100%; }
      @media (min-width: 768px) and (max-width: 1023px) {
        .main-grid { grid-template-columns: 1.2fr 0.8fr; }
      }
      @media (max-width: 767px) {
        .main-grid { grid-template-columns: 1fr; }
        .activity-panel { order: 2; }
        .left-column { order: 1; }
      }
      @media (max-width: 640px) {
        html, body { height: auto; overflow: auto; }
        .content { overflow: auto; flex: unset; padding: 12px; }
        .main-grid { height: auto; }
        .activity-panel { height: auto; min-height: 300px; }
        .activity-feed { max-height: 400px; }
        .page-actions-bar { flex-wrap: wrap; gap: 6px; padding: 8px 12px; }
        .page-actions-right { flex-wrap: wrap; gap: 4px; }
        .rerun-bar-inner { flex-direction: column; gap: 8px; }
        .rerun-bar-left { min-width: 0; }
        .rerun-bar-right { flex-direction: column; }
        .edit-row { grid-template-columns: 1fr; }
      }
      @media (hover: none) and (pointer: coarse) {
        .btn-edit, .btn-delete { min-height: 44px; padding: 6px 14px; }
      }
      .panel { background: var(--bg-secondary); border: 1px solid var(--border);
        border-radius: var(--radius); padding: 20px; overflow: hidden; }
      .left-column { display: flex; flex-direction: column; gap: 16px; overflow-y: auto; }
      .issue-panel { flex-shrink: 0; }
      .issue-panel h2 { color: var(--text-primary); font-size: 1.1rem; margin-bottom: 12px; }
      .issue-meta { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; margin-bottom: 16px; }
      .description { color: var(--text-secondary); font-size: 0.9rem; line-height: 1.6; }
      .description p { margin-bottom: 8px; }
      .activity-panel { display: flex; flex-direction: column; min-height: 0; }
      .activity-header { display: flex; justify-content: space-between; align-items: center;
        margin-bottom: 12px; flex-shrink: 0; }
      .activity-header h3 { color: var(--text-primary); font-size: 1rem; }
      .token-display { font-size: 0.75rem; color: var(--text-muted); display: flex; gap: 12px; }
      .token-display .tok { background: var(--border-light); padding: 2px 8px; border-radius: 4px; }
      .activity-feed { flex: 1; overflow-y: auto; display: flex; flex-direction: column; gap: 2px; }
      .empty-state { color: var(--text-muted); font-style: italic; text-align: center; padding: 40px; opacity: 0.6; }
      .event { padding: 6px 10px; border-radius: 4px; font-size: 0.8rem;
        font-family: 'SF Mono', 'Fira Code', monospace; border-left: 3px solid transparent; }
      .event .time { color: var(--text-muted); margin-right: 8px; font-size: 0.7rem; opacity: 0.6; }
      .event.has-detail { cursor: pointer; }
      .event.has-detail:hover { background: var(--bg-secondary); }
      .event .detail-summary { color: var(--text-muted); margin-left: 8px; font-weight: 400; }
      .event .detail-block { display: none; margin-top: 6px; padding: 8px 10px;
        background: var(--bg-primary); border: 1px solid var(--border-light); border-radius: 4px;
        font-size: 0.75rem; color: var(--text-muted); white-space: pre-wrap;
        word-break: break-all; max-height: 200px; overflow-y: auto; }
      .event.expanded .detail-block { display: block; }
      .event.tool_use { border-left-color: var(--accent); background: var(--bg-primary); }
      .event.tool_use .tool-name { color: var(--accent); font-weight: 600; }
      .event.agent_message { border-left-color: var(--green); background: var(--bg-primary); }
      .event.agent_message .msg { color: var(--text-secondary); }
      .event.agent_output { border-left-color: var(--text-muted); background: var(--bg-primary); }
      .event.agent_output .msg { color: var(--text-muted); }
      .event.system_info { border-left-color: var(--yellow); background: var(--bg-primary); }
      .event.session_started { border-left-color: var(--yellow); background: var(--bg-primary); }
      .event.turn_completed { border-left-color: var(--green); background: rgba(63,185,80,0.05); }
      .event.token_usage_updated { border-left-color: var(--text-muted); }
      .event.default { border-left-color: var(--border); background: var(--bg-primary); }
      .plan-review-panel { flex-shrink: 0; }
      .plan-review-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 12px; }
      .plan-review-header h3 { color: var(--text-primary); font-size: 1rem;
        display: flex; align-items: center; gap: 8px; }
      .plan-review-header h3::before { content: ''; display: inline-block;
        width: 8px; height: 8px; border-radius: 50%; background: var(--accent); }
      .plan-status-badge { font-size: 0.75rem; padding: 2px 8px; border-radius: 10px; font-weight: 600; }
      .plan-status-badge.review { color: var(--accent); background: rgba(88,166,255,0.15); }
      .plan-status-badge.approved { color: var(--green); background: rgba(63,185,80,0.12); }
      .plan-status-badge.planning { color: var(--orange); background: rgba(255,180,50,0.12); }
      .plan-text { color: var(--text-secondary); font-size: 0.9rem; line-height: 1.7;
        white-space: pre-wrap; word-break: break-word; max-height: 500px; overflow-y: auto;
        margin-bottom: 12px; padding: 12px; background: var(--bg-secondary);
        border-radius: 6px; border: 1px solid var(--border-light); }
      .plan-text p { margin-bottom: 10px; }
      .plan-text strong { color: var(--text-primary); }
      .plan-text h2, .plan-text h3 { color: var(--text-primary); margin: 16px 0 8px; font-size: 1rem; }
      .plan-text code { background: var(--border-light); padding: 1px 6px;
        border-radius: 3px; font-size: 0.85em; color: var(--accent-hover); }
      .plan-text ul, .plan-text ol { margin-left: 20px; margin-bottom: 10px; }
      .plan-text li { margin-bottom: 4px; }
      .plan-actions { display: flex; gap: 8px; margin-bottom: 8px; }
      .plan-reject-form textarea {
        width: 100%; margin-bottom: var(--space-2); padding: var(--space-2) var(--space-3);
        border: 1px solid var(--border-primary); border-radius: var(--radius-sm);
        background: var(--bg-secondary); color: var(--text-primary);
        font-size: var(--font-base); resize: vertical; font-family: inherit;
        outline: none; transition: border-color var(--transition);
      }
      .plan-reject-form textarea:focus { border-color: var(--accent); }
      .plan-reject-form .btn-replan { background: var(--warning); border-color: var(--warning); }
      .result-panel { flex-shrink: 0; }
      .result-panel h3 { color: var(--text-primary); font-size: 1rem;
        margin-bottom: 12px; display: flex; align-items: center; gap: 8px; }
      .result-panel h3::before { content: ''; display: inline-block;
        width: 8px; height: 8px; border-radius: 50%; background: var(--green); }
      .result-text { color: var(--text-secondary); font-size: 0.9rem; line-height: 1.7;
        white-space: pre-wrap; word-break: break-word; }
      .result-text p { margin-bottom: 10px; }
      .result-text strong { color: var(--text-primary); }
      .result-text h2, .result-text h3 { color: var(--text-primary); margin: 16px 0 8px; font-size: 1rem; }
      .result-text code { background: var(--border-light); padding: 1px 6px;
        border-radius: 3px; font-size: 0.85em; color: var(--accent-hover); }
      .result-text ul, .result-text ol { margin-left: 20px; margin-bottom: 10px; }
      .result-text li { margin-bottom: 4px; }
      .skills-panel { flex-shrink: 0; }
      .skills-panel-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 8px; }
      .skills-panel-header h3 { color: var(--text-primary); font-size: 0.95rem;
        display: flex; align-items: center; gap: 6px; }
      .skills-panel-header h3::before { content: ''; display: inline-block;
        width: 8px; height: 8px; border-radius: 50%; background: var(--purple); }
      .skill-pills { display: flex; flex-wrap: wrap; gap: 6px; }
      .skill-picker {
        margin-top: 10px; padding: 10px; background: var(--bg-primary);
        border: 1px solid var(--border); border-radius: var(--radius-sm);
      }
      .picker-section { margin-bottom: 8px; }
      .picker-section:last-child { margin-bottom: 0; }
      .picker-label { font-size: 0.72rem; color: var(--text-muted); display: block; margin-bottom: 4px; }
      .picker-section select {
        width: 100%; padding: 5px 8px; background: var(--bg-secondary);
        border: 1px solid var(--border); border-radius: var(--radius-sm);
        color: var(--text-primary); font-size: 0.8rem;
      }
      .pipeline-ctx-panel { flex-shrink: 0; }
      .pipeline-ctx-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 8px; }
      .pipeline-ctx-header h3 { color: var(--text-primary); font-size: 0.95rem;
        display: flex; align-items: center; gap: 6px; }
      .pipeline-ctx-header h3::before { content: ''; display: inline-block;
        width: 8px; height: 8px; border-radius: 50%; background: var(--orange); }
      .pipeline-progress-bar { display: flex; height: 6px; border-radius: 3px;
        overflow: hidden; gap: 2px; margin: 8px 0; }
      .pipeline-progress-seg { flex: 1; border-radius: 2px; }
      .pipeline-run-link { display: flex; align-items: center; gap: 8px; padding: 8px;
        border: 1px solid var(--border); border-radius: var(--radius-sm); margin-top: 6px;
        cursor: pointer; text-decoration: none; color: var(--text-secondary);
        font-size: 0.85rem; transition: border-color var(--transition); }
      .pipeline-run-link:hover { border-color: var(--accent); }
      .followups-panel { flex-shrink: 0; }
      .followups-title { color: var(--text-primary); font-size: 1rem;
        margin-bottom: 12px; display: flex; align-items: center; gap: 8px; }
      .followups-title::before { content: ''; display: inline-block;
        width: 8px; height: 8px; border-radius: 50%; background: var(--yellow); }
      .followup-card { padding: 12px; border: 1px solid var(--border);
        border-radius: var(--radius-sm); margin-bottom: 8px; background: var(--bg-primary); }
      .followup-card.accepted { border-color: var(--green); opacity: 0.7; }
      .followup-card.rejected { border-color: var(--border); opacity: 0.4; }
      .fu-title { color: var(--text-primary); font-weight: 600; font-size: 0.9rem; margin-bottom: 4px; }
      .fu-desc { color: var(--text-muted); font-size: 0.8rem; margin-bottom: 8px; line-height: 1.4; }
      .fu-labels { display: flex; gap: 4px; margin-bottom: 8px; flex-wrap: wrap; }
      .fu-label { display: inline-block; padding: 1px 6px; border-radius: 8px;
        font-size: 0.65rem; background: rgba(88,166,255,0.1); color: var(--accent-hover); }
      .fu-actions { display: flex; gap: 8px; align-items: center; }
      .btn-accept { padding: 4px 12px; border-radius: var(--radius-sm); border: 1px solid var(--green);
        background: var(--green); color: #fff; font-size: 0.75rem; cursor: pointer; }
      .btn-accept:hover { opacity: 0.9; }
      .btn-reject { padding: 4px 12px; border-radius: var(--radius-sm); border: 1px solid var(--border);
        background: transparent; color: var(--text-muted); font-size: 0.75rem; cursor: pointer; }
      .btn-reject:hover { border-color: var(--red); color: var(--red); }
      .btn-fu-edit { padding: 4px 12px; border-radius: var(--radius-sm); border: 1px solid var(--border);
        background: transparent; color: var(--text-secondary); font-size: 0.75rem; cursor: pointer; }
      .btn-fu-edit:hover { border-color: var(--accent); color: var(--accent); }
      .fu-status { font-size: 0.75rem; font-weight: 600; }
      .fu-status.accepted { color: var(--green); }
      .fu-status.rejected { color: var(--text-muted); text-decoration: line-through; }
      .fu-link { color: var(--accent); text-decoration: none; font-size: 0.75rem; margin-left: 8px; }
      .fu-link:hover { text-decoration: underline; }
      .fu-edit-form { margin-top: 8px; display: flex; flex-direction: column; gap: 6px; }
      .fu-edit-form input, .fu-edit-form textarea { width: 100%; padding: 6px 8px;
        border: 1px solid var(--border); border-radius: var(--radius-sm);
        background: var(--bg-primary); color: var(--text-primary);
        font-size: 0.8rem; font-family: inherit; }
      .fu-edit-form textarea { min-height: 60px; resize: vertical; }
      .fu-edit-form .fu-edit-btns { display: flex; gap: 6px; }
      .report-panel { flex-shrink: 0; }
      .report-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 12px; }
      .report-header h3 { color: var(--text-primary); font-size: 1rem; display: flex; align-items: center; gap: 8px; }
      .report-header h3::before { content: ''; display: inline-block;
        width: 8px; height: 8px; border-radius: 50%; background: var(--accent); }
      .report-content { color: var(--text-secondary); font-size: 0.9rem; line-height: 1.7; }
      .report-content h1, .report-content h2 { color: var(--text-primary); font-size: 1.1rem;
        margin: 20px 0 10px; padding-bottom: 6px; border-bottom: 1px solid var(--border-light); }
      .report-content h3 { color: var(--text-primary); font-size: 1rem; margin: 16px 0 8px; }
      .report-content h4 { color: var(--text-primary); font-size: 0.95rem; margin: 12px 0 6px; }
      .report-content p { margin-bottom: 12px; }
      .report-content strong { color: var(--text-primary); }
      .report-content em { color: var(--text-secondary); font-style: italic; }
      .report-content code { background: var(--border-light); padding: 1px 6px;
        border-radius: 3px; font-size: 0.85em; color: var(--accent-hover); }
      .report-content pre { background: var(--bg-primary); border: 1px solid var(--border-light);
        border-radius: var(--radius-sm); padding: 12px; margin: 12px 0; overflow-x: auto; }
      .report-content pre code { background: none; padding: 0; color: var(--text-secondary); }
      .report-content ul, .report-content ol { margin-left: 20px; margin-bottom: 12px; }
      .report-content li { margin-bottom: 4px; }
      .report-content blockquote { border-left: 3px solid var(--border);
        padding-left: 12px; color: var(--text-muted); margin: 12px 0; }
      .report-content hr { border: none; border-top: 1px solid var(--border-light); margin: 20px 0; }
      .report-content a { color: var(--accent); text-decoration: none; }
      .report-content a:hover { text-decoration: underline; }
      .report-content table { border-collapse: collapse; margin: 12px 0; width: 100%; }
      .report-content th, .report-content td { border: 1px solid var(--border); padding: 6px 12px; text-align: left; }
      .report-content th { background: var(--bg-secondary); color: var(--text-primary); font-weight: 600; }
      .btn-edit { padding: 4px 14px; border-radius: var(--radius-sm); border: 1px solid var(--border);
        background: transparent; color: var(--text-secondary);
        font-size: 0.8rem; cursor: pointer; transition: all var(--transition); }
      .btn-edit:hover { border-color: var(--accent); color: var(--accent); }
      .btn-edit.active { border-color: var(--accent); background: var(--accent); color: #fff; }
      .btn-delete { padding: 4px 14px; border-radius: var(--radius-sm); border: 1px solid var(--border);
        background: transparent; color: var(--text-muted);
        font-size: 0.8rem; cursor: pointer; transition: all var(--transition); }
      .btn-delete:hover { border-color: var(--red); color: var(--red); }
      .kb-sent { border-color: var(--green, #3fb950); color: var(--green, #3fb950); }
      .rerun-bar { border-bottom: 1px solid var(--border); background: var(--bg-secondary); }
      .rerun-bar-inner { display: flex; align-items: flex-start; gap: 16px; padding: 10px 20px; }
      .rerun-bar-left { flex-shrink: 0; display: flex; flex-direction: column;
        gap: 2px; padding-top: 4px; min-width: 180px; }
      .rerun-bar-left strong { font-size: 0.85rem; color: var(--text-primary); }
      .rerun-bar-left .meta { font-size: 0.75rem; }
      .rerun-bar-right { flex: 1; display: flex; gap: 8px; align-items: flex-start; }
      .rerun-bar-right textarea { flex: 1; padding: 6px 10px; border: 1px solid var(--border);
        border-radius: 6px; background: var(--bg-primary); color: var(--text-primary);
        font-size: 0.85rem; resize: vertical; font-family: inherit; min-height: 36px; }
      .rerun-bar-right textarea:focus { outline: none; border-color: var(--accent);
        box-shadow: 0 0 0 2px rgba(88,166,255,0.15); }
      .rerun-bar-actions { display: flex; flex-direction: column; gap: 4px; flex-shrink: 0; }
      .edit-field { margin-bottom: 12px; }
      .edit-field label { display: block; font-size: 0.75rem; color: var(--text-muted);
        margin-bottom: 4px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; }
      .edit-input { width: 100%; padding: 8px 10px; border: 1px solid var(--border);
        border-radius: var(--radius-sm); background: var(--bg-primary);
        color: var(--text-primary); font-size: 0.9rem; font-family: inherit; }
      .edit-input:focus { outline: none; border-color: var(--accent); box-shadow: 0 0 0 2px rgba(88,166,255,0.15); }
      .edit-textarea { min-height: 120px; resize: vertical; line-height: 1.5; }
      .edit-row { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
      .edit-actions { display: flex; gap: 8px; margin-top: 4px; }
      .btn-save { padding: 6px 20px; border-radius: var(--radius-sm); border: none;
        background: var(--accent); color: #fff; font-size: 0.85rem; cursor: pointer; font-weight: 500; }
      .btn-save:hover { background: var(--accent-hover); }
      .btn-cancel { padding: 6px 20px; border-radius: var(--radius-sm); border: 1px solid var(--border);
        background: transparent; color: var(--text-muted); font-size: 0.85rem; cursor: pointer; }
      .btn-cancel:hover { border-color: var(--text-muted); }
      .product-badge { font-size: 0.75rem; padding: 2px 8px; border-radius: 10px;
        background: rgba(63,185,80,0.1); color: var(--green); }
      .product-badge:empty { display: none; }
      .project-badge { font-size: 0.75rem; padding: 2px 8px; border-radius: 10px;
        background: rgba(88,166,255,0.1); color: var(--accent-hover); }
      .project-badge:empty { display: none; }
      ::-webkit-scrollbar { width: 6px; height: 6px; }
      ::-webkit-scrollbar-track { background: transparent; }
      ::-webkit-scrollbar-thumb { background: var(--border); border-radius: 3px; }
      """
  end

  defp js(issue_id, identifier) do
    # Use ~s only for the interpolated constants, ~S for everything else
    # so that JS escape sequences (\n, \s, \w, etc.) are preserved literally.
    vars = ~s|const ISSUE_ID = "#{issue_id}";\nconst IDENTIFIER = "#{identifier}";\n|

    vars <> js_body()
  end

  defp js_body do
    polling_js() <>
      UIHelpers.time_utils_js() <>
      followups_js() <>
      render_events_js() <>
      edit_js() <>
      kb_and_actions_js() <>
      skills_js() <>
      init_and_pipeline_js() <>
      plan_review_and_poll_js()
  end

  defp polling_js do
    ~S"""
    let lastEventCount = 0;
    let lastOrchStatus = null;
    let reportLoaded = false;
    
    async function fetchReport() {
      try {
        const res = await fetch(`/board/api/issues/${ISSUE_ID}/report`);
        if (!res.ok) return;
        const data = await res.json();
        if (data.content) {
          reportLoaded = true;
          const panel = document.getElementById('report-panel');
          const title = document.getElementById('report-title');
          const content = document.getElementById('report-content');
          panel.style.display = 'block';
          title.textContent = data.path || 'Report';
          content.innerHTML = renderMarkdown(data.content);
        }
      } catch(e) {
        console.error('Report fetch error:', e);
      }
    }
    
    async function pollActivity() {
      try {
        const res = await fetch(`/board/api/issues/${ISSUE_ID}/activity`);
        if (!res.ok) return;
        const data = await res.json();
        updateUI(data);
      } catch(e) {
        console.error('Poll error:', e);
      }
    }
    
    function updateUI(data) {
      const issue = data.issue;
      const orch = data.orchestrator;
    
      // Update state badge
      const badge = document.getElementById('state-badge');
      badge.textContent = issue.state;
      badge.className = 'badge ' + issue.state.toLowerCase().replace(/\s+/g, '-');
      if (orch && orch.status === 'running') {
        badge.className = 'badge running';
        badge.textContent = 'Running';
      }
    
      // Update agent status
      const status = document.getElementById('agent-status');
      if (orch && orch.status === 'running' && orch.running) {
        const r = orch.running;
        const ago = r.last_event_at ? timeAgo(r.last_event_at) : '';
        status.textContent = `Turn ${r.turn_count || 1} | ${r.last_event || 'starting'} ${ago}`;
      } else if (orch && orch.status === 'retrying') {
        status.textContent = 'Retrying...';
      } else if (orch && orch.status === 'completed') {
        status.textContent = 'Completed';
      } else if (issue.state === 'Done') {
        status.textContent = 'Completed';
      } else {
        status.textContent = 'Idle';
      }
    
      // Show rerun button when agent has completed (not currently running)
      var rerunBtn = document.getElementById('rerun-btn');
      var isCompleted = (orch && orch.status === 'completed') || issue.state === 'Done' || issue.state === 'Review';
      var isRunning = orch && orch.status === 'running';
      rerunBtn.style.display = (isCompleted && !isRunning) ? '' : 'none';
      // Hide the rerun panel if agent started running
      if (isRunning) {
        document.getElementById('rerun-panel').style.display = 'none';
      }
    
      // Update tokens — check running state first, then fall back to persisted tokens
      const tokEl = document.getElementById('token-display');
      var t = (orch && orch.running && orch.running.tokens) ? orch.running.tokens : null;
      if (t && (t.input_tokens > 0 || t.output_tokens > 0)) {
        tokEl.innerHTML =
          '<span class="tok">In: ' + (t.input_tokens||0).toLocaleString() + '</span>' +
          '<span class="tok">Out: ' + (t.output_tokens||0).toLocaleString() + '</span>';
      } else {
        tokEl.innerHTML = '';
      }
    
      // Update activity feed — re-render on new events or status change
      const events = orch && orch.event_log ? orch.event_log : [];
      const orchStatus = orch ? orch.status : null;
      if (events.length !== lastEventCount || orchStatus !== lastOrchStatus) {
        lastEventCount = events.length;
        lastOrchStatus = orchStatus;
        renderEvents(events);
      }
    
      // Show plan review panel
      const planPanel = document.getElementById('plan-review-panel');
      const planText = document.getElementById('plan-text');
      const planActions = document.getElementById('plan-actions');
      const planBadge = document.getElementById('plan-status-badge');
      if (issue.plan_status === 'plan_review' && issue.plan_text) {
        planPanel.style.display = 'block';
        planText.innerHTML = renderMarkdown(issue.plan_text);
        planActions.style.display = 'flex';
        planBadge.textContent = 'Awaiting Review';
        planBadge.className = 'plan-status-badge review';
      } else if (issue.plan_status === 'approved' && issue.plan_text) {
        planPanel.style.display = 'block';
        planText.innerHTML = renderMarkdown(issue.plan_text);
        planActions.style.display = 'none';
        planBadge.textContent = 'Approved';
        planBadge.className = 'plan-status-badge approved';
      } else if (issue.plan_status === 'planning') {
        planPanel.style.display = 'block';
        planText.innerHTML = '<div class="empty-state">Agent is producing a plan...</div>';
        planActions.style.display = 'none';
        planBadge.textContent = 'Planning';
        planBadge.className = 'plan-status-badge planning';
      } else {
        planPanel.style.display = 'none';
      }
    
      // Show result panel when completed
      const resultPanel = document.getElementById('result-panel');
      const resultText = document.getElementById('result-text');
      if (orch && orch.result_text) {
        resultPanel.style.display = 'block';
        resultText.innerHTML = renderMarkdown(orch.result_text);
        // Fetch the report file if not already loaded
        if (!reportLoaded) {
          fetchReport();
        }
      } else {
        resultPanel.style.display = 'none';
      }
    
      // Show follow-ups panel
      renderFollowups(orch);
    }
    
    """
  end

  defp followups_js do
    ~S"""
    var followupsData = [];
    var editingFollowupId = null;
    
    function renderFollowups(orch) {
      // Skip re-render while user is editing a follow-up
      if (editingFollowupId) return;
      const panel = document.getElementById('followups-panel');
      const list = document.getElementById('followups-list');
      const followups = (orch && orch.follow_ups) || [];
      followupsData = followups;
      if (followups.length === 0) {
        panel.style.display = 'none';
        return;
      }
      panel.style.display = 'block';
      list.innerHTML = followups.map(function(fu) {
        var statusCls = fu.status || 'proposed';
        var labelsHtml = (fu.labels || []).map(function(l) {
          return '<span class="fu-label">' + esc(l) + '</span>';
        }).join('');
        var actionsHtml = '';
        if (fu.status === 'proposed') {
          actionsHtml = '<button class="btn-accept" onclick="acceptFollowup(\'' + fu.id + '\')">Accept</button>' +
            '<button class="btn-fu-edit" onclick="toggleFollowupEdit(\'' + fu.id + '\')">Edit</button>' +
            '<button class="btn-reject" onclick="rejectFollowup(\'' + fu.id + '\')">Reject</button>';
        } else if (fu.status === 'accepted') {
          actionsHtml = '<span class="fu-status accepted">Accepted</span>';
          if (fu.created_issue_identifier) {
            actionsHtml += '<a class="fu-link" href="/board/issues/' + fu.created_issue_id + '">'
              + esc(fu.created_issue_identifier) + '</a>';
          }
        } else {
          actionsHtml = '<span class="fu-status rejected">Rejected</span>';
        }
        var editForm = '<div class="fu-edit-form" id="fu-edit-' + fu.id + '" style="display:none;">' +
          '<input type="text" id="fu-edit-title-' + fu.id + '"'
          + ' value="' + esc(fu.title || '') + '" placeholder="Title">' +
          '<textarea id="fu-edit-desc-' + fu.id + '" placeholder="Description">'
          + esc(fu.description || '') + '</textarea>' +
          '<input type="text" id="fu-edit-labels-' + fu.id + '"'
          + ' value="' + esc((fu.labels || []).join(', ')) + '" placeholder="Labels (comma-separated)">' +
          '<div class="fu-edit-btns">' +
            '<button class="btn-accept" onclick="saveFollowupEdit(\'' + fu.id + '\')">Save</button>' +
            '<button class="btn-reject" onclick="toggleFollowupEdit(\'' + fu.id + '\')">Cancel</button>' +
          '</div></div>';
        return '<div class="followup-card ' + statusCls + '">' +
          '<div class="fu-title" id="fu-view-' + fu.id + '">' + esc(fu.title || '') + '</div>' +
          (fu.description ? '<div class="fu-desc">' + esc(fu.description.slice(0, 200)) + '</div>' : '') +
          (labelsHtml ? '<div class="fu-labels">' + labelsHtml + '</div>' : '') +
          '<div class="fu-actions">' + actionsHtml + '</div>' +
          editForm +
          '</div>';
      }).join('');
    }
    
    function toggleFollowupEdit(fuId) {
      var form = document.getElementById('fu-edit-' + fuId);
      if (!form) return;
      var opening = form.style.display === 'none';
      form.style.display = opening ? 'flex' : 'none';
      editingFollowupId = opening ? fuId : null;
    }
    
    async function saveFollowupEdit(fuId) {
      var title = document.getElementById('fu-edit-title-' + fuId).value.trim();
      var desc = document.getElementById('fu-edit-desc-' + fuId).value;
      var labelsStr = document.getElementById('fu-edit-labels-' + fuId).value;
      var labels = labelsStr.split(',').map(function(l) { return l.trim(); }).filter(function(l) { return l !== ''; });
      editingFollowupId = null;
      try {
        var res = await fetch('/board/api/issues/' + ISSUE_ID + '/follow-ups/' + fuId, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ title: title, description: desc, labels: labels })
        });
        if (res.ok) pollActivity();
      } catch (err) { console.error('Edit follow-up failed:', err); }
    }
    
    async function acceptFollowup(fuId) {
      var res = await fetch('/board/api/issues/' + ISSUE_ID + '/follow-ups/' + fuId + '/accept', {method: 'POST'});
      if (res.ok) pollActivity();
    }
    
    async function rejectFollowup(fuId) {
      var res = await fetch('/board/api/issues/' + ISSUE_ID + '/follow-ups/' + fuId + '/reject', {method: 'POST'});
      if (res.ok) pollActivity();
    }
    
    """
  end

  defp render_events_js do
    ~S"""
    function renderEvents(events) {
      const feed = document.getElementById('activity-feed');
      if (events.length === 0) {
        feed.innerHTML = '<div class="empty-state">Waiting for agent...</div>';
        return;
      }
    
      // Filter out noisy/duplicate events
      const filtered = events.filter(ev => {
        // Skip token_usage_updated (shown in header instead)
        if (ev.event === 'token_usage_updated') return false;
        return true;
      });
    
      feed.innerHTML = filtered.map((ev, idx) => {
        if (!ev) return '';
        const cls = (ev.event || 'default').replace(/[^a-zA-Z0-9_-]/g, '');
        const time = ev.timestamp ? formatTime(ev.timestamp) : '';
        let body = '';
        let detailText = '';
        let hasDetail = false;
    
        switch(ev.event) {
          case 'tool_use':
            const summary = ev.detail ? `: ${truncate(String(ev.detail), 80)}` : '';
            body = `<span class="tool-name">${esc(String(ev.tool || 'unknown'))}</span>`
              + `<span class="detail-summary">${esc(summary)}</span>`;
            if (ev.detail) {
              hasDetail = true;
              detailText = String(ev.detail);
            }
            break;
          case 'agent_message':
            const msgText = ev.message != null ? String(ev.message) : '';
            const shortMsg = truncate(msgText, 120);
            body = `<span class="msg">${esc(shortMsg)}</span>`;
            if (msgText.length > 120) {
              hasDetail = true;
              detailText = msgText;
            }
            break;
          case 'agent_output':
            body = `<span class="msg">${esc(truncate(ev.line != null ? String(ev.line) : '', 200))}</span>`;
            break;
          case 'session_started':
            body = 'Agent started';
            break;
          case 'system_info':
            body = 'Claude connected';
            break;
          case 'turn_completed':
            body = '<strong>Turn completed</strong>';
            break;
          case 'session_stopped':
            body = 'Session ended';
            break;
          default:
            body = esc(ev.event || 'event');
        }
    
        const detailHtml = hasDetail
          ? `<div class="detail-block">${esc(detailText)}</div>`
          : '';
        const detailCls = hasDetail ? ' has-detail' : '';
        const onclick = hasDetail ? ` onclick="toggleDetail(this)"` : '';
    
        return `<div class="event ${cls}${detailCls}"${onclick}>`
          + `<span class="time">${time}</span>${body}${detailHtml}</div>`;
      }).join('');
    
      // Auto-scroll to bottom
      feed.scrollTop = feed.scrollHeight;
    }
    
    """
  end

  defp edit_js do
    ~S"""
    function toggleDetail(el) {
      el.classList.toggle('expanded');
    }
    
    // --- Edit mode ---
    let editing = false;
    let issueData = null;
    
    async function loadIssueData() {
      try {
        var res = await fetch('/board/api/issues/' + ISSUE_ID);
        if (res.ok) {
          issueData = await res.json();
          // Populate product badge in view mode
          if (issueData.product_id) {
            var prodRes = await fetch('/board/api/products');
            if (prodRes.ok) {
              var prodData = await prodRes.json();
              var prod = (prodData.products || []).find(function(p) { return p.id === issueData.product_id; });
              if (prod) {
                document.getElementById('issue-product').textContent = prod.name;
              }
            }
          }
          // Populate project badge in view mode
          if (issueData.project_id) {
            var projRes = await fetch('/board/api/projects');
            if (projRes.ok) {
              var projData = await projRes.json();
              var proj = (projData.projects || []).find(function(p) { return p.id === issueData.project_id; });
              if (proj) {
                document.getElementById('issue-project').textContent = proj.name;
              }
            }
          }
        }
      } catch(e) {}
    }
    
    """
  end

  defp kb_and_actions_js do
    ~S"""
    // Send to KB
    async function checkKBAvailable() {
      try {
        var res = await fetch('/board/api/settings');
        if (res.ok) {
          var settings = await res.json();
          var kbType = settings.kb_type || 'local';
          var vaultPath = settings.kb_vault_path || '';
          // Local type works without vault_path (uses default dir)
          if (kbType === 'local' || vaultPath !== '') {
            document.getElementById('send-to-kb-btn').style.display = '';
          }
        }
      } catch(e) {}
    }
    checkKBAvailable();
    
    async function sendToKB() {
      if (!confirm('Send this issue and its reports to the Knowledge Base?')) return;
      var btn = document.getElementById('send-to-kb-btn');
      btn.disabled = true;
      btn.textContent = 'Sending...';
      try {
        var res = await fetch('/board/api/vault/send', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ issue_id: ISSUE_ID })
        });
        var data = await res.json();
        if (data.ok) {
          var paths = (data.notes_written || []).map(function(p) { return p.split('/').pop(); }).join(', ');
          var sourceMsg = data.source === 'reports' ? 'from agent reports' : 'from issue description';
          showToast('Sent to KB (' + sourceMsg + '): ' + paths, { type: 'success' });
          btn.textContent = 'Sent to KB';
          btn.title = 'Last sent: ' + new Date().toLocaleString();
          btn.classList.add('kb-sent');
          setTimeout(function() { btn.disabled = false; }, 2000);
        } else {
          showToast('Send failed: ' + (data.error || 'unknown'), { type: 'error' });
          btn.textContent = 'Send to KB';
          btn.disabled = false;
        }
      } catch(err) {
        showToast('Send failed: ' + err.message, { type: 'error' });
        btn.textContent = 'Send to KB';
        btn.disabled = false;
      }
    }
    
    function toggleRerunPanel() {
      var panel = document.getElementById('rerun-panel');
      panel.style.display = panel.style.display === 'none' ? '' : 'none';
      if (panel.style.display !== 'none') {
        document.getElementById('rerun-hint').focus();
      }
    }
    
    async function rerunIssue() {
      var hint = document.getElementById('rerun-hint').value.trim();
      if (!hint) {
        showToast('Please provide feedback for the rerun.', { type: 'error' });
        return;
      }
      if (!confirm('Rerun the agent with this feedback? The issue will move back to In Progress.')) return;
      try {
        var res = await fetch('/board/api/issues/' + ISSUE_ID + '/rerun', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ hint: hint })
        });
        var data = await res.json();
        if (data.ok) {
          showToast('Agent rerun started', { type: 'success' });
          document.getElementById('rerun-panel').style.display = 'none';
          document.getElementById('rerun-hint').value = '';
          pollActivity();
        } else {
          showToast('Rerun failed: ' + (data.error || 'unknown'), { type: 'error' });
        }
      } catch(err) {
        showToast('Rerun failed: ' + err.message, { type: 'error' });
      }
    }
    
    async function deleteIssue() {
      if (!confirm('Delete ' + IDENTIFIER + '?')) return;
      try {
        var res = await fetch('/board/api/issues/' + ISSUE_ID, { method: 'DELETE' });
        if (res.ok) {
          window.location.href = '/board';
        } else {
          alert('Delete failed: ' + res.status);
        }
      } catch (err) {
        alert('Delete failed: ' + err.message);
      }
    }
    
    function toggleEdit() {
      editing = !editing;
      var viewMode = document.getElementById('view-mode');
      var editMode = document.getElementById('edit-mode');
      var btn = document.getElementById('edit-btn');
    
      if (editing) {
        viewMode.style.display = 'none';
        editMode.style.display = 'block';
        btn.textContent = 'Cancel';
        btn.classList.add('active');
        populateEditForm();
      } else {
        viewMode.style.display = 'block';
        editMode.style.display = 'none';
        btn.textContent = 'Edit';
        btn.classList.remove('active');
      }
    }
    
    async function populateEditForm() {
      if (!issueData) await loadIssueData();
      if (!issueData) return;
    
      document.getElementById('edit-title').value = issueData.title || '';
      document.getElementById('edit-description').value = issueData.description || '';
      document.getElementById('edit-priority').value = (issueData.priority || 0).toString();
      document.getElementById('edit-labels').value = (issueData.labels || []).join(', ');
    
      // Populate state select
      var stateSelect = document.getElementById('edit-state');
      stateSelect.innerHTML = '';
      try {
        var statesRes = await fetch('/board/api/states');
        if (statesRes.ok) {
          var statesData = await statesRes.json();
          (statesData.states || []).forEach(function(s) {
            var opt = document.createElement('option');
            opt.value = s; opt.textContent = s;
            if (s === issueData.state) opt.selected = true;
            stateSelect.appendChild(opt);
          });
        }
      } catch(e) {}
    
      // Populate product select
      var prodSelect = document.getElementById('edit-product');
      prodSelect.innerHTML = '<option value="">No product</option>';
      try {
        var prodRes = await fetch('/board/api/products');
        if (prodRes.ok) {
          var prodData = await prodRes.json();
          (prodData.products || []).forEach(function(p) {
            var opt = document.createElement('option');
            opt.value = p.id; opt.textContent = p.name;
            if (p.id === issueData.product_id) opt.selected = true;
            prodSelect.appendChild(opt);
          });
        }
      } catch(e) {}
    
      // Populate project select
      var projSelect = document.getElementById('edit-project');
      projSelect.innerHTML = '<option value="">No project</option>';
      try {
        var projRes = await fetch('/board/api/projects');
        if (projRes.ok) {
          var projData = await projRes.json();
          (projData.projects || []).forEach(function(p) {
            var opt = document.createElement('option');
            opt.value = p.id; opt.textContent = p.name;
            if (p.id === issueData.project_id) opt.selected = true;
            projSelect.appendChild(opt);
          });
        }
      } catch(e) {}
    
      document.getElementById('edit-title').focus();
    }
    
    async function saveEdit() {
      var data = {
        title: document.getElementById('edit-title').value,
        description: document.getElementById('edit-description').value,
        state: document.getElementById('edit-state').value,
        priority: parseInt(document.getElementById('edit-priority').value) || 0,
        labels: document.getElementById('edit-labels').value
          .split(',').map(function(l) { return l.trim(); }).filter(Boolean),
        product_id: document.getElementById('edit-product').value || null,
        project_id: document.getElementById('edit-project').value || null
      };
    
      try {
        var res = await fetch('/board/api/issues/' + ISSUE_ID, {
          method: 'PATCH',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify(data)
        });
        if (res.ok) {
          issueData = await res.json();
          // Update view mode
          document.getElementById('issue-title').textContent = issueData.title;
          document.getElementById('description').innerHTML =
            renderMarkdown(issueData.description || 'No description.');
          var badge = document.getElementById('state-badge');
          badge.textContent = issueData.state;
          badge.className = 'badge ' + issueData.state.toLowerCase().replace(/\s+/g, '-');
          var priEl = document.getElementById('issue-priority');
          priEl.textContent = 'P' + (issueData.priority || 0);
          priEl.className = 'priority-badge priority-' + (issueData.priority || 0);
          document.getElementById('issue-labels').innerHTML = (issueData.labels || []).map(function(l) {
            return '<span class="label">' + esc(l) + '</span>';
          }).join(' ');
          // Update product badge
          var prodSelect = document.getElementById('edit-product');
          var selProdOpt = prodSelect.options[prodSelect.selectedIndex];
          document.getElementById('issue-product').textContent =
            selProdOpt && selProdOpt.value ? selProdOpt.textContent : '';
          // Update project badge
          var projSelect = document.getElementById('edit-project');
          var selOpt = projSelect.options[projSelect.selectedIndex];
          document.getElementById('issue-project').textContent = selOpt && selOpt.value ? selOpt.textContent : '';
          // Exit edit mode
          toggleEdit();
        } else {
          var errData = await res.json().catch(function() { return {}; });
          showToast('Save failed: ' + esc(errData.error || 'unknown error'), {type: 'error'});
        }
      } catch(e) {
        console.error('Save error:', e);
        showToast('Save failed: ' + esc(e.message || 'network error'), {type: 'error'});
      }
    }
    
    // Ctrl+S to save while editing
    document.addEventListener('keydown', function(e) {
      if (editing && e.key === 's' && (e.ctrlKey || e.metaKey)) {
        e.preventDefault();
        saveEdit();
      }
      if (editing && e.key === 'Escape') {
        toggleEdit();
      }
    });
    
    """
  end

  defp skills_js do
    ~S"""
    // --- Skills Management ---
    var allSkills = [];
    var allGroups = [];
    var issueSkillIds = [];
    var issueGroupIds = [];
    
    async function loadSkillsData() {
      try {
        var [skillsRes, groupsRes, issueRes] = await Promise.all([
          fetch('/board/api/skills'),
          fetch('/board/api/skill-groups'),
          fetch('/board/api/issues/' + ISSUE_ID)
        ]);
        if (skillsRes.ok) { var d = await skillsRes.json(); allSkills = d.skills || []; }
        if (groupsRes.ok) { var d = await groupsRes.json(); allGroups = d.skill_groups || []; }
        if (issueRes.ok) {
          var d = await issueRes.json();
          issueSkillIds = d.skill_ids || [];
          issueGroupIds = d.skill_group_ids || [];
        }
        renderSkillPills();
        populateSkillPicker();
      } catch(e) { console.error('Skills load error:', e); }
    }
    
    function renderSkillPills() {
      var container = document.getElementById('skill-pills');
      var pills = [];
    
      issueSkillIds.forEach(function(sid) {
        var s = allSkills.find(function(sk) { return sk.id === sid; });
        if (s) {
          pills.push('<span class="skill-pill" title="' + esc(s.description || '') + '">' +
            esc(s.name) +
            '<button class="skill-pill-remove" aria-label="Remove skill: ' + esc(s.name) + '" onclick="removeSkillFromIssue(\'' + sid + '\')">&times;</button>' +
          '</span>');
        }
      });
    
      issueGroupIds.forEach(function(gid) {
        var g = allGroups.find(function(gr) { return gr.id === gid; });
        if (g) {
          pills.push('<span class="skill-pill group-pill" title="Group: ' + esc(g.description || '') + '">' +
            esc(g.name) + ' (' + (g.skill_ids || []).length + ')' +
            '<button class="skill-pill-remove" aria-label="Remove group: ' + esc(g.name) + '" onclick="removeGroupFromIssue(\'' + gid + '\')">&times;</button>' +
          '</span>');
        }
      });
    
      container.innerHTML = pills.length > 0 ? pills.join('') : '<span class="meta">No skills assigned</span>';
    }
    
    function populateSkillPicker() {
      var skillSelect = document.getElementById('add-skill-select');
      skillSelect.innerHTML = '<option value="">Select a skill...</option>';
      allSkills.forEach(function(s) {
        if (issueSkillIds.indexOf(s.id) === -1) {
          skillSelect.innerHTML += '<option value="' + s.id + '">'
            + '[' + esc(s.category) + '] ' + esc(s.name) + '</option>';
        }
      });
    
      var groupSelect = document.getElementById('add-group-select');
      groupSelect.innerHTML = '<option value="">Select a group...</option>';
      allGroups.forEach(function(g) {
        if (issueGroupIds.indexOf(g.id) === -1) {
          groupSelect.innerHTML += '<option value="' + g.id + '">'
            + esc(g.name) + ' (' + (g.skill_ids || []).length + ' skills)</option>';
        }
      });
    }
    
    function toggleSkillPicker() {
      var picker = document.getElementById('skill-picker');
      picker.style.display = picker.style.display === 'none' ? '' : 'none';
    }
    
    async function addSkillToIssue(skillId) {
      if (!skillId) return;
      issueSkillIds.push(skillId);
      await saveIssueSkills();
    }
    
    async function addGroupToIssue(groupId) {
      if (!groupId) return;
      issueGroupIds.push(groupId);
      await saveIssueSkills();
    }
    
    async function removeSkillFromIssue(skillId) {
      issueSkillIds = issueSkillIds.filter(function(id) { return id !== skillId; });
      await saveIssueSkills();
    }
    
    async function removeGroupFromIssue(groupId) {
      issueGroupIds = issueGroupIds.filter(function(id) { return id !== groupId; });
      await saveIssueSkills();
    }
    
    async function saveIssueSkills() {
      try {
        var res = await fetch('/board/api/issues/' + ISSUE_ID + '/skills', {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({ skill_ids: issueSkillIds, skill_group_ids: issueGroupIds })
        });
        if (!res.ok) {
          var errData = await res.json().catch(function() { return {}; });
          showToast('Save skills failed: ' + esc(errData.error || 'unknown error'), {type: 'error'});
        }
        renderSkillPills();
        populateSkillPicker();
      } catch(e) {
        console.error('Save skills error:', e);
        showToast('Save skills failed: ' + esc(e.message || 'network error'), {type: 'error'});
      }
    }
    
    """
  end

  defp init_and_pipeline_js do
    ~S"""
    // Load issue data on init
    loadIssueData();
    loadSkillsData();
    loadPipelineContext();
    
    // --- Pipeline Context ---
    async function loadPipelineContext() {
      try {
        const res = await fetch('/board/api/pipelines');
        const data = await res.json();
        const pipelines = data.pipelines || [];
        const issueId = ISSUE_ID;
        const matches = [];
    
        pipelines.forEach(function(p) {
          (p.nodes || []).forEach(function(n) {
            if (n.type === 'issue' && n.issue_id === issueId) {
              matches.push({ pipeline: p, node: n });
            }
          });
        });
    
        const panel = document.getElementById('pipeline-ctx-panel');
        const content = document.getElementById('pipeline-ctx-content');
        if (matches.length === 0) return;
    
        panel.style.display = '';
        var html = '';
        for (var m = 0; m < matches.length; m++) {
          var p = matches[m].pipeline;
          var nodeCount = (p.nodes || []).length;
    
          // Build mini progress bar
          var segHtml = '';
          (p.nodes || []).forEach(function(n) {
            var color = n.id === matches[m].node.id ? 'var(--accent)' : 'var(--border)';
            segHtml += '<div class="pipeline-progress-seg" style="background:' + color + '"></div>';
          });
    
          html += '<a class="pipeline-run-link" href="/board/pipeline/' + p.id + '">' +
            '<strong>' + esc(p.name) + '</strong>' +
            '<span style="color:var(--text-muted)">' + nodeCount + ' nodes</span>' +
            '</a>' +
            '<div class="pipeline-progress-bar">' + segHtml + '</div>';
        }
        content.innerHTML = html;
    
        // Check for active runs
        var activeRes = await fetch('/board/api/pipeline-runs/active');
        var activeData = await activeRes.json();
        var activeRuns = activeData.runs || [];
    
        matches.forEach(function(m) {
          var run = activeRuns.find(function(r) { return r.pipeline_id === m.pipeline.id; });
          if (run) {
            var nodeState = run.node_states[m.node.id] || 'pending';
            var stateColors = {
              pending: 'var(--text-muted)', running: 'var(--accent)',
              completed: 'var(--green)', failed: 'var(--red)', waiting_gate: 'var(--yellow)'
            };
            content.innerHTML += '<div style="margin-top:6px;font-size:0.8rem;color:'
              + (stateColors[nodeState] || 'var(--text-muted)') + '">'
              + 'Pipeline running \u2014 this step: ' + nodeState + '</div>';
          }
        });
      } catch(e) {}
    }
    
    """
  end

  defp plan_review_and_poll_js do
    ~S"""
    // --- Plan Review Actions ---
    async function approvePlan() {
      try {
        const res = await fetch('/board/api/issues/' + ISSUE_ID + '/approve-plan', { method: 'POST' });
        if (res.ok) {
          pollActivity();
        } else {
          const data = await res.json();
          alert('Failed to approve plan: ' + (data.error || 'unknown error'));
        }
      } catch(e) {
        console.error('Approve plan error:', e);
      }
    }
    
    function showRejectForm() {
      document.getElementById('plan-actions').style.display = 'none';
      document.getElementById('plan-reject-form').style.display = 'block';
      document.getElementById('plan-feedback').focus();
    }
    
    function hideRejectForm() {
      document.getElementById('plan-reject-form').style.display = 'none';
      document.getElementById('plan-actions').style.display = 'flex';
    }
    
    async function rejectPlan() {
      var feedback = document.getElementById('plan-feedback').value.trim();
      try {
        const res = await fetch('/board/api/issues/' + ISSUE_ID + '/reject-plan', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ feedback: feedback || null })
        });
        if (res.ok) {
          document.getElementById('plan-reject-form').style.display = 'none';
          document.getElementById('plan-feedback').value = '';
          pollActivity();
        } else {
          const data = await res.json();
          alert('Failed to reject plan: ' + (data.error || 'unknown error'));
        }
      } catch(e) {
        console.error('Reject plan error:', e);
      }
    }
    
    // Poll every 2 seconds
    pollActivity();
    setInterval(pollActivity, 2000);
    """
  end
end

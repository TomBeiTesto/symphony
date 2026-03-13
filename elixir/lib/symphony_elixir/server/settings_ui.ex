defmodule SymphonyElixir.Server.SettingsUI do
  @moduledoc """
  Settings page for Symphony — configure git credentials, AI provider,
  agent command, and tracker settings via a web UI.
  """

  @doc "Render the full Settings HTML page."
  @spec render() :: String.t()
  def render do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Symphony Settings</title>
      <style>
    #{css()}
      </style>
    </head>
    <body>
    #{SymphonyElixir.Server.UIHelpers.nav_topbar("settings")}

      <main class="settings-page">
        <div class="settings-container">

          <div class="settings-saved" id="saved-banner">Settings saved</div>

          <!-- Git Provider -->
          <section class="settings-section">
            <h2>
              <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 19c-5 1.5-5-2.5-7-3m14 6v-3.87a3.37 3.37 0 0 0-.94-2.61c3.14-.35 6.44-1.54 6.44-7A5.44 5.44 0 0 0 20 4.77 5.07 5.07 0 0 0 19.91 1S18.73.65 16 2.48a13.38 13.38 0 0 0-7 0C6.27.65 5.09 1 5.09 1A5.07 5.07 0 0 0 5 4.77a5.44 5.44 0 0 0-1.5 3.78c0 5.42 3.3 6.61 6.44 7A3.37 3.37 0 0 0 9 18.13V22"/></svg>
              Git Provider
            </h2>
            <p class="section-desc">Configure which git host to use for cloning repositories and how to authenticate.</p>

            <div class="form-row">
              <div class="form-group">
                <label for="git_provider">Provider</label>
                <select id="git_provider">
                  <option value="gitlab">GitLab</option>
                  <option value="github">GitHub</option>
                  <option value="bitbucket">Bitbucket</option>
                  <option value="other">Other</option>
                </select>
              </div>
              <div class="form-group">
                <label for="git_host">Host URL</label>
                <input type="text" id="git_host" placeholder="https://gitlab.com">
              </div>
            </div>
            <div class="form-group">
              <label for="git_token">Personal Access Token</label>
              <div class="token-input-wrap">
                <input type="password" id="git_token" placeholder="glpat-xxxxxxxxxxxx or ghp_xxxxxxxxxxxx" autocomplete="off">
                <button type="button" class="btn-icon toggle-vis" onclick="toggleTokenVisibility('git_token')">
                  <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>
                </button>
              </div>
              <small class="help-text">Used to clone private repositories. For GitLab use a Personal Access Token (read_repository scope). For GitHub use a Fine-grained PAT.</small>
            </div>
          </section>

          <!-- AI / Agent -->
          <section class="settings-section">
            <h2>
              <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 2a2 2 0 012 2c0 .74-.4 1.39-1 1.73V7h1a7 7 0 017 7h1a2 2 0 110 4h-1.07A7 7 0 0113 22h-2a7 7 0 01-6.93-4H3a2 2 0 110-4h1a7 7 0 017-7h1V5.73c-.6-.34-1-.99-1-1.73a2 2 0 012-2z"/></svg>
              AI Provider &amp; Agent
            </h2>
            <p class="section-desc">Choose which AI model to use as the coding agent. The agent command is what Symphony invokes for each issue.</p>

            <div class="form-row">
              <div class="form-group">
                <label for="ai_provider">AI Provider</label>
                <select id="ai_provider">
                  <option value="claude">Claude (Anthropic)</option>
                  <option value="openai">OpenAI / ChatGPT</option>
                  <option value="gemini">Gemini (Google)</option>
                  <option value="ollama">Ollama (local)</option>
                  <option value="custom">Custom</option>
                </select>
              </div>
              <div class="form-group">
                <label for="ai_model">Model</label>
                <input type="text" id="ai_model" placeholder="claude-sonnet-4-20250514">
              </div>
            </div>
            <div class="form-group">
              <label for="agent_provider">Agent Backend</label>
              <select id="agent_provider">
                <option value="claude-code">Claude Code (claude --print)</option>
                <option value="codex">Codex (codex app-server)</option>
                <option value="custom">Custom Command</option>
              </select>
              <small class="help-text">Which agent protocol to use. Claude Code uses --print with streaming JSON. Codex uses the app-server JSON-RPC protocol.</small>
            </div>
            <div class="form-row">
              <div class="form-group">
                <label for="agent_command">Agent Command Override</label>
                <input type="text" id="agent_command" placeholder="Auto-detected from agent backend">
                <small class="help-text">Override the CLI command. Leave blank to use the default for the selected backend.</small>
              </div>
              <div class="form-group">
                <label for="agent_shell">Shell</label>
                <input type="text" id="agent_shell" placeholder="/bin/bash, pwsh, cmd.exe">
                <small class="help-text">Shell used to run hooks and agent processes. Leave blank for system default.</small>
              </div>
            </div>
            <div class="form-group">
              <label for="agent_allowed_tools">Allowed Tools</label>
              <input type="text" id="agent_allowed_tools" placeholder="WebSearch,WebFetch,Read,Write,Edit,Bash,Glob,Grep">
              <small class="help-text">Comma-separated list of tools the agent is allowed to use without prompting. Each becomes a <code>--allowedTools</code> flag. Leave blank to use Claude Code defaults (will prompt for each tool).</small>
            </div>
            <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px">
              <div class="form-group">
                <label for="agent_sandbox">Sandbox Mode</label>
                <select id="agent_sandbox">
                  <option value="">None (local)</option>
                  <option value="podman">Podman container</option>
                  <option value="docker">Docker container</option>
                </select>
                <small class="help-text">Run agents inside an isolated container. Only the workspace directory is mounted — agents cannot access other files on the host.</small>
              </div>
              <div class="form-group">
                <label for="agent_sandbox_image">Sandbox Image</label>
                <input type="text" id="agent_sandbox_image" placeholder="symphony-agent-sandbox">
                <small class="help-text">Container image name. Build with: <code>podman build -t symphony-agent-sandbox -f Dockerfile.agent-sandbox .</code></small>
              </div>
            </div>
          </section>

          <!-- Default Skills -->
          <section class="settings-section">
            <h2>
              <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg>
              Default Skills
            </h2>
            <p class="section-desc">Skills and skill groups auto-assigned to every new issue. Manage your skills library at <a href="/board/skills" style="color:var(--accent);">Skills Library</a>.</p>

            <div class="form-group">
              <label>Default Skills</label>
              <div class="default-skill-pills" id="default-skill-pills"></div>
              <select id="default-add-skill" onchange="defaultAddSkill(this.value); this.value='';">
                <option value="">+ Add skill or group...</option>
              </select>
              <small class="help-text">These skills are automatically assigned to all newly created issues.</small>
            </div>
          </section>

          <!-- Tracker -->
          <section class="settings-section">
            <h2>
              <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="2"/><line x1="3" y1="9" x2="21" y2="9"/><line x1="9" y1="21" x2="9" y2="9"/></svg>
              Issue Tracker
            </h2>
            <p class="section-desc">Override the tracker configured in your Workflow.md. These settings take effect on the next restart.</p>

            <div class="form-row">
              <div class="form-group">
                <label for="tracker_kind">Tracker Type</label>
                <select id="tracker_kind">
                  <option value="local">Local Board</option>
                  <option value="gitlab">GitLab Issues</option>
                </select>
              </div>
              <div class="form-group">
                <label for="tracker_project_slug">Project Slug / ID</label>
                <input type="text" id="tracker_project_slug" placeholder="my-project or 12345">
              </div>
            </div>
            <div class="form-row">
              <div class="form-group">
                <label for="tracker_endpoint">API Endpoint</label>
                <input type="text" id="tracker_endpoint" placeholder="https://gitlab.com/api/v4">
                <small class="help-text">Leave blank for provider default.</small>
              </div>
              <div class="form-group">
                <label for="tracker_api_key">Tracker API Key</label>
                <div class="token-input-wrap">
                  <input type="password" id="tracker_api_key" placeholder="API key or token" autocomplete="off">
                  <button type="button" class="btn-icon toggle-vis" onclick="toggleTokenVisibility('tracker_api_key')">
                    <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>
                  </button>
                </div>
              </div>
            </div>
          </section>

          <!-- Actions -->
          <div class="settings-actions">
            <button class="btn btn-ghost" onclick="resetSettings()">Reset to Defaults</button>
            <button class="btn btn-primary" onclick="saveSettings()">Save Settings</button>
          </div>

        </div>
      </main>

      <script>
    #{SymphonyElixir.Server.UIHelpers.esc_js()}
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
      UIHelpers.nav_active_css() <>
      UIHelpers.button_css() <>
      UIHelpers.form_css() <>
      ~S"""

      body { min-height: 100vh; }

      .topbar { position: sticky; top: 0; }

      .settings-page {
        max-width: 760px; margin: 0 auto; padding: 32px 24px 64px;
      }

      .settings-saved {
        display: none; padding: 10px 16px; background: #1a3a2a;
        border: 1px solid var(--green); border-radius: var(--radius-sm);
        color: var(--green); font-size: 0.85rem; font-weight: 500;
        margin-bottom: 24px; text-align: center;
      }
      .settings-saved.show { display: block; animation: fadeIn 0.2s ease; }

      @keyframes fadeIn { from { opacity: 0; transform: translateY(-4px); } to { opacity: 1; transform: translateY(0); } }

      .settings-section {
        background: var(--bg-secondary); border: 1px solid var(--border);
        border-radius: var(--radius); padding: 24px; margin-bottom: 24px;
      }
      .settings-section h2 {
        font-size: 1rem; font-weight: 600; margin-bottom: 6px;
        display: flex; align-items: center; gap: 8px;
      }
      .settings-section h2 svg { color: var(--accent); flex-shrink: 0; }
      .section-desc {
        font-size: 0.8rem; color: var(--text-muted); margin-bottom: 20px; line-height: 1.5;
      }

      /* Form overrides for settings — base from UIHelpers */
      .form-row { gap: 16px; }

      .token-input-wrap {
        display: flex; align-items: center; gap: 4px;
      }
      .token-input-wrap input { flex: 1; }

      .settings-actions {
        display: flex; justify-content: flex-end; gap: 10px;
        padding-top: 8px;
      }

      .default-skill-pills { display: flex; flex-wrap: wrap; gap: 4px; margin-bottom: 8px; min-height: 24px; }
      .ds-pill {
        display: inline-flex; align-items: center; gap: 3px;
        padding: 3px 10px; border-radius: 12px; font-size: 0.72rem; font-weight: 500;
        background: rgba(188,140,255,0.12); color: var(--purple); border: 1px solid rgba(188,140,255,0.25);
      }
      .ds-pill.group { background: rgba(88,166,255,0.12); color: var(--accent); border-color: rgba(88,166,255,0.25); }
      .ds-pill button {
        background: none; border: none; color: inherit; cursor: pointer;
        font-size: 0.8rem; padding: 0 2px; opacity: 0.6; line-height: 1;
      }
      .ds-pill button:hover { opacity: 1; }

      ::-webkit-scrollbar { width: 6px; }
      ::-webkit-scrollbar-track { background: transparent; }
      ::-webkit-scrollbar-thumb { background: var(--border); border-radius: 3px; }

      @media (max-width: 600px) {
        .form-row { flex-direction: column; gap: 0; }
        .settings-page { padding: 16px 12px 48px; }
      }
      """
  end

  defp javascript do
    ~S"""
    const API = '/board/api';

    const FIELDS = [
      'git_provider', 'git_token', 'git_host',
      'ai_provider', 'ai_model', 'agent_provider', 'agent_command', 'agent_shell', 'agent_allowed_tools', 'agent_sandbox', 'agent_sandbox_image',
      'tracker_kind', 'tracker_endpoint', 'tracker_api_key', 'tracker_project_slug'
    ];

    // Provider → default host mapping
    const DEFAULT_HOSTS = {
      gitlab: 'https://gitlab.com',
      github: 'https://github.com',
      bitbucket: 'https://bitbucket.org',
      other: ''
    };

    // AI provider → default model mapping
    const DEFAULT_MODELS = {
      claude: 'claude-sonnet-4-20250514',
      openai: 'gpt-4o',
      gemini: 'gemini-2.5-pro',
      ollama: 'llama3',
      custom: ''
    };

    // Auto-update host when provider changes
    document.getElementById('git_provider').addEventListener('change', (e) => {
      const host = document.getElementById('git_host');
      if (!host.value || Object.values(DEFAULT_HOSTS).includes(host.value)) {
        host.value = DEFAULT_HOSTS[e.target.value] || '';
      }
    });

    // Auto-update model when AI provider changes
    document.getElementById('ai_provider').addEventListener('change', (e) => {
      const model = document.getElementById('ai_model');
      if (!model.value || Object.values(DEFAULT_MODELS).includes(model.value)) {
        model.value = DEFAULT_MODELS[e.target.value] || '';
      }
    });

    // Default commands per agent backend
    const DEFAULT_AGENT_COMMANDS = {
      'claude-code': 'claude --print --output-format stream-json --verbose',
      'codex': 'codex app-server',
      'custom': ''
    };

    // Auto-update command placeholder when agent backend changes
    document.getElementById('agent_provider').addEventListener('change', (e) => {
      const cmd = document.getElementById('agent_command');
      cmd.placeholder = DEFAULT_AGENT_COMMANDS[e.target.value] || '';
    });

    function toggleTokenVisibility(fieldId) {
      const input = document.getElementById(fieldId);
      input.type = input.type === 'password' ? 'text' : 'password';
    }

    async function loadSettings() {
      try {
        const res = await fetch(`${API}/settings`);
        const data = await res.json();
        FIELDS.forEach(key => {
          const el = document.getElementById(key);
          if (el && data[key] !== undefined && data[key] !== null) {
            el.value = data[key];
          }
        });
      } catch (e) {
        console.error('Failed to load settings:', e);
      }
    }

    async function saveSettings() {
      const data = {};
      FIELDS.forEach(key => {
        const el = document.getElementById(key);
        if (el) data[key] = el.value;
      });

      try {
        const res = await fetch(`${API}/settings`, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(data)
        });

        if (res.ok) {
          const banner = document.getElementById('saved-banner');
          banner.classList.add('show');
          setTimeout(() => banner.classList.remove('show'), 2500);
        }
      } catch (e) {
        console.error('Save failed:', e);
        alert('Failed to save settings. Check console.');
      }
    }

    async function resetSettings() {
      if (!confirm('Reset all settings to defaults? This cannot be undone.')) return;

      try {
        const res = await fetch(`${API}/settings/reset`, { method: 'POST' });
        if (res.ok) {
          await loadSettings();
          const banner = document.getElementById('saved-banner');
          banner.textContent = 'Settings reset to defaults';
          banner.classList.add('show');
          setTimeout(() => {
            banner.classList.remove('show');
            banner.textContent = 'Settings saved';
          }, 2500);
        }
      } catch (e) {
        console.error('Reset failed:', e);
      }
    }

    // Keyboard: Ctrl+S to save
    document.addEventListener('keydown', (e) => {
      if ((e.ctrlKey || e.metaKey) && e.key === 's') {
        e.preventDefault();
        saveSettings();
      }
    });

    // --- Default Skills ---
    var allSkills = [];
    var allGroups = [];
    var defaultSkillIds = [];
    var defaultGroupIds = [];

    async function loadDefaultSkillsUI() {
      try {
        var [sr, gr, setRes] = await Promise.all([
          fetch(API + '/skills'), fetch(API + '/skill-groups'), fetch(API + '/settings')
        ]);
        if (sr.ok) { var d = await sr.json(); allSkills = d.skills || []; }
        if (gr.ok) { var d = await gr.json(); allGroups = d.skill_groups || []; }
        if (setRes.ok) {
          var s = await setRes.json();
          defaultSkillIds = (s.default_skill_ids || '').split(',').filter(Boolean);
          defaultGroupIds = (s.default_skill_group_ids || '').split(',').filter(Boolean);
        }
        renderDefaultSkillPills();
      } catch(e) { console.error('Default skills load error:', e); }
    }

    function renderDefaultSkillPills() {
      var container = document.getElementById('default-skill-pills');
      var pills = [];
      defaultSkillIds.forEach(function(sid) {
        var s = allSkills.find(function(sk) { return sk.id === sid; });
        if (s) pills.push('<span class="ds-pill">' + esc(s.name) + '<button onclick="defaultRemoveSkill(\'' + sid + '\')">&times;</button></span>');
      });
      defaultGroupIds.forEach(function(gid) {
        var g = allGroups.find(function(gr) { return gr.id === gid; });
        if (g) pills.push('<span class="ds-pill group">' + esc(g.name) + '<button onclick="defaultRemoveGroup(\'' + gid + '\')">&times;</button></span>');
      });
      container.innerHTML = pills.length > 0 ? pills.join('') : '<span style="font-size:0.75rem;color:var(--text-muted)">No default skills</span>';
      populateDefaultSkillSelect();
    }

    function populateDefaultSkillSelect() {
      var sel = document.getElementById('default-add-skill');
      sel.innerHTML = '<option value="">+ Add skill or group...</option>';
      var optSkills = document.createElement('optgroup');
      optSkills.label = 'Skills';
      allSkills.forEach(function(s) {
        if (defaultSkillIds.indexOf(s.id) === -1) {
          var opt = document.createElement('option');
          opt.value = 'skill:' + s.id;
          opt.textContent = '[' + s.category + '] ' + s.name;
          optSkills.appendChild(opt);
        }
      });
      sel.appendChild(optSkills);
      var optGroups = document.createElement('optgroup');
      optGroups.label = 'Groups';
      allGroups.forEach(function(g) {
        if (defaultGroupIds.indexOf(g.id) === -1) {
          var opt = document.createElement('option');
          opt.value = 'group:' + g.id;
          opt.textContent = g.name + ' (' + (g.skill_ids || []).length + ' skills)';
          optGroups.appendChild(opt);
        }
      });
      sel.appendChild(optGroups);
    }

    function defaultAddSkill(val) {
      if (!val) return;
      if (val.startsWith('skill:')) {
        var id = val.substring(6);
        if (defaultSkillIds.indexOf(id) === -1) defaultSkillIds.push(id);
      } else if (val.startsWith('group:')) {
        var id = val.substring(6);
        if (defaultGroupIds.indexOf(id) === -1) defaultGroupIds.push(id);
      }
      saveDefaultSkills();
    }

    function defaultRemoveSkill(sid) {
      defaultSkillIds = defaultSkillIds.filter(function(id) { return id !== sid; });
      saveDefaultSkills();
    }

    function defaultRemoveGroup(gid) {
      defaultGroupIds = defaultGroupIds.filter(function(id) { return id !== gid; });
      saveDefaultSkills();
    }

    async function saveDefaultSkills() {
      try {
        await fetch(API + '/settings', {
          method: 'PATCH',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({
            default_skill_ids: defaultSkillIds.join(','),
            default_skill_group_ids: defaultGroupIds.join(',')
          })
        });
        renderDefaultSkillPills();
      } catch(e) { console.error('Save default skills error:', e); }
    }

    // Init
    loadSettings();
    loadDefaultSkillsUI();
    """
  end
end

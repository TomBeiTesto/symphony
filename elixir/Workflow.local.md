---
tracker:
  kind: local
  project_slug: "SYM"
  active_states:
    - Todo
    - In Progress
  terminal_states:
    - Done
    - Cancelled
polling:
  interval_ms: 5000
workspace:
  root: ~/code/symphony-workspaces
agent:
  max_concurrent_agents: 5
  max_turns: 20
agent_process:
  command: claude
  approval_policy: never
hooks:
  after_run: |
    if [ -d "reports" ]; then
      mkdir -p "../_reports"
      cp reports/*.md "../_reports/" 2>/dev/null || true
    fi
---

You are working on issue `{{ issue.identifier }}`: **{{ issue.title }}**

{% if attempt %}
This is retry attempt #{{ attempt }}. Resume from the current workspace state — do not repeat completed work.
{% endif %}

## Issue Context

- **Identifier**: {{ issue.identifier }}
- **Title**: {{ issue.title }}
- **Status**: {{ issue.state }}
- **Priority**: {{ issue.priority }}
- **Labels**: {{ issue.labels }}

{% if issue.description %}
### Description

{{ issue.description }}
{% endif %}

{% if blocked_by %}
### Blocked By

The following issues must be completed before this one:
{% for blocker in blocked_by %}
- {{ blocker.identifier }} ({{ blocker.state }})
{% endfor %}
If any blockers are not yet resolved, note them and focus on what can be done independently.
{% endif %}

{% if product %}
### Product Context

This issue belongs to product **{{ product.name }}**{% if product.description %}: {{ product.description }}{% endif %}.

{% if product_projects.size > 0 %}
This product spans the following project directories — you have access to all of them:
{% for proj in product_projects %}
- **{{ proj.name }}**{% if proj.path %}: `{{ proj.path }}`{% endif %}{% if proj.description %} — {{ proj.description }}{% endif %}
{% endfor %}

Consider cross-project impact when making changes.
{% endif %}
{% endif %}

{% if project %}
{% unless product %}
### Project Context

This issue belongs to project **{{ project.name }}**{% if project.description %}: {{ project.description }}{% endif %}.
{% if project.path %}Working directory: `{{ project.path }}`{% endif %}
{% endunless %}
{% endif %}

## Instructions

1. Work only in the provided workspace directory.
2. Follow the issue description and acceptance criteria.
3. Run tests before completing if the project has a test suite.
4. Keep changes focused — do not expand scope beyond the issue.

{% if issue.labels contains "research" %}
### Research Mode

You are a **research agent**. Investigate the topic and produce a written report.

1. Research the topic thoroughly using available tools.
2. Create a `reports/` directory in the workspace.
3. Write your report to `reports/{{ issue.identifier }}.md`:
   - **Summary** — key findings in 2-3 sentences
   - **Details** — in-depth analysis with sections as appropriate
   - **Sources** — references and links consulted
   - **Recommendations** — actionable next steps (if applicable)
4. Be factual and cite sources where possible.
{% endif %}

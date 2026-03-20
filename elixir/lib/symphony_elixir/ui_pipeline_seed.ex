defmodule SymphonyElixir.UIPipelineSeed do
  @moduledoc """
  Seeds the "UI & Layout Design" pipeline template on startup.

  7-phase pipeline for creating professional, intuitive UI and layouts:
    Phase 1 (parallel): Design System Audit, UX Research & Patterns, Accessibility Audit
    Phase 2 (sequential): Layout Architecture → Human Gate (plan review)
    Phase 3 (parallel): Component Implementation, Responsive & Mobile, Interaction & Motion
    Phase 4 (sequential): Human Gate (code review)
    Phase 5 (parallel): Visual Polish & Theming, Accessibility Compliance
    Phase 6: Quality Gate (automated checks, auto-approve on pass)
    Phase 7: KB Sync → End

  Product/project is selected when starting a run.
  """

  require Logger

  alias SymphonyElixir.LocalBoard

  @pipeline_name "UI & Layout Design"

  @spec seed() :: :ok
  def seed do
    existing_pipelines = LocalBoard.list_pipelines()
    skill_id_map = build_skill_id_map()

    already_exists? = Enum.any?(existing_pipelines, fn p -> p.name == @pipeline_name end)

    unless already_exists? do
      create_pipeline(skill_id_map)
    end

    :ok
  end

  defp build_skill_id_map do
    LocalBoard.list_skills()
    |> Enum.map(fn s -> {s.name, s.id} end)
    |> Map.new()
  end

  defp create_pipeline(skill_id_map) do
    {nodes, edges} = build_graph(skill_id_map)

    attrs = %{
      "name" => @pipeline_name,
      "description" =>
        "End-to-end UI/layout pipeline. Audits the existing design system, researches UX patterns, " <>
          "architects responsive layouts, implements polished components with motion design, " <>
          "and verifies accessibility compliance. Produces production-ready, professional interfaces.",
      "nodes" => nodes,
      "edges" => edges,
      "settings" => %{}
    }

    case LocalBoard.create_pipeline(attrs) do
      {:ok, pipeline} ->
        Logger.info("Seeded pipeline template '#{@pipeline_name}' (#{pipeline.id})")

      {:error, reason} ->
        Logger.warning("Failed to seed UI pipeline template: #{inspect(reason)}")
    end
  end

  defp build_graph(skill_id_map) do
    x_center = 500
    col = 280
    row = 150

    # ── Phase 1: Research & Audit (3 parallel) ──
    y_p1 = 130

    design_audit =
      issue_node(
        "design-audit",
        "Design System Audit",
        "Inventory the existing design system: colors, typography, spacing tokens, component library, " <>
          "CSS architecture, and naming conventions. Identify inconsistencies, missing tokens, " <>
          "and components that need visual or structural updates. Output DESIGN_SYSTEM_AUDIT.md.",
        ["ui-design", "audit"],
        "ui-design-system-audit",
        skill_id_map,
        %{"x" => x_center - col, "y" => y_p1}
      )

    ux_research =
      issue_node(
        "ux-research",
        "UX Research & Patterns",
        "Research best-in-class UX patterns for the feature area. Analyze layout hierarchy, " <>
          "information density, whitespace rhythm, visual scanning paths (F-pattern, Z-pattern), " <>
          "and interaction paradigms. Reference real-world exemplars. Output UX_PATTERNS.md.",
        ["ui-design", "research"],
        "ui-ux-research",
        skill_id_map,
        %{"x" => x_center, "y" => y_p1}
      )

    a11y_audit =
      issue_node(
        "a11y-audit",
        "Accessibility Audit",
        "Audit the current UI for WCAG 2.1 AA compliance: color contrast ratios, keyboard navigation, " <>
          "screen reader landmarks, focus management, ARIA attributes, and semantic HTML. " <>
          "Flag violations and missing patterns. Output A11Y_AUDIT.md.",
        ["ui-design", "audit"],
        "ui-accessibility-audit",
        skill_id_map,
        %{"x" => x_center + col, "y" => y_p1}
      )

    # ── Phase 2: Layout Architecture → Plan Review ──
    y_p2 = y_p1 + row

    layout_arch =
      issue_node(
        "layout-arch",
        "Layout Architecture",
        "Design the layout structure from all research outputs. Define grid system, breakpoint strategy, " <>
          "component hierarchy, spacing scale, and responsive behavior. Produce a component tree " <>
          "with props/slots, a CSS architecture plan (BEM/utility/CSS-in-JS), and mockup descriptions " <>
          "for each breakpoint. Output LAYOUT_ARCHITECTURE.md.",
        ["ui-design", "layout"],
        "ui-layout-architecture",
        skill_id_map,
        %{"x" => x_center, "y" => y_p2}
      )

    y_plan_gate = y_p2 + row

    plan_gate =
      gate_node(
        "layout-review",
        "Review Layout Plan",
        "Review the layout architecture. Does the grid system handle all content scenarios? " <>
          "Are breakpoints sensible? Is the component hierarchy clean and composable? " <>
          "Approve to proceed with implementation, or reject with feedback.",
        "Does the layout plan use a consistent spacing scale, handle edge cases " <>
          "(empty states, overflow, long text), and follow the existing design system tokens? " <>
          "Approve to begin building, or reject with specific layout feedback.",
        %{"x" => x_center, "y" => y_plan_gate},
        "plan_review"
      )

    # ── Phase 3: Implementation (3 parallel) ──
    y_p3 = y_plan_gate + row

    components =
      issue_node(
        "component-impl",
        "Component Implementation",
        "Build the UI components following the approved layout architecture. Use the existing design " <>
          "system tokens. Implement semantic HTML structure, proper component composition, " <>
          "slot/prop APIs, and clean CSS. Focus on getting the structure and data flow right. " <>
          "Every component must be self-contained and reusable.",
        ["ui-design", "implement"],
        "ui-component-implementation",
        skill_id_map,
        %{"x" => x_center - col, "y" => y_p3}
      )

    responsive =
      issue_node(
        "responsive-mobile",
        "Responsive & Mobile",
        "Implement responsive behavior across all breakpoints. Mobile-first CSS, touch targets " <>
          "(min 44px), fluid typography, container queries where appropriate, and graceful " <>
          "degradation for constrained viewports. Test every layout at 320px, 768px, 1024px, 1440px.",
        ["ui-design", "responsive"],
        "ui-responsive-mobile",
        skill_id_map,
        %{"x" => x_center, "y" => y_p3}
      )

    motion =
      issue_node(
        "interaction-motion",
        "Interaction & Motion",
        "Add micro-interactions and motion design: hover/focus states, transitions between views, " <>
          "loading skeletons, scroll-driven animations, and entrance choreography. Follow the " <>
          "principle of purposeful motion — every animation must communicate state change or " <>
          "guide attention. Use CSS transitions/animations, respect prefers-reduced-motion.",
        ["ui-design", "motion"],
        "ui-interaction-motion",
        skill_id_map,
        %{"x" => x_center + col, "y" => y_p3}
      )

    # ── Phase 4: Code Review ──
    y_code_gate = y_p3 + row

    code_gate =
      gate_node(
        "ui-code-review",
        "UI Code Review",
        "Review all implemented components, responsive behavior, and interactions. " <>
          "Approve if the UI is polished and professional, reject with specific visual feedback.",
        "Is the code clean, well-structured, and using design tokens consistently? " <>
          "Do components render correctly at all breakpoints? Are interactions smooth and purposeful? " <>
          "Does it look and feel professional? Approve or reject with specific feedback.",
        %{"x" => x_center, "y" => y_code_gate},
        "code_review"
      )

    # ── Phase 5: Polish & A11y (2 parallel) ──
    y_p5 = y_code_gate + row

    polish =
      issue_node(
        "visual-polish",
        "Visual Polish & Theming",
        "Final visual pass: tighten spacing inconsistencies, verify color usage against the palette, " <>
          "check typography hierarchy, ensure consistent border radii and shadows, verify dark/light " <>
          "theme support if applicable. Add finishing touches: empty states, error states, " <>
          "loading states, truncation with tooltips. The UI should feel crisp and intentional.",
        ["ui-design", "polish"],
        "ui-visual-polish",
        skill_id_map,
        %{"x" => x_center - div(col, 2), "y" => y_p5}
      )

    a11y_fix =
      issue_node(
        "a11y-compliance",
        "Accessibility Compliance",
        "Fix all issues from the initial audit and verify new components. Ensure: proper heading " <>
          "hierarchy, ARIA labels on interactive elements, keyboard navigation with visible focus " <>
          "rings, color contrast ≥ 4.5:1 for text, screen reader announcements for dynamic content, " <>
          "and skip-to-content links. Run automated checks (axe-core or equivalent).",
        ["ui-design", "accessibility"],
        "ui-accessibility-compliance",
        skill_id_map,
        %{"x" => x_center + div(col, 2), "y" => y_p5}
      )

    # ── Phase 6: Quality Gate ──
    y_qgate = y_p5 + row

    quality_gate = %{
      "id" => "ui-quality-gate",
      "type" => "quality_gate",
      "label" => "UI Quality Check",
      "config" => %{
        "instructions" =>
          "Auto-approves if all predecessors completed. Manual review if any failed.",
        "auto_approve_condition" => "all_predecessors_completed"
      },
      "position" => %{"x" => x_center, "y" => y_qgate}
    }

    # ── Phase 7: KB Sync → End ──
    y_kb = y_qgate + row

    kb_sync = %{
      "id" => "ui-kb-sync",
      "type" => "kb_sync",
      "label" => "Sync to Knowledge Base",
      "config" => %{
        "auto_approve_condition" => "all_predecessors_completed"
      },
      "position" => %{"x" => x_center, "y" => y_kb}
    }

    y_end = y_kb + row

    all_nodes = [
      %{
        "id" => "start",
        "type" => "start",
        "label" => "Start",
        "config" => %{},
        "position" => %{"x" => x_center, "y" => 30}
      },
      design_audit,
      ux_research,
      a11y_audit,
      layout_arch,
      plan_gate,
      components,
      responsive,
      motion,
      code_gate,
      polish,
      a11y_fix,
      quality_gate,
      kb_sync,
      %{
        "id" => "end",
        "type" => "end",
        "label" => "End",
        "config" => %{},
        "position" => %{"x" => x_center, "y" => y_end}
      }
    ]

    all_edges = [
      # Start → Phase 1 (fan out)
      edge("e-start-design", "start", "design-audit"),
      edge("e-start-ux", "start", "ux-research"),
      edge("e-start-a11y", "start", "a11y-audit"),

      # Phase 1 → Layout Architecture (all three converge)
      edge("e-design-layout", "design-audit", "layout-arch"),
      edge("e-ux-layout", "ux-research", "layout-arch"),
      edge("e-a11y-layout", "a11y-audit", "layout-arch"),

      # Layout → Plan Gate → Implementation (fan out)
      edge("e-layout-gate", "layout-arch", "layout-review"),
      edge("e-plangate-components", "layout-review", "component-impl"),
      edge("e-plangate-responsive", "layout-review", "responsive-mobile"),
      edge("e-plangate-motion", "layout-review", "interaction-motion"),

      # Implementation → Code Review (converge)
      edge("e-components-codegate", "component-impl", "ui-code-review"),
      edge("e-responsive-codegate", "responsive-mobile", "ui-code-review"),
      edge("e-motion-codegate", "interaction-motion", "ui-code-review"),

      # Code Review → Polish & A11y (fan out)
      edge("e-codegate-polish", "ui-code-review", "visual-polish"),
      edge("e-codegate-a11y", "ui-code-review", "a11y-compliance"),

      # Polish & A11y → Quality Gate → KB Sync → End
      edge("e-polish-qgate", "visual-polish", "ui-quality-gate"),
      edge("e-a11y-qgate", "a11y-compliance", "ui-quality-gate"),
      edge("e-qgate-kb", "ui-quality-gate", "ui-kb-sync"),
      edge("e-kb-end", "ui-kb-sync", "end")
    ]

    {all_nodes, all_edges}
  end

  defp issue_node(id, label, description, labels, skill_name, skill_id_map, position) do
    skill_ids = skill_ids_for(skill_name, skill_id_map)

    %{
      "id" => id,
      "type" => "issue",
      "label" => label,
      "config" => %{
        "title" => label,
        "description" => description,
        "labels" => labels,
        "skill_ids" => skill_ids,
        "priority" => 3
      },
      "position" => position
    }
  end

  defp gate_node(id, label, instructions, gate_prompt, position, review_mode) do
    config = %{
      "instructions" => instructions,
      "gate_prompt" => gate_prompt
    }

    config = if review_mode, do: Map.put(config, "review_mode", review_mode), else: config

    %{
      "id" => id,
      "type" => "human_gate",
      "label" => label,
      "config" => config,
      "position" => position
    }
  end

  defp edge(id, source, target) do
    %{
      "id" => id,
      "source_node_id" => source,
      "target_node_id" => target,
      "source_port" => "output"
    }
  end

  defp skill_ids_for(skill_name, skill_id_map) do
    case Map.get(skill_id_map, skill_name) do
      nil -> []
      id -> [id]
    end
  end
end

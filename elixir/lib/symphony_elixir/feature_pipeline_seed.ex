defmodule SymphonyElixir.FeaturePipelineSeed do
  @moduledoc """
  Seeds the "Feature Implementation" pipeline template on startup.

  5-phase sequential pipeline:
    Phase 1 (parallel): KB Context Retrieval, Codebase Impact Analysis, Constraint Check
    Phase 2 (sequential): Implementation Plan → Human Gate (plan review)
    Phase 3 (sequential): Code Implementation → Human Gate (code review)
    Phase 4 (parallel): Test Verification, Documentation & Changelog
    Phase 4b: Quality Gate (automated test run, auto-approve on pass)
    Phase 5: KB Sync (auto-approve) → End

  Product/project is selected when starting a run.
  """

  require Logger

  alias SymphonyElixir.LocalBoard

  @pipeline_name "Feature Implementation"

  @doc """
  Seed the Feature Implementation pipeline template (once, not per product).
  Call this after LocalBoard and SkillsSeed have run.
  """
  @spec seed() :: :ok
  def seed do
    existing_pipelines = LocalBoard.list_pipelines()
    skill_id_map = build_skill_id_map()

    already_exists? =
      Enum.any?(existing_pipelines, fn p -> p.name == @pipeline_name end)

    unless already_exists? do
      create_feature_pipeline(skill_id_map)
    end

    :ok
  end

  defp build_skill_id_map do
    LocalBoard.list_skills()
    |> Enum.map(fn s -> {s.name, s.id} end)
    |> Map.new()
  end

  defp create_feature_pipeline(skill_id_map) do
    {nodes, edges} = build_graph(skill_id_map)

    attrs = %{
      "name" => @pipeline_name,
      "description" =>
        "General-purpose feature implementation pipeline. " <>
          "Analyzes KB context & codebase impact, generates a reviewed plan, " <>
          "implements with code review, then verifies and documents.",
      "nodes" => nodes,
      "edges" => edges,
      "settings" => %{}
    }

    case LocalBoard.create_pipeline(attrs) do
      {:ok, pipeline} ->
        Logger.info("Seeded pipeline template '#{@pipeline_name}' (#{pipeline.id})")

      {:error, reason} ->
        Logger.warning("Failed to seed feature pipeline template: #{inspect(reason)}")
    end
  end

  defp build_graph(skill_id_map) do
    # Layout constants
    x_center = 500
    col_spacing = 280
    row_gap = 150

    # ── Phase 1: Analyze (3 parallel) ──
    y_p1 = 130

    kb_context = issue_node("kb-context", "KB Context Retrieval",
      "Pull relevant architecture, business logic, constraints, and workflows from the Knowledge Base.",
      ["feature-implementation", "analysis"], "feature-kb-context", skill_id_map,
      %{"x" => x_center - col_spacing, "y" => y_p1})

    impact = issue_node("impact-analysis", "Codebase Impact Analysis",
      "Trace through the codebase to identify every file, module, and function affected by the feature.",
      ["feature-implementation", "analysis"], "feature-impact-analysis", skill_id_map,
      %{"x" => x_center, "y" => y_p1})

    constraints = issue_node("constraint-check", "Constraint Check",
      "Cross-reference the feature against known constraints, security boundaries, and data contracts.",
      ["feature-implementation", "analysis"], "feature-constraint-check", skill_id_map,
      %{"x" => x_center + col_spacing, "y" => y_p1})

    # ── Phase 2: Plan (sequential, gated) ──
    y_p2 = y_p1 + row_gap

    plan = issue_node("impl-plan", "Implementation Plan",
      "Generate a step-by-step implementation plan from all analysis outputs. " <>
        "Reads KB_CONTEXT.md, IMPACT_ANALYSIS.md, and CONSTRAINT_CHECK.md.",
      ["feature-implementation", "plan"], "feature-implementation-plan", skill_id_map,
      %{"x" => x_center, "y" => y_p2})

    y_plan_gate = y_p2 + row_gap
    plan_gate = gate_node("plan-review", "Review Plan",
      "Review the implementation plan. Approve to proceed with coding, " <>
        "reject with feedback to re-plan.",
      "Does the implementation plan cover all affected files, respect constraints, " <>
        "and have a sensible execution order? Approve to begin coding, or reject with specific feedback.",
      %{"x" => x_center, "y" => y_plan_gate})

    # ── Phase 3: Implement (sequential, gated) ──
    y_p3 = y_plan_gate + row_gap

    code = issue_node("code-impl", "Code Implementation",
      "Implement the feature by following the approved plan step by step.",
      ["feature-implementation", "implement"], "feature-code-implementation", skill_id_map,
      %{"x" => x_center, "y" => y_p3})

    y_code_gate = y_p3 + row_gap
    code_gate = gate_node("code-review", "Code Review",
      "Review the implementation. Approve if correct, reject with feedback to revise.",
      "Does the code match the approved plan? Are there bugs, missing edge cases, or style issues? " <>
        "Approve to proceed to testing, or reject with specific code review feedback.",
      %{"x" => x_center, "y" => y_code_gate})

    # ── Phase 4: Verify & Document (parallel) ──
    y_p4 = y_code_gate + row_gap

    tests = issue_node("test-verify", "Test Verification",
      "Write missing tests, fix broken tests, run the full test suite.",
      ["feature-implementation", "verify"], "feature-test-verification", skill_id_map,
      %{"x" => x_center - div(col_spacing, 2), "y" => y_p4})

    docs = issue_node("docs-changelog", "Documentation & Changelog",
      "Update documentation and changelog for the implemented feature.",
      ["feature-implementation", "docs"], "feature-docs-changelog", skill_id_map,
      %{"x" => x_center + div(col_spacing, 2), "y" => y_p4})

    # Quality gate after tests (auto-approve if tests pass)
    y_qgate = y_p4 + row_gap
    test_gate = %{
      "id" => "test-gate",
      "type" => "quality_gate",
      "label" => "Tests Pass?",
      "config" => %{
        "instructions" => "Auto-approves if all tests pass. Manual review if any fail.",
        "auto_approve_condition" => "all_predecessors_completed"
      },
      "position" => %{"x" => x_center, "y" => y_qgate}
    }

    # ── Phase 5: KB Sync → End ──
    y_kb = y_qgate + row_gap
    kb_sync = %{
      "id" => "kb-sync",
      "type" => "kb_sync",
      "label" => "Sync to Knowledge Base",
      "config" => %{
        "auto_approve_condition" => "all_predecessors_completed"
      },
      "position" => %{"x" => x_center, "y" => y_kb}
    }

    y_end = y_kb + row_gap

    # ── Assemble nodes ──
    all_nodes = [
      %{"id" => "start", "type" => "start", "label" => "Start",
        "config" => %{}, "position" => %{"x" => x_center, "y" => 30}},
      kb_context, impact, constraints,
      plan, plan_gate,
      code, code_gate,
      tests, docs, test_gate,
      kb_sync,
      %{"id" => "end", "type" => "end", "label" => "End",
        "config" => %{}, "position" => %{"x" => x_center, "y" => y_end}}
    ]

    # ── Assemble edges ──
    all_edges = [
      # Start → Phase 1 (fan out)
      edge("e-start-kb", "start", "kb-context"),
      edge("e-start-impact", "start", "impact-analysis"),
      edge("e-start-constraints", "start", "constraint-check"),

      # Phase 1 → Plan (all three converge)
      edge("e-kb-plan", "kb-context", "impl-plan"),
      edge("e-impact-plan", "impact-analysis", "impl-plan"),
      edge("e-constraints-plan", "constraint-check", "impl-plan"),

      # Plan → Gate → Code
      edge("e-plan-gate", "impl-plan", "plan-review"),
      edge("e-plangate-code", "plan-review", "code-impl"),

      # Code → Gate → Phase 4 (fan out)
      edge("e-code-gate", "code-impl", "code-review"),
      edge("e-codegate-tests", "code-review", "test-verify"),
      edge("e-codegate-docs", "code-review", "docs-changelog"),

      # Phase 4 → Test quality gate
      edge("e-tests-qgate", "test-verify", "test-gate"),
      edge("e-docs-qgate", "docs-changelog", "test-gate"),

      # Quality gate → KB sync → End
      edge("e-qgate-kb", "test-gate", "kb-sync"),
      edge("e-kb-end", "kb-sync", "end")
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

  defp gate_node(id, label, instructions, gate_prompt, position) do
    %{
      "id" => id,
      "type" => "human_gate",
      "label" => label,
      "config" => %{
        "instructions" => instructions,
        "gate_prompt" => gate_prompt
      },
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

defmodule SymphonyElixir.HardeningSeed do
  @moduledoc """
  Seeds the "Product Health & Hardening" pipeline for each product on startup.

  4-phase pipeline with per-finding human gates:
    Phase 1 (parallel): Lint & Format, Dead Code, Dependency Audit, Security Scan
    Phase 2 (parallel): DRY Analysis, Error Handling, Type Safety
    Phase 3 (parallel): Test Style, Infrastructure Review, Frontend E2E (Playwright)
    Phase 4 (sequential): Test Coverage Audit
    Final: Summary Report → End

  Each hardening step follows a 3-node pattern:
    scan-{id} → gate-{id} → apply-{id}
  The scan agent analyzes and outputs structured findings (no code changes).
  The human reviews each finding individually (accept/discard per finding).
  The apply agent applies only the accepted findings.
  """

  require Logger

  alias SymphonyElixir.LocalBoard

  @pipeline_name "Product Health & Hardening"

  # Phase definitions: {node_id, scan_skill, apply_skill, label, description}
  @phase_1 [
    {"lint-format", "hardening-lint-format-scan", "hardening-lint-format-apply", "Lint & Format",
     "Lint and auto-format the entire codebase. Detects tech stack per subproject and runs appropriate tools (ruff, credo, eslint, gofmt, etc.)."},
    {"dead-code", "hardening-dead-code-scan", "hardening-dead-code-apply", "Dead Code Removal",
     "Find and remove unused functions, modules, imports, unreachable branches, and stale files across all subprojects."},
    {"dep-audit", "hardening-dependency-audit-scan", "hardening-dependency-audit-apply", "Dependency Audit",
     "Audit all dependencies for vulnerabilities, outdated versions, and unused packages."},
    {"security-scan", "hardening-security-scan-scan", "hardening-security-scan-apply", "Security Scan",
     "Scan for OWASP top 10 vulnerabilities: injection, path traversal, hardcoded secrets, auth gaps."}
  ]

  @phase_2 [
    {"dry-analysis", "hardening-dry-analysis-scan", "hardening-dry-analysis-apply", "DRY Analysis",
     "Find and eliminate code duplication. Extract shared modules and reduce copy-paste across all subprojects."},
    {"error-handling", "hardening-error-handling-scan", "hardening-error-handling-apply", "Error Handling Audit",
     "Fix bare rescues, swallowed errors, missing error tuples, and inconsistent error patterns."},
    {"type-safety", "hardening-type-safety-scan", "hardening-type-safety-apply", "Type Safety",
     "Add missing type annotations, fix type errors, improve type coverage (dialyzer, mypy, tsc strict, etc.)."}
  ]

  @phase_3 [
    {"test-style", "hardening-test-style-scan", "hardening-test-style-apply", "Test Style & Consistency",
     "Audit and fix test naming conventions, setup patterns, assertion style, and helper usage."},
    {"infra-review", "hardening-infrastructure-scan", "hardening-infrastructure-apply", "Infrastructure Review",
     "Review and fix CI/CD, Dockerfiles, Makefiles, config files, .gitignore, and deployment scripts."},
    {"playwright-e2e", "hardening-playwright-e2e-scan", "hardening-playwright-e2e-apply", "Frontend E2E (Playwright)",
     "Fix broken Playwright tests, add missing E2E coverage. Marks as N/A if no frontend exists."}
  ]

  @phase_4 [
    {"test-coverage", "hardening-test-coverage-scan", "hardening-test-coverage-apply", "Test Coverage Audit",
     "Find coverage gaps, remove duplicate tests, add missing unit tests. Runs last after all code changes."}
  ]

  @summary {"summary-report", "hardening-pipeline-summary", "Pipeline Summary Report",
   "Summarize everything done across all phases: metrics, accepted/rejected findings, final state."}

  @doc """
  Seed the Product Health & Hardening pipeline template (once, not per product).
  Product is selected when starting a run.
  Call this after LocalBoard and SkillsSeed have run.
  """
  @spec seed() :: :ok
  def seed do
    existing_pipelines = LocalBoard.list_pipelines()
    skill_id_map = build_skill_id_map()

    already_exists? =
      Enum.any?(existing_pipelines, fn p -> p.name == @pipeline_name end)

    unless already_exists? do
      create_hardening_pipeline(skill_id_map)
    end

    :ok
  end

  defp build_skill_id_map do
    LocalBoard.list_skills()
    |> Enum.map(fn s -> {s.name, s.id} end)
    |> Map.new()
  end

  defp create_hardening_pipeline(skill_id_map) do
    {nodes, edges} = build_graph(skill_id_map)

    attrs = %{
      "name" => @pipeline_name,
      "description" =>
        "4-phase codebase hardening pipeline with per-finding review. " <>
          "Each step: scan → human gate (accept/discard per finding) → apply accepted fixes. " <>
          "Agents auto-detect tech stack (Elixir, Python, TypeScript, Go, Rust, Ruby, etc.).",
      "nodes" => nodes,
      "edges" => edges,
      "settings" => %{}
    }

    case LocalBoard.create_pipeline(attrs) do
      {:ok, pipeline} ->
        Logger.info("Seeded pipeline template '#{@pipeline_name}' (#{pipeline.id})")

      {:error, reason} ->
        Logger.warning("Failed to seed hardening pipeline template: #{inspect(reason)}")
    end
  end

  defp build_graph(skill_id_map) do
    # Layout constants
    col_spacing = 280
    scan_to_gate = 120
    gate_to_apply = 120
    step_height = scan_to_gate + gate_to_apply + 80
    phase_gap = 160

    # ── Start node ──
    start = node_def("start", "start", "Start", %{}, %{"x" => 500, "y" => 30})

    # ── Phase 1: 4 parallel scan→gate→apply triplets ──
    y_base_p1 = 130
    {p1_nodes, p1_edges} = build_phase(@phase_1, y_base_p1, scan_to_gate, gate_to_apply, col_spacing, skill_id_map)
    p1_start_edges = fan_out_to_scans("start", @phase_1, "p1-start")

    # ── Phase 2 ──
    y_base_p2 = y_base_p1 + step_height + phase_gap
    {p2_nodes, p2_edges} = build_phase(@phase_2, y_base_p2, scan_to_gate, gate_to_apply, col_spacing, skill_id_map)
    p2_from_p1 = fan_apply_to_scans(@phase_1, @phase_2, "p1p2")

    # ── Phase 3 ──
    y_base_p3 = y_base_p2 + step_height + phase_gap
    {p3_nodes, p3_edges} = build_phase(@phase_3, y_base_p3, scan_to_gate, gate_to_apply, col_spacing, skill_id_map)
    p3_from_p2 = fan_apply_to_scans(@phase_2, @phase_3, "p2p3")

    # ── Phase 4 ──
    y_base_p4 = y_base_p3 + step_height + phase_gap
    {p4_nodes, p4_edges} = build_phase(@phase_4, y_base_p4, scan_to_gate, gate_to_apply, col_spacing, skill_id_map)
    p4_from_p3 = fan_apply_to_scans(@phase_3, @phase_4, "p3p4")

    # ── Summary issue node ──
    {sum_id, sum_skill, sum_label, sum_desc} = @summary
    sum_skill_ids = skill_ids_for(sum_skill, skill_id_map)
    y_summary = y_base_p4 + step_height + phase_gap

    summary_node =
      node_def(sum_id, "issue", sum_label, %{
        "title" => sum_label,
        "description" => sum_desc,
        "labels" => ["hardening", "summary"],
        "skill_ids" => sum_skill_ids,
        "priority" => 4
      }, %{"x" => 500, "y" => y_summary})

    # Edge: P4 apply → summary
    {p4_id, _, _, _, _} = hd(@phase_4)
    p4_to_summary = [
      edge_def("e-apply-#{p4_id}-#{sum_id}", "apply-#{p4_id}", sum_id, "output")
    ]

    # ── End node ──
    end_node = node_def("end", "end", "End", %{}, %{"x" => 500, "y" => y_summary + 150})
    summary_to_end = [
      edge_def("e-#{sum_id}-end", sum_id, "end", "output")
    ]

    # ── Assemble ──
    all_nodes =
      [start] ++
        p1_nodes ++ p2_nodes ++ p3_nodes ++ p4_nodes ++
        [summary_node, end_node]

    all_edges =
      p1_start_edges ++ p1_edges ++
        p2_from_p1 ++ p2_edges ++
        p3_from_p2 ++ p3_edges ++
        p4_from_p3 ++ p4_edges ++
        p4_to_summary ++ summary_to_end

    {all_nodes, all_edges}
  end

  # Build scan→gate→apply triplets for a phase
  defp build_phase(phase_specs, y_base, scan_to_gate, gate_to_apply, col_spacing, skill_id_map) do
    count = length(phase_specs)
    x_start = 500 - div((count - 1) * col_spacing, 2)

    phase_specs
    |> Enum.with_index()
    |> Enum.reduce({[], []}, fn {{node_id, scan_skill, apply_skill, label, desc}, idx}, {nodes, edges} ->
      x = x_start + idx * col_spacing
      scan_skill_ids = skill_ids_for(scan_skill, skill_id_map)
      apply_skill_ids = skill_ids_for(apply_skill, skill_id_map)

      scan_id = "scan-#{node_id}"
      gate_id = "gate-#{node_id}"
      apply_id = "apply-#{node_id}"

      scan_node =
        node_def(scan_id, "issue", "Scan: #{label}", %{
          "title" => "Scan: #{label}",
          "description" => "SCAN ONLY — analyze and report findings. Do NOT make code changes.\n\n#{desc}",
          "labels" => ["hardening", "scan"],
          "skill_ids" => scan_skill_ids,
          "priority" => 3
        }, %{"x" => x, "y" => y_base})

      gate_node =
        node_def(gate_id, "human_gate", "Review: #{label}", %{
          "instructions" => "Review each finding individually. Accept the ones you want applied, discard the rest."
        }, %{
          "x" => x,
          "y" => y_base + scan_to_gate
        })

      apply_node =
        node_def(apply_id, "issue", "Apply: #{label}", %{
          "title" => "Apply: #{label}",
          "description" => "Apply ONLY the accepted findings from the review gate.\n\n#{desc}",
          "labels" => ["hardening", "apply"],
          "skill_ids" => apply_skill_ids,
          "priority" => 3
        }, %{"x" => x, "y" => y_base + scan_to_gate + gate_to_apply})

      new_nodes = [scan_node, gate_node, apply_node]
      new_edges = [
        edge_def("e-#{scan_id}-#{gate_id}", scan_id, gate_id, "output"),
        edge_def("e-#{gate_id}-#{apply_id}", gate_id, apply_id, "output")
      ]

      {nodes ++ new_nodes, edges ++ new_edges}
    end)
  end

  # Edges from a single source to each scan node in a phase
  defp fan_out_to_scans(source_id, phase_specs, prefix) do
    Enum.map(phase_specs, fn {node_id, _, _, _, _} ->
      edge_def("e-#{prefix}-scan-#{node_id}", source_id, "scan-#{node_id}", "output")
    end)
  end

  # Edges from every apply node in prev_phase to every scan node in next_phase
  defp fan_apply_to_scans(prev_phase, next_phase, prefix) do
    for {prev_id, _, _, _, _} <- prev_phase,
        {next_id, _, _, _, _} <- next_phase do
      edge_def("e-#{prefix}-#{prev_id}-#{next_id}", "apply-#{prev_id}", "scan-#{next_id}", "output")
    end
  end

  defp skill_ids_for(skill_name, skill_id_map) do
    case Map.get(skill_id_map, skill_name) do
      nil -> []
      id -> [id]
    end
  end

  defp node_def(id, type, label, config, position) do
    %{
      "id" => id,
      "type" => type,
      "label" => label,
      "config" => config,
      "position" => position
    }
  end

  defp edge_def(id, source_id, target_id, source_port) do
    %{
      "id" => id,
      "source_node_id" => source_id,
      "target_node_id" => target_id,
      "source_port" => source_port
    }
  end
end

defmodule SymphonyElixir.PipelineSeed do
  @moduledoc """
  Seeds the "Extract Product Knowledge" pipeline for each product on startup.

  For every product that doesn't already have this pipeline, creates a pipeline
  with 5 parallel extraction issue nodes (architecture, business logic, constraints,
  workflows, product overview) that fan into a single KB sync node with auto-approve.

  Each agent analyzes the entire product across all its projects — the sandbox
  mounts the primary project as /workspace and additional projects under /projects/.
  """

  require Logger

  alias SymphonyElixir.LocalBoard

  @pipeline_name "Extract Product Knowledge"

  @extraction_nodes [
    %{
      skill_name: "extract-architecture",
      label: "Extract Architecture",
      title: "Extract Architecture",
      description: "Analyze the codebase and extract system architecture documentation.",
      extra_label: "extract-architecture"
    },
    %{
      skill_name: "extract-business-logic",
      label: "Extract Business Logic",
      title: "Extract Business Logic",
      description:
        "Analyze the codebase and extract business rules, domain logic, and invariants.",
      extra_label: "extract-business-logic"
    },
    %{
      skill_name: "extract-constraints",
      label: "Extract Constraints",
      title: "Extract Constraints",
      description:
        "Analyze the codebase and extract technical constraints, limits, and boundaries.",
      extra_label: "extract-constraints"
    },
    %{
      skill_name: "extract-workflows",
      label: "Extract Workflows",
      title: "Extract Workflows",
      description: "Analyze the codebase and extract process workflows and data flows.",
      extra_label: "extract-workflows"
    },
    %{
      skill_name: "extract-product-overview",
      label: "Extract Product Overview",
      title: "Extract Product Overview",
      description:
        "Analyze the codebase and extract product identity, feature inventory, and project structure.",
      extra_label: "extract-product-overview"
    }
  ]

  @doc """
  Seed the Extract Product Knowledge pipeline template (once, not per product).
  Product is selected when starting a run.
  Call this after LocalBoard and SkillsSeed have run.
  """
  @spec seed() :: :ok
  def seed do
    existing_pipelines = LocalBoard.list_pipelines()
    skill_id_map = build_skill_id_map()

    already_exists? = Enum.any?(existing_pipelines, fn p -> p.name == @pipeline_name end)

    unless already_exists? do
      create_extraction_pipeline(skill_id_map)
    end

    :ok
  end

  # Build a map of skill name -> skill ID from the current board
  defp build_skill_id_map do
    LocalBoard.list_skills()
    |> Enum.map(fn s -> {s.name, s.id} end)
    |> Map.new()
  end

  defp create_extraction_pipeline(skill_id_map) do
    # Node IDs
    start_id = "start"
    end_id = "end"
    kb_sync_id = "kb-sync"

    # Build extraction issue nodes
    {issue_nodes, issue_edges_from_start, issue_edges_to_kb} =
      @extraction_nodes
      |> Enum.with_index()
      |> Enum.reduce({[], [], []}, fn {spec, idx}, {nodes, from_start, to_kb} ->
        node_id = "extract-#{idx}"
        skill_id = Map.get(skill_id_map, spec.skill_name)
        skill_ids = if skill_id, do: [skill_id], else: []

        node = %{
          "id" => node_id,
          "type" => "issue",
          "label" => spec.label,
          "config" => %{
            "title" => spec.title,
            "description" => spec.description,
            "labels" => ["extract-logic", spec.extra_label],
            "skill_ids" => skill_ids,
            "priority" => 3
          },
          "position" => %{"x" => 100 + idx * 250, "y" => 200}
        }

        edge_from_start = %{
          "id" => "e-start-#{node_id}",
          "source_node_id" => start_id,
          "target_node_id" => node_id,
          "source_port" => "output"
        }

        edge_to_kb = %{
          "id" => "e-#{node_id}-kb",
          "source_node_id" => node_id,
          "target_node_id" => kb_sync_id,
          "source_port" => "output"
        }

        {nodes ++ [node], from_start ++ [edge_from_start], to_kb ++ [edge_to_kb]}
      end)

    # Assemble full node list
    nodes =
      [
        %{
          "id" => start_id,
          "type" => "start",
          "label" => "Start",
          "position" => %{"x" => 600, "y" => 50}
        }
      ] ++
        issue_nodes ++
        [
          %{
            "id" => kb_sync_id,
            "type" => "kb_sync",
            "label" => "Sync to Knowledge Base",
            "config" => %{
              "auto_approve_condition" => "all_predecessors_completed"
            },
            "position" => %{"x" => 600, "y" => 400}
          },
          %{
            "id" => end_id,
            "type" => "end",
            "label" => "End",
            "position" => %{"x" => 600, "y" => 550}
          }
        ]

    # Assemble full edge list
    edges =
      issue_edges_from_start ++
        issue_edges_to_kb ++
        [
          %{
            "id" => "e-kb-end",
            "source_node_id" => kb_sync_id,
            "target_node_id" => end_id,
            "source_port" => "output"
          }
        ]

    attrs = %{
      "name" => @pipeline_name,
      "description" =>
        "Runs 5 parallel knowledge extraction agents against the product's codebase, " <>
          "then syncs all reports to the Knowledge Base.",
      "nodes" => nodes,
      "edges" => edges,
      "settings" => %{}
    }

    case LocalBoard.create_pipeline(attrs) do
      {:ok, pipeline} ->
        Logger.info("Seeded pipeline template '#{@pipeline_name}' (#{pipeline.id})")

      {:error, reason} ->
        Logger.warning("Failed to seed extraction pipeline template: #{inspect(reason)}")
    end
  end
end

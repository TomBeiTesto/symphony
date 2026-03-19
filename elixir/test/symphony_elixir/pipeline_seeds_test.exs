defmodule SymphonyElixir.PipelineSeedsTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.{LocalBoard, SkillsSeed, PipelineSeed, HardeningSeed, FeaturePipelineSeed}

  @store_path "test_pipeline_seeds_#{System.unique_integer([:positive])}.json"

  setup do
    start_supervised!({LocalBoard, store_path: @store_path, project_prefix: "PS"})
    on_exit(fn -> File.rm(@store_path) end)

    # Skills must be seeded first — pipelines reference them
    :ok = SkillsSeed.seed()
    :ok
  end

  # ── Extract Product Knowledge ──

  describe "PipelineSeed.seed/0" do
    test "creates the extraction pipeline" do
      assert :ok = PipelineSeed.seed()

      pipelines = LocalBoard.list_pipelines()
      assert Enum.any?(pipelines, &(&1.name == "Extract Product Knowledge"))
    end

    test "extraction pipeline has correct node count" do
      :ok = PipelineSeed.seed()

      {:ok, pipeline} =
        LocalBoard.list_pipelines()
        |> Enum.find(&(&1.name == "Extract Product Knowledge"))
        |> then(&LocalBoard.get_pipeline(&1.id))

      # start + 5 extraction + kb_sync + end = 8
      assert length(pipeline.nodes) == 8
    end

    test "extraction pipeline graph is fully connected" do
      :ok = PipelineSeed.seed()

      {:ok, pipeline} =
        LocalBoard.list_pipelines()
        |> Enum.find(&(&1.name == "Extract Product Knowledge"))
        |> then(&LocalBoard.get_pipeline(&1.id))

      node_ids = MapSet.new(pipeline.nodes, & &1.id)

      # Every edge references existing nodes
      for edge <- pipeline.edges do
        assert MapSet.member?(node_ids, edge.source_node_id),
               "Edge #{edge.id} references missing source #{edge.source_node_id}"

        assert MapSet.member?(node_ids, edge.target_node_id),
               "Edge #{edge.id} references missing target #{edge.target_node_id}"
      end

      # Every non-start node has at least one incoming edge
      start_ids = pipeline.nodes |> Enum.filter(&(&1.type == "start")) |> Enum.map(& &1.id) |> MapSet.new()
      target_ids = MapSet.new(pipeline.edges, & &1.target_node_id)

      for node <- pipeline.nodes, not MapSet.member?(start_ids, node.id) do
        assert MapSet.member?(target_ids, node.id),
               "Node #{node.id} has no incoming edges (orphaned)"
      end
    end

    test "idempotent — running twice does not create duplicates" do
      :ok = PipelineSeed.seed()
      :ok = PipelineSeed.seed()

      count =
        LocalBoard.list_pipelines()
        |> Enum.count(&(&1.name == "Extract Product Knowledge"))

      assert count == 1
    end
  end

  # ── Product Health & Hardening ──

  describe "HardeningSeed.seed/0" do
    test "creates the hardening pipeline" do
      assert :ok = HardeningSeed.seed()

      pipelines = LocalBoard.list_pipelines()
      assert Enum.any?(pipelines, &(&1.name == "Product Health & Hardening"))
    end

    test "hardening pipeline has correct node count" do
      :ok = HardeningSeed.seed()

      {:ok, pipeline} =
        LocalBoard.list_pipelines()
        |> Enum.find(&(&1.name == "Product Health & Hardening"))
        |> then(&LocalBoard.get_pipeline(&1.id))

      # start + (4+3+3+1)*3 triplets + summary + end = 1 + 33 + 1 + 1 = 36
      assert length(pipeline.nodes) == 36
    end

    test "hardening pipeline all edges reference valid nodes" do
      :ok = HardeningSeed.seed()

      {:ok, pipeline} =
        LocalBoard.list_pipelines()
        |> Enum.find(&(&1.name == "Product Health & Hardening"))
        |> then(&LocalBoard.get_pipeline(&1.id))

      node_ids = MapSet.new(pipeline.nodes, & &1.id)

      for edge <- pipeline.edges do
        assert MapSet.member?(node_ids, edge.source_node_id),
               "Edge #{edge.id} references missing source #{edge.source_node_id}"

        assert MapSet.member?(node_ids, edge.target_node_id),
               "Edge #{edge.id} references missing target #{edge.target_node_id}"
      end
    end

    test "hardening pipeline has scan→gate→apply triplets" do
      :ok = HardeningSeed.seed()

      {:ok, pipeline} =
        LocalBoard.list_pipelines()
        |> Enum.find(&(&1.name == "Product Health & Hardening"))
        |> then(&LocalBoard.get_pipeline(&1.id))

      # Every scan-* node should have an edge to a gate-* node
      scan_nodes = Enum.filter(pipeline.nodes, &String.starts_with?(&1.id, "scan-"))

      for scan <- scan_nodes do
        suffix = String.replace_prefix(scan.id, "scan-", "")
        gate_id = "gate-#{suffix}"
        apply_id = "apply-#{suffix}"

        assert Enum.any?(pipeline.edges, &(&1.source_node_id == scan.id && &1.target_node_id == gate_id)),
               "Missing edge from #{scan.id} to #{gate_id}"

        assert Enum.any?(pipeline.edges, &(&1.source_node_id == gate_id && &1.target_node_id == apply_id)),
               "Missing edge from #{gate_id} to #{apply_id}"
      end
    end

    test "idempotent — running twice does not create duplicates" do
      :ok = HardeningSeed.seed()
      :ok = HardeningSeed.seed()

      count =
        LocalBoard.list_pipelines()
        |> Enum.count(&(&1.name == "Product Health & Hardening"))

      assert count == 1
    end
  end

  # ── Feature Implementation ──

  describe "FeaturePipelineSeed.seed/0" do
    test "creates the feature implementation pipeline" do
      assert :ok = FeaturePipelineSeed.seed()

      pipelines = LocalBoard.list_pipelines()
      assert Enum.any?(pipelines, &(&1.name == "Feature Implementation"))
    end

    test "feature pipeline has correct node count" do
      :ok = FeaturePipelineSeed.seed()

      {:ok, pipeline} =
        LocalBoard.list_pipelines()
        |> Enum.find(&(&1.name == "Feature Implementation"))
        |> then(&LocalBoard.get_pipeline(&1.id))

      # start + 3 analyze + plan + plan-gate + code + code-gate +
      # tests + docs + test-gate + kb-sync + end = 13
      assert length(pipeline.nodes) == 13
    end

    test "feature pipeline all edges reference valid nodes" do
      :ok = FeaturePipelineSeed.seed()

      {:ok, pipeline} =
        LocalBoard.list_pipelines()
        |> Enum.find(&(&1.name == "Feature Implementation"))
        |> then(&LocalBoard.get_pipeline(&1.id))

      node_ids = MapSet.new(pipeline.nodes, & &1.id)

      for edge <- pipeline.edges do
        assert MapSet.member?(node_ids, edge.source_node_id),
               "Edge #{edge.id} references missing source #{edge.source_node_id}"

        assert MapSet.member?(node_ids, edge.target_node_id),
               "Edge #{edge.id} references missing target #{edge.target_node_id}"
      end
    end

    test "feature pipeline has no orphaned nodes" do
      :ok = FeaturePipelineSeed.seed()

      {:ok, pipeline} =
        LocalBoard.list_pipelines()
        |> Enum.find(&(&1.name == "Feature Implementation"))
        |> then(&LocalBoard.get_pipeline(&1.id))

      start_ids = pipeline.nodes |> Enum.filter(&(&1.type == "start")) |> Enum.map(& &1.id) |> MapSet.new()
      end_ids = pipeline.nodes |> Enum.filter(&(&1.type == "end")) |> Enum.map(& &1.id) |> MapSet.new()
      target_ids = MapSet.new(pipeline.edges, & &1.target_node_id)
      source_ids = MapSet.new(pipeline.edges, & &1.source_node_id)

      for node <- pipeline.nodes do
        unless MapSet.member?(start_ids, node.id) do
          assert MapSet.member?(target_ids, node.id),
                 "Node #{node.id} has no incoming edges"
        end

        unless MapSet.member?(end_ids, node.id) do
          assert MapSet.member?(source_ids, node.id),
                 "Node #{node.id} has no outgoing edges"
        end
      end
    end

    test "feature pipeline phase 1 fans out from start" do
      :ok = FeaturePipelineSeed.seed()

      {:ok, pipeline} =
        LocalBoard.list_pipelines()
        |> Enum.find(&(&1.name == "Feature Implementation"))
        |> then(&LocalBoard.get_pipeline(&1.id))

      start_edges = Enum.filter(pipeline.edges, &(&1.source_node_id == "start"))
      targets = Enum.map(start_edges, & &1.target_node_id) |> Enum.sort()

      assert targets == ["constraint-check", "impact-analysis", "kb-context"]
    end

    test "feature pipeline phase 1 converges into plan" do
      :ok = FeaturePipelineSeed.seed()

      {:ok, pipeline} =
        LocalBoard.list_pipelines()
        |> Enum.find(&(&1.name == "Feature Implementation"))
        |> then(&LocalBoard.get_pipeline(&1.id))

      plan_inputs =
        pipeline.edges
        |> Enum.filter(&(&1.target_node_id == "impl-plan"))
        |> Enum.map(& &1.source_node_id)
        |> Enum.sort()

      assert plan_inputs == ["constraint-check", "impact-analysis", "kb-context"]
    end

    test "feature pipeline issue nodes have skill_ids populated" do
      :ok = FeaturePipelineSeed.seed()

      {:ok, pipeline} =
        LocalBoard.list_pipelines()
        |> Enum.find(&(&1.name == "Feature Implementation"))
        |> then(&LocalBoard.get_pipeline(&1.id))

      issue_nodes = Enum.filter(pipeline.nodes, &(&1.type == "issue"))

      for node <- issue_nodes do
        skill_ids = get_in(node, [:config, "skill_ids"]) || []

        assert length(skill_ids) > 0,
               "Issue node #{node.id} has no skill_ids assigned"
      end
    end

    test "idempotent — running twice does not create duplicates" do
      :ok = FeaturePipelineSeed.seed()
      :ok = FeaturePipelineSeed.seed()

      count =
        LocalBoard.list_pipelines()
        |> Enum.count(&(&1.name == "Feature Implementation"))

      assert count == 1
    end
  end

  # ── All pipelines together ──

  describe "all seeds together" do
    test "all three pipelines coexist" do
      :ok = PipelineSeed.seed()
      :ok = HardeningSeed.seed()
      :ok = FeaturePipelineSeed.seed()

      names =
        LocalBoard.list_pipelines()
        |> Enum.map(& &1.name)
        |> Enum.sort()

      assert names == [
               "Extract Product Knowledge",
               "Feature Implementation",
               "Product Health & Hardening"
             ]
    end
  end
end

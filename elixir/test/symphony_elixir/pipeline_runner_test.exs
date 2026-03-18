defmodule SymphonyElixir.PipelineRunnerTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.LocalBoard
  alias SymphonyElixir.Settings
  alias SymphonyElixir.PipelineRunner

  import SymphonyElixir.TestHelpers, only: [wait_until: 1]

  @store_path "test_pipeline_runner_#{System.unique_integer([:positive])}.json"
  @settings_path "test_pipeline_runner_settings_#{System.unique_integer([:positive])}.json"

  setup do
    start_supervised!(
      {LocalBoard,
       store_path: @store_path,
       states: ["Backlog", "Todo", "In Progress", "Review", "Done", "Archived", "Cancelled"],
       project_prefix: "PR"}
    )

    start_supervised!({Settings, store_path: @settings_path})
    start_supervised!(PipelineRunner)

    on_exit(fn ->
      File.rm(@store_path)
      File.rm(@settings_path)
    end)

    :ok
  end

  defp create_simple_pipeline(nodes \\ nil, edges \\ nil) do
    {:ok, pipeline} = LocalBoard.create_pipeline(%{"name" => "Test Pipeline"})

    default_nodes = [
      %{
        "id" => "s1",
        "type" => "start",
        "label" => "Start",
        "position" => %{"x" => 0, "y" => 0},
        "config" => %{}
      },
      %{
        "id" => "e1",
        "type" => "end",
        "label" => "End",
        "position" => %{"x" => 400, "y" => 0},
        "config" => %{}
      }
    ]

    default_edges = [
      %{
        "id" => "edge-se",
        "source_node_id" => "s1",
        "target_node_id" => "e1",
        "source_port" => "output"
      }
    ]

    {:ok, pipeline} =
      LocalBoard.update_pipeline(pipeline.id, %{
        "nodes" => nodes || default_nodes,
        "edges" => edges || default_edges
      })

    pipeline
  end

  defp run_status(pipeline_id, run_id) do
    {:ok, run} = LocalBoard.get_pipeline_run(pipeline_id, run_id)
    run.status
  end

  defp node_state(pipeline_id, run_id, node_id) do
    {:ok, run} = LocalBoard.get_pipeline_run(pipeline_id, run_id)
    Map.get(run.node_states, node_id)
  end

  # --- Basic execution ---

  describe "start → end pipeline" do
    test "completes automatically" do
      pipeline = create_simple_pipeline()
      {:ok, run} = LocalBoard.create_pipeline_run(pipeline.id)
      PipelineRunner.start_run(pipeline.id, run.id)

      wait_until(fn -> run_status(pipeline.id, run.id) == "completed" end)

      {:ok, run} = LocalBoard.get_pipeline_run(pipeline.id, run.id)
      assert Map.get(run.node_states, "s1") == "completed"
      assert Map.get(run.node_states, "e1") == "completed"
    end
  end

  describe "issue node" do
    test "moves issue to Todo and completes when issue reaches Done" do
      {:ok, issue} =
        LocalBoard.create_issue(%{"title" => "Runner Test Issue", "state" => "Backlog"})

      pipeline =
        create_simple_pipeline(
          [
            %{
              "id" => "s1",
              "type" => "start",
              "label" => "Start",
              "position" => %{"x" => 0, "y" => 0},
              "config" => %{}
            },
            %{
              "id" => "i1",
              "type" => "issue",
              "label" => "Issue",
              "issue_id" => issue.id,
              "position" => %{"x" => 200, "y" => 0},
              "config" => %{}
            },
            %{
              "id" => "e1",
              "type" => "end",
              "label" => "End",
              "position" => %{"x" => 400, "y" => 0},
              "config" => %{}
            }
          ],
          [
            %{
              "id" => "e-si",
              "source_node_id" => "s1",
              "target_node_id" => "i1",
              "source_port" => "output"
            },
            %{
              "id" => "e-ie",
              "source_node_id" => "i1",
              "target_node_id" => "e1",
              "source_port" => "output"
            }
          ]
        )

      {:ok, run} = LocalBoard.create_pipeline_run(pipeline.id)
      PipelineRunner.start_run(pipeline.id, run.id)

      wait_until(fn -> node_state(pipeline.id, run.id, "i1") == "running" end)

      # Issue should be moved to Todo
      {:ok, issue} = LocalBoard.get_issue(issue.id)
      assert issue.state == "Todo"

      # Move issue to Done
      LocalBoard.move_issue(issue.id, "Done")

      wait_until(fn -> run_status(pipeline.id, run.id) == "completed" end)

      {:ok, run} = LocalBoard.get_pipeline_run(pipeline.id, run.id)
      assert Map.get(run.node_states, "i1") == "completed"
    end

    test "template-based issue creation" do
      pipeline =
        create_simple_pipeline(
          [
            %{
              "id" => "s1",
              "type" => "start",
              "label" => "Start",
              "position" => %{"x" => 0, "y" => 0},
              "config" => %{}
            },
            %{
              "id" => "i1",
              "type" => "issue",
              "label" => "Template Issue",
              "position" => %{"x" => 200, "y" => 0},
              "config" => %{"title" => "Auto-created issue", "description" => "From template"}
            },
            %{
              "id" => "e1",
              "type" => "end",
              "label" => "End",
              "position" => %{"x" => 400, "y" => 0},
              "config" => %{}
            }
          ],
          [
            %{
              "id" => "e-si",
              "source_node_id" => "s1",
              "target_node_id" => "i1",
              "source_port" => "output"
            },
            %{
              "id" => "e-ie",
              "source_node_id" => "i1",
              "target_node_id" => "e1",
              "source_port" => "output"
            }
          ]
        )

      {:ok, run} = LocalBoard.create_pipeline_run(pipeline.id)
      PipelineRunner.start_run(pipeline.id, run.id)

      wait_until(fn ->
        {:ok, r} = LocalBoard.get_pipeline_run(pipeline.id, run.id)
        Map.has_key?(r.node_issue_ids, "i1")
      end)

      {:ok, run} = LocalBoard.get_pipeline_run(pipeline.id, run.id)
      created_issue_id = run.node_issue_ids["i1"]
      {:ok, issue} = LocalBoard.get_issue(created_issue_id)
      assert String.starts_with?(issue.title, "Auto-created issue")
      assert issue.state == "Todo"

      # Move issue to Done to complete pipeline
      LocalBoard.move_issue(created_issue_id, "Done")

      wait_until(fn -> run_status(pipeline.id, run.id) == "completed" end)
    end
  end

  describe "human gate" do
    test "pauses at gate and advances on approve" do
      pipeline =
        create_simple_pipeline(
          [
            %{
              "id" => "s1",
              "type" => "start",
              "label" => "Start",
              "position" => %{"x" => 0, "y" => 0},
              "config" => %{}
            },
            %{
              "id" => "g1",
              "type" => "human_gate",
              "label" => "Gate",
              "position" => %{"x" => 200, "y" => 0},
              "config" => %{}
            },
            %{
              "id" => "e1",
              "type" => "end",
              "label" => "End",
              "position" => %{"x" => 400, "y" => 0},
              "config" => %{}
            }
          ],
          [
            %{
              "id" => "e-sg",
              "source_node_id" => "s1",
              "target_node_id" => "g1",
              "source_port" => "output"
            },
            %{
              "id" => "e-ge",
              "source_node_id" => "g1",
              "target_node_id" => "e1",
              "source_port" => "output"
            }
          ]
        )

      {:ok, run} = LocalBoard.create_pipeline_run(pipeline.id)
      PipelineRunner.start_run(pipeline.id, run.id)

      wait_until(fn -> node_state(pipeline.id, run.id, "g1") == "waiting_gate" end)

      # Approve the gate
      {:ok, _} = LocalBoard.record_gate_decision(run.id, "g1", "approve", "LGTM")
      PipelineRunner.gate_decided(run.id, "g1", "approve")

      wait_until(fn -> run_status(pipeline.id, run.id) == "completed" end)
    end

    test "reject gate resets downstream and re-advances" do
      pipeline =
        create_simple_pipeline(
          [
            %{
              "id" => "s1",
              "type" => "start",
              "label" => "Start",
              "position" => %{"x" => 0, "y" => 0},
              "config" => %{}
            },
            %{
              "id" => "g1",
              "type" => "human_gate",
              "label" => "Gate",
              "position" => %{"x" => 200, "y" => 0},
              "config" => %{}
            },
            %{
              "id" => "e1",
              "type" => "end",
              "label" => "End",
              "position" => %{"x" => 400, "y" => 0},
              "config" => %{}
            }
          ],
          [
            %{
              "id" => "e-sg",
              "source_node_id" => "s1",
              "target_node_id" => "g1",
              "source_port" => "output"
            },
            %{
              "id" => "e-ge",
              "source_node_id" => "g1",
              "target_node_id" => "e1",
              "source_port" => "output"
            },
            # Reject edge loops back to gate
            %{
              "id" => "e-gg",
              "source_node_id" => "g1",
              "target_node_id" => "g1",
              "source_port" => "reject"
            }
          ]
        )

      {:ok, run} = LocalBoard.create_pipeline_run(pipeline.id)
      PipelineRunner.start_run(pipeline.id, run.id)

      wait_until(fn -> node_state(pipeline.id, run.id, "g1") == "waiting_gate" end)

      # Reject the gate
      {:ok, _} = LocalBoard.record_gate_decision(run.id, "g1", "reject", "Needs work")
      PipelineRunner.gate_decided(run.id, "g1", "reject")

      # Gate should loop back to waiting_gate after reject
      # Need a brief sleep then wait — the reject resets to pending, then tick re-activates
      wait_until(fn ->
        state = node_state(pipeline.id, run.id, "g1")
        state == "waiting_gate" and run_status(pipeline.id, run.id) == "running"
      end)

      # Now approve
      {:ok, _} = LocalBoard.record_gate_decision(run.id, "g1", "approve", "OK now")
      PipelineRunner.gate_decided(run.id, "g1", "approve")

      wait_until(fn -> run_status(pipeline.id, run.id) == "completed" end)
    end
  end

  describe "pause/resume" do
    test "paused run does not advance nodes" do
      pipeline =
        create_simple_pipeline(
          [
            %{
              "id" => "s1",
              "type" => "start",
              "label" => "Start",
              "position" => %{"x" => 0, "y" => 0},
              "config" => %{}
            },
            %{
              "id" => "g1",
              "type" => "human_gate",
              "label" => "Gate",
              "position" => %{"x" => 200, "y" => 0},
              "config" => %{}
            },
            %{
              "id" => "e1",
              "type" => "end",
              "label" => "End",
              "position" => %{"x" => 400, "y" => 0},
              "config" => %{}
            }
          ],
          [
            %{
              "id" => "e-sg",
              "source_node_id" => "s1",
              "target_node_id" => "g1",
              "source_port" => "output"
            },
            %{
              "id" => "e-ge",
              "source_node_id" => "g1",
              "target_node_id" => "e1",
              "source_port" => "output"
            }
          ]
        )

      {:ok, run} = LocalBoard.create_pipeline_run(pipeline.id)
      PipelineRunner.start_run(pipeline.id, run.id)

      wait_until(fn -> node_state(pipeline.id, run.id, "g1") == "waiting_gate" end)

      # Pause the run
      {:ok, _} = LocalBoard.update_pipeline_run_status(run.id, "paused")

      # Approve the gate (should not advance because paused)
      {:ok, _} = LocalBoard.record_gate_decision(run.id, "g1", "approve", nil)
      PipelineRunner.gate_decided(run.id, "g1", "approve")

      # Give a tick cycle to confirm it doesn't advance
      Process.sleep(500)

      # End node should still not be completed since run was paused when tick fires
      {:ok, run} = LocalBoard.get_pipeline_run(pipeline.id, run.id)
      assert run.status == "paused"
    end
  end

  describe "concurrency guard" do
    test "cannot start two runs of the same pipeline" do
      pipeline =
        create_simple_pipeline(
          [
            %{
              "id" => "s1",
              "type" => "start",
              "label" => "Start",
              "position" => %{"x" => 0, "y" => 0},
              "config" => %{}
            },
            %{
              "id" => "g1",
              "type" => "human_gate",
              "label" => "Gate",
              "position" => %{"x" => 200, "y" => 0},
              "config" => %{}
            },
            %{
              "id" => "e1",
              "type" => "end",
              "label" => "End",
              "position" => %{"x" => 400, "y" => 0},
              "config" => %{}
            }
          ],
          [
            %{
              "id" => "e-sg",
              "source_node_id" => "s1",
              "target_node_id" => "g1",
              "source_port" => "output"
            },
            %{
              "id" => "e-ge",
              "source_node_id" => "g1",
              "target_node_id" => "e1",
              "source_port" => "output"
            }
          ]
        )

      {:ok, _run1} = LocalBoard.create_pipeline_run(pipeline.id)
      assert {:error, :already_running} = LocalBoard.create_pipeline_run(pipeline.id)
    end
  end

  describe "graph validation" do
    test "rejects pipeline without start node" do
      {:ok, pipeline} = LocalBoard.create_pipeline(%{"name" => "No Start"})

      result =
        LocalBoard.update_pipeline(pipeline.id, %{
          "nodes" => [
            %{
              "id" => "e1",
              "type" => "end",
              "label" => "End",
              "position" => %{"x" => 0, "y" => 0}
            }
          ],
          "edges" => []
        })

      assert {:error, :no_start_node} = result
    end

    test "rejects pipeline without end node" do
      {:ok, pipeline} = LocalBoard.create_pipeline(%{"name" => "No End"})

      result =
        LocalBoard.update_pipeline(pipeline.id, %{
          "nodes" => [
            %{
              "id" => "s1",
              "type" => "start",
              "label" => "Start",
              "position" => %{"x" => 0, "y" => 0}
            }
          ],
          "edges" => []
        })

      assert {:error, :no_end_node} = result
    end

    test "rejects pipeline with invalid edge references" do
      {:ok, pipeline} = LocalBoard.create_pipeline(%{"name" => "Bad Edges"})

      result =
        LocalBoard.update_pipeline(pipeline.id, %{
          "nodes" => [
            %{
              "id" => "s1",
              "type" => "start",
              "label" => "Start",
              "position" => %{"x" => 0, "y" => 0}
            },
            %{
              "id" => "e1",
              "type" => "end",
              "label" => "End",
              "position" => %{"x" => 200, "y" => 0}
            }
          ],
          "edges" => [
            %{
              "id" => "bad",
              "source_node_id" => "s1",
              "target_node_id" => "nonexistent",
              "source_port" => "output"
            }
          ]
        })

      assert {:error, :invalid_edge_reference} = result
    end

    test "rejects disconnected graph" do
      {:ok, pipeline} = LocalBoard.create_pipeline(%{"name" => "Disconnected"})

      result =
        LocalBoard.update_pipeline(pipeline.id, %{
          "nodes" => [
            %{
              "id" => "s1",
              "type" => "start",
              "label" => "Start",
              "position" => %{"x" => 0, "y" => 0}
            },
            %{
              "id" => "e1",
              "type" => "end",
              "label" => "End",
              "position" => %{"x" => 200, "y" => 0}
            },
            %{
              "id" => "orphan",
              "type" => "issue",
              "label" => "Orphan",
              "position" => %{"x" => 100, "y" => 100}
            }
          ],
          "edges" => [
            %{
              "id" => "e-se",
              "source_node_id" => "s1",
              "target_node_id" => "e1",
              "source_port" => "output"
            }
          ]
        })

      assert {:error, :disconnected_graph} = result
    end

    test "accepts valid graph" do
      {:ok, pipeline} = LocalBoard.create_pipeline(%{"name" => "Valid"})

      {:ok, _} =
        LocalBoard.update_pipeline(pipeline.id, %{
          "nodes" => [
            %{
              "id" => "s1",
              "type" => "start",
              "label" => "Start",
              "position" => %{"x" => 0, "y" => 0}
            },
            %{
              "id" => "e1",
              "type" => "end",
              "label" => "End",
              "position" => %{"x" => 200, "y" => 0}
            }
          ],
          "edges" => [
            %{
              "id" => "e-se",
              "source_node_id" => "s1",
              "target_node_id" => "e1",
              "source_port" => "output"
            }
          ]
        })
    end
  end

  describe "gate action validation" do
    test "rejects invalid gate action" do
      assert {:error, :invalid_action} =
               LocalBoard.record_gate_decision("fake-run", "fake-node", "appprove", nil)
    end
  end

  describe "pipeline_id validation on get_pipeline_run" do
    test "returns not_found when pipeline_id doesn't match" do
      pipeline = create_simple_pipeline()
      {:ok, run} = LocalBoard.create_pipeline_run(pipeline.id)

      assert {:error, :not_found} = LocalBoard.get_pipeline_run("wrong-pipeline-id", run.id)
      assert {:ok, _} = LocalBoard.get_pipeline_run(pipeline.id, run.id)
    end
  end
end

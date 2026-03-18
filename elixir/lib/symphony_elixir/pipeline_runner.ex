defmodule SymphonyElixir.PipelineRunner do
  @moduledoc """
  Execution engine for pipelines.

  Walks the pipeline graph, dispatching issue nodes to the orchestrator,
  pausing at gates for human/automated decisions, and handling loops.

  Each active pipeline run is tracked as a process that polls state
  and advances nodes when their predecessors complete.
  """

  use GenServer

  require Logger

  alias SymphonyElixir.LocalBoard

  @poll_interval_ms 3_000

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Start executing a pipeline run. The run must already exist in LocalBoard."
  def start_run(pipeline_id, run_id) do
    GenServer.cast(__MODULE__, {:start_run, pipeline_id, run_id})
  end

  @doc "Notify the runner that a gate decision was made (called after LocalBoard update)."
  def gate_decided(run_id, node_id, action) do
    GenServer.cast(__MODULE__, {:gate_decided, run_id, node_id, action})
  end

  @doc "Get status of all tracked runs."
  def list_active do
    GenServer.call(__MODULE__, :list_active)
  end

  # --- Server ---

  @impl true
  def init(_opts) do
    {:ok, %{runs: %{}}}
  end

  @impl true
  def handle_cast({:start_run, pipeline_id, run_id}, state) do
    case LocalBoard.get_pipeline(pipeline_id) do
      {:ok, pipeline} ->
        run_state = %{
          pipeline_id: pipeline_id,
          run_id: run_id,
          pipeline: pipeline,
          timer_ref: schedule_tick(run_id)
        }

        state = put_in(state, [:runs, run_id], run_state)
        # Immediately advance from start nodes
        advance_run(pipeline_id, run_id, pipeline)
        {:noreply, state}

      {:error, :not_found} ->
        Logger.warning("PipelineRunner: pipeline #{pipeline_id} not found")
        {:noreply, state}
    end
  end

  def handle_cast({:gate_decided, run_id, node_id, action}, state) do
    case Map.get(state.runs, run_id) do
      nil ->
        {:noreply, state}

      run_state ->
        pipeline = run_state.pipeline

        if action == "approve" do
          # Gate passed — advance to successors via output edges
          advance_from_node(run_state.pipeline_id, run_id, node_id, pipeline)
        else
          # Gate rejected — follow reject edges and reset target nodes to pending
          reject_edges =
            Enum.filter(pipeline.edges, fn e ->
              e.source_node_id == node_id and e.source_port == "reject"
            end)

          Enum.each(reject_edges, fn edge ->
            # Reset the reject target and all its downstream nodes
            reset_node_and_downstream(run_id, edge.target_node_id, pipeline)
          end)

          # Re-advance to pick up the newly pending nodes
          advance_run(run_state.pipeline_id, run_id, pipeline)
        end

        {:noreply, state}
    end
  end

  @impl true
  def handle_call(:list_active, _from, state) do
    active = Map.keys(state.runs)
    {:reply, active, state}
  end

  @impl true
  def handle_info({:tick, run_id}, state) do
    case Map.get(state.runs, run_id) do
      nil ->
        {:noreply, state}

      run_state ->
        case LocalBoard.get_pipeline_run(run_state.pipeline_id, run_id) do
          {:ok, run} ->
            if run.status in ["completed", "failed", "cancelled"] do
              # Run is done, stop tracking
              {:noreply, %{state | runs: Map.delete(state.runs, run_id)}}
            else
              # Check if any issue nodes that are "running" have completed
              check_issue_completions(run_state.pipeline_id, run_id, run_state.pipeline, run)

              # Try to advance
              advance_run(run_state.pipeline_id, run_id, run_state.pipeline)

              # Check if all nodes are done
              check_pipeline_completion(run_state.pipeline_id, run_id, run_state.pipeline)

              # Schedule next tick
              timer_ref = schedule_tick(run_id)
              state = put_in(state, [:runs, run_id, :timer_ref], timer_ref)
              {:noreply, state}
            end

          {:error, :not_found} ->
            {:noreply, %{state | runs: Map.delete(state.runs, run_id)}}
        end
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --- Internal ---

  defp schedule_tick(run_id) do
    Process.send_after(self(), {:tick, run_id}, @poll_interval_ms)
  end

  defp advance_run(pipeline_id, run_id, pipeline) do
    case LocalBoard.get_pipeline_run(pipeline_id, run_id) do
      {:ok, run} ->
        # Find nodes whose predecessors are all completed and that are still pending
        ready_nodes = find_ready_nodes(pipeline, run)

        Enum.each(ready_nodes, fn node ->
          activate_node(pipeline_id, run_id, node, pipeline)
        end)

      {:error, _} ->
        :ok
    end
  end

  defp advance_from_node(pipeline_id, run_id, completed_node_id, pipeline) do
    # Find successor nodes via output edges
    successor_edges =
      Enum.filter(pipeline.edges, fn e ->
        e.source_node_id == completed_node_id and e.source_port == "output"
      end)

    case LocalBoard.get_pipeline_run(pipeline_id, run_id) do
      {:ok, run} ->
        Enum.each(successor_edges, fn edge ->
          target = Enum.find(pipeline.nodes, &(&1.id == edge.target_node_id))

          if target do
            # Check if all predecessors of this target are completed
            preds = predecessors(pipeline, target.id)

            all_done =
              Enum.all?(preds, fn pred_id ->
                Map.get(run.node_states, pred_id) == "completed"
              end)

            if all_done do
              activate_node(pipeline_id, run_id, target, pipeline)
            end
          end
        end)

      {:error, _} ->
        :ok
    end
  end

  defp activate_node(pipeline_id, run_id, node, pipeline) do
    case node.type do
      "start" ->
        LocalBoard.update_node_state(run_id, node.id, "completed")
        advance_from_node(pipeline_id, run_id, node.id, pipeline)

      "end" ->
        LocalBoard.update_node_state(run_id, node.id, "completed")

      "issue" ->
        LocalBoard.update_node_state(run_id, node.id, "running")

        # Dispatch the linked issue to the orchestrator by moving it to Todo
        if node.issue_id do
          case LocalBoard.get_issue(node.issue_id) do
            {:ok, _issue} ->
              LocalBoard.move_issue(node.issue_id, "Todo")

            {:error, _} ->
              Logger.warning(
                "PipelineRunner: issue #{node.issue_id} not found for node #{node.id}"
              )

              LocalBoard.update_node_state(run_id, node.id, "failed")
          end
        else
          # No linked issue — mark as completed immediately
          LocalBoard.update_node_state(run_id, node.id, "completed")
          advance_from_node(pipeline_id, run_id, node.id, pipeline)
        end

      type when type in ["human_gate", "quality_gate"] ->
        LocalBoard.update_node_state(run_id, node.id, "waiting_gate")

      # For quality gates, we could auto-trigger checks here
      # For now, both gate types wait for manual decision via API

      "loop" ->
        # Loop nodes pass through — they act as markers
        # The actual looping is handled by reject edges going back
        LocalBoard.update_node_state(run_id, node.id, "completed")
        advance_from_node(pipeline_id, run_id, node.id, pipeline)

      "kb_sync" ->
        # KB sync — pause as gate, user decides to "Send to KB" or "Skip"
        LocalBoard.update_node_state(run_id, node.id, "waiting_gate")

      "integration" ->
        # Integration nodes — mark running, then completed
        # Actual integration logic will be added in integration connectors
        LocalBoard.update_node_state(run_id, node.id, "running")
        LocalBoard.update_node_state(run_id, node.id, "completed")
        advance_from_node(pipeline_id, run_id, node.id, pipeline)

      _ ->
        LocalBoard.update_node_state(run_id, node.id, "completed")
        advance_from_node(pipeline_id, run_id, node.id, pipeline)
    end
  end

  defp find_ready_nodes(pipeline, run) do
    Enum.filter(pipeline.nodes, fn node ->
      state = Map.get(run.node_states, node.id, "pending")

      if state == "pending" do
        preds = predecessors(pipeline, node.id)
        # Node is ready if it has no predecessors (start node) or all predecessors are completed
        preds == [] or
          Enum.all?(preds, fn pred_id ->
            Map.get(run.node_states, pred_id) == "completed"
          end)
      else
        false
      end
    end)
  end

  defp predecessors(pipeline, node_id) do
    pipeline.edges
    |> Enum.filter(fn e -> e.target_node_id == node_id end)
    |> Enum.map(& &1.source_node_id)
  end

  defp check_issue_completions(pipeline_id, run_id, pipeline, run) do
    # Check issue nodes that are "running" — see if the linked issue has reached Done/Review
    pipeline.nodes
    |> Enum.filter(fn n ->
      n.type == "issue" and Map.get(run.node_states, n.id) == "running" and n.issue_id
    end)
    |> Enum.each(fn node ->
      case LocalBoard.get_issue(node.issue_id) do
        {:ok, issue} ->
          if MapSet.member?(terminal_states(), String.downcase(issue.state)) do
            LocalBoard.update_node_state(run_id, node.id, "completed")
            advance_from_node(pipeline_id, run_id, node.id, pipeline)
          end

        {:error, _} ->
          :ok
      end
    end)
  end

  defp check_pipeline_completion(pipeline_id, run_id, pipeline) do
    case LocalBoard.get_pipeline_run(pipeline_id, run_id) do
      {:ok, run} ->
        all_terminal =
          Enum.all?(pipeline.nodes, fn node ->
            state = Map.get(run.node_states, node.id, "pending")
            state in ["completed", "skipped", "failed"]
          end)

        if all_terminal do
          has_failures =
            Enum.any?(pipeline.nodes, fn node ->
              Map.get(run.node_states, node.id) == "failed"
            end)

          status = if has_failures, do: "failed", else: "completed"
          LocalBoard.update_pipeline_run_status(run_id, status)
        end

      {:error, _} ->
        :ok
    end
  end

  defp reset_node_and_downstream(run_id, node_id, pipeline) do
    reset_node_and_downstream(run_id, node_id, pipeline, MapSet.new())
  end

  defp reset_node_and_downstream(run_id, node_id, pipeline, visited) do
    if MapSet.member?(visited, node_id) do
      visited
    else
      LocalBoard.update_node_state(run_id, node_id, "pending")
      visited = MapSet.put(visited, node_id)

      # Find downstream nodes via output edges from this node
      successors =
        pipeline.edges
        |> Enum.filter(fn e -> e.source_node_id == node_id end)
        |> Enum.map(& &1.target_node_id)

      Enum.reduce(successors, visited, fn succ_id, acc ->
        reset_node_and_downstream(run_id, succ_id, pipeline, acc)
      end)
    end
  end

  defp terminal_states do
    # States considered "done" for issue nodes. Uses lowercased matching.
    MapSet.new(["done", "review", "archived", "cancelled"])
  end
end

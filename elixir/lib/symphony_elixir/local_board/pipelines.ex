defmodule SymphonyElixir.LocalBoard.Pipelines do
  @moduledoc """
  Pipeline-related operations for the local board.

  Handles CRUD for pipelines (visual workflow definitions) and pipeline runs
  (execution instances). Pipelines orchestrate issues through a graph of nodes
  connected by edges, with human gates, quality gates, loops, and integrations.
  """

  alias SymphonyElixir.LocalBoard.Persistence

  import SymphonyElixir.LocalBoard.Helpers

  @valid_node_types ~w(issue human_gate quality_gate loop kb_sync integration start end)
  @valid_run_statuses ~w(running paused completed failed cancelled)
  @valid_node_states ~w(pending running completed failed waiting_gate skipped on_hold)
  @valid_gate_actions ~w(approve reject hold)
  @gate_node_types ~w(human_gate quality_gate kb_sync)

  # Valid state transitions: from_state => [allowed_to_states]
  @valid_transitions %{
    "pending" => ~w(running completed skipped waiting_gate),
    "running" => ~w(completed failed waiting_gate),
    "completed" => ~w(pending),
    "failed" => ~w(pending running),
    "waiting_gate" => ~w(completed pending on_hold),
    "skipped" => ~w(pending),
    "on_hold" => ~w(waiting_gate completed pending)
  }

  # --- Pipeline CRUD ---

  def list_pipelines(board) do
    pipelines = board.pipelines |> Map.values() |> Enum.sort_by(& &1.name)
    {:reply, pipelines, board}
  end

  def get_pipeline(board, id) do
    case Map.get(board.pipelines, id) do
      nil -> {:reply, {:error, :not_found}, board}
      pipeline -> {:reply, {:ok, pipeline}, board}
    end
  end

  def create_pipeline(board, attrs) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    id = generate_id()

    pipeline = %{
      id: id,
      name: Map.get(attrs, "name", "Untitled Pipeline") |> String.trim(),
      description: Map.get(attrs, "description"),
      product_id: Map.get(attrs, "product_id"),
      nodes: parse_nodes(Map.get(attrs, "nodes", [])),
      edges: parse_edges(Map.get(attrs, "edges", [])),
      settings: parse_settings(Map.get(attrs, "settings", %{})),
      created_at: now,
      updated_at: now
    }

    board = %{board | pipelines: Map.put(board.pipelines, id, pipeline)}
    Persistence.persist(board)
    {:reply, {:ok, pipeline}, board}
  end

  def update_pipeline(board, id, attrs) do
    case Map.get(board.pipelines, id) do
      nil ->
        {:reply, {:error, :not_found}, board}

      existing ->
        now = DateTime.utc_now() |> DateTime.to_iso8601()

        updated =
          existing
          |> maybe_update(:name, attrs)
          |> maybe_update(:description, attrs)
          |> maybe_update(:product_id, attrs)
          |> maybe_update_nodes(attrs)
          |> maybe_update_edges(attrs)
          |> maybe_update_settings(attrs)
          |> Map.put(:updated_at, now)

        # Fix K: Validate graph structure if nodes or edges changed
        if Map.has_key?(attrs, "nodes") or Map.has_key?(attrs, "edges") do
          case validate_graph(updated) do
            :ok ->
              board = %{board | pipelines: Map.put(board.pipelines, id, updated)}
              Persistence.persist(board)
              {:reply, {:ok, updated}, board}

            {:error, reason} ->
              {:reply, {:error, reason}, board}
          end
        else
          board = %{board | pipelines: Map.put(board.pipelines, id, updated)}
          Persistence.persist(board)
          {:reply, {:ok, updated}, board}
        end
    end
  end

  def delete_pipeline(board, id) do
    if Map.has_key?(board.pipelines, id) do
      board = %{board | pipelines: Map.delete(board.pipelines, id)}
      # Also delete any runs for this pipeline
      runs =
        board.pipeline_runs
        |> Enum.reject(fn {_rid, run} -> run.pipeline_id == id end)
        |> Map.new()

      board = %{board | pipeline_runs: runs}
      Persistence.persist(board)
      {:reply, :ok, board}
    else
      {:reply, {:error, :not_found}, board}
    end
  end

  # --- Pipeline Run CRUD ---

  def create_pipeline_run(board, pipeline_id) do
    case Map.get(board.pipelines, pipeline_id) do
      nil ->
        {:reply, {:error, :not_found}, board}

      pipeline ->
        # Fix L: Concurrency guard — only one active run per pipeline
        has_active =
          board.pipeline_runs
          |> Map.values()
          |> Enum.any?(fn run ->
            run.pipeline_id == pipeline_id and run.status in ["running", "paused"]
          end)

        if has_active do
          {:reply, {:error, :already_running}, board}
        else
          now = DateTime.utc_now() |> DateTime.to_iso8601()
          id = generate_id()

          node_states =
            Map.new(pipeline.nodes, fn node ->
              initial = if node.type == "start", do: "completed", else: "pending"
              {node.id, initial}
            end)

          node_attempts = Map.new(pipeline.nodes, fn node -> {node.id, 0} end)

          run = %{
            id: id,
            pipeline_id: pipeline_id,
            status: "running",
            node_states: node_states,
            node_attempts: node_attempts,
            node_issue_ids: %{},
            node_outputs: %{},
            gate_decisions: [],
            started_at: now,
            completed_at: nil
          }

          board = %{board | pipeline_runs: Map.put(board.pipeline_runs, id, run)}
          Persistence.persist(board)
          {:reply, {:ok, run}, board}
        end
    end
  end

  # Fix M: Validate pipeline_id ownership
  def get_pipeline_run(board, pipeline_id, run_id) do
    case Map.get(board.pipeline_runs, run_id) do
      nil ->
        {:reply, {:error, :not_found}, board}

      run ->
        if run.pipeline_id == pipeline_id do
          {:reply, {:ok, run}, board}
        else
          {:reply, {:error, :not_found}, board}
        end
    end
  end

  def get_pipeline_run_by_id(board, run_id) do
    case Map.get(board.pipeline_runs, run_id) do
      nil -> {:reply, {:error, :not_found}, board}
      run -> {:reply, {:ok, run}, board}
    end
  end

  def update_pipeline_run_status(board, run_id, status) when status in @valid_run_statuses do
    case Map.get(board.pipeline_runs, run_id) do
      nil ->
        {:reply, {:error, :not_found}, board}

      run ->
        now = DateTime.utc_now() |> DateTime.to_iso8601()

        completed_at =
          if status in ["completed", "failed", "cancelled"], do: now, else: run.completed_at

        updated = %{run | status: status, completed_at: completed_at}
        board = %{board | pipeline_runs: Map.put(board.pipeline_runs, run_id, updated)}
        Persistence.persist(board)
        {:reply, {:ok, updated}, board}
    end
  end

  def update_pipeline_run_status(board, _run_id, _status) do
    {:reply, {:error, :invalid_status}, board}
  end

  def update_node_state(board, run_id, node_id, state) when state in @valid_node_states do
    case Map.get(board.pipeline_runs, run_id) do
      nil ->
        {:reply, {:error, :not_found}, board}

      run ->
        current = Map.get(run.node_states, node_id, "pending")

        if valid_transition?(current, state) do
          node_states = Map.put(run.node_states, node_id, state)

          node_attempts =
            if state == "running" do
              Map.update(run.node_attempts, node_id, 1, &(&1 + 1))
            else
              run.node_attempts
            end

          updated = %{run | node_states: node_states, node_attempts: node_attempts}
          board = %{board | pipeline_runs: Map.put(board.pipeline_runs, run_id, updated)}
          Persistence.persist(board)
          {:reply, {:ok, updated}, board}
        else
          {:reply, {:error, {:invalid_transition, current, state}}, board}
        end
    end
  end

  def update_node_state(board, _run_id, _node_id, _state) do
    {:reply, {:error, :invalid_state}, board}
  end

  @doc "Store a dynamically created issue_id for a node in a run."
  def set_run_node_issue_id(board, run_id, node_id, issue_id) do
    case Map.get(board.pipeline_runs, run_id) do
      nil ->
        {:reply, {:error, :not_found}, board}

      run ->
        node_issue_ids = Map.put(run.node_issue_ids || %{}, node_id, issue_id)
        updated = %{run | node_issue_ids: node_issue_ids}
        board = %{board | pipeline_runs: Map.put(board.pipeline_runs, run_id, updated)}
        Persistence.persist(board)
        {:reply, {:ok, updated}, board}
    end
  end

  @doc "Store output data from a completed node (artifact passing)."
  def set_node_output(board, run_id, node_id, output) when is_map(output) do
    case Map.get(board.pipeline_runs, run_id) do
      nil ->
        {:reply, {:error, :not_found}, board}

      run ->
        node_outputs = Map.put(run.node_outputs || %{}, node_id, output)
        updated = %{run | node_outputs: node_outputs}
        board = %{board | pipeline_runs: Map.put(board.pipeline_runs, run_id, updated)}
        Persistence.persist(board)
        {:reply, {:ok, updated}, board}
    end
  end

  @doc "Get outputs from predecessor nodes for building downstream context."
  def get_predecessor_outputs(board, run_id, node_id) do
    case Map.get(board.pipeline_runs, run_id) do
      nil ->
        {:reply, {:error, :not_found}, board}

      run ->
        pipeline = Map.get(board.pipelines, run.pipeline_id)

        if pipeline do
          pred_ids =
            pipeline.edges
            |> Enum.filter(&(&1.target_node_id == node_id && &1.source_port == "output"))
            |> Enum.map(& &1.source_node_id)

          outputs =
            Enum.reduce(pred_ids, %{}, fn pid, acc ->
              case Map.get(run.node_outputs || %{}, pid) do
                nil -> acc
                output -> Map.put(acc, pid, output)
              end
            end)

          {:reply, {:ok, outputs}, board}
        else
          {:reply, {:ok, %{}}, board}
        end
    end
  end

  # Fix N: Validate gate action + A8: Validate node is actually a gate
  def record_gate_decision(board, run_id, node_id, action, feedback) do
    if action not in @valid_gate_actions do
      {:reply, {:error, :invalid_action}, board}
    else
      case Map.get(board.pipeline_runs, run_id) do
        nil ->
          {:reply, {:error, :not_found}, board}

        run ->
          # A8: Validate the node is a gate type
          pipeline = Map.get(board.pipelines, run.pipeline_id)
          node = pipeline && Enum.find(pipeline.nodes, &(&1.id == node_id))

          cond do
            is_nil(node) ->
              {:reply, {:error, :node_not_found}, board}

            node.type not in @gate_node_types ->
              {:reply, {:error, :not_a_gate_node}, board}

            true ->
              now = DateTime.utc_now() |> DateTime.to_iso8601()

              decision = %{
                node_id: node_id,
                action: action,
                feedback: feedback,
                decided_at: now
              }

              # On approve → completed, reject → pending (runner resets downstream),
              # hold → on_hold (pauses this gate until resumed)
              new_state =
                case action do
                  "approve" -> "completed"
                  "reject" -> "pending"
                  "hold" -> "on_hold"
                end

              node_states = Map.put(run.node_states, node_id, new_state)

              updated = %{
                run
                | gate_decisions: run.gate_decisions ++ [decision],
                  node_states: node_states
              }

              board = %{board | pipeline_runs: Map.put(board.pipeline_runs, run_id, updated)}
              Persistence.persist(board)
              {:reply, {:ok, updated}, board}
          end
      end
    end
  end

  def list_pipeline_runs(board, pipeline_id) do
    runs =
      board.pipeline_runs
      |> Map.values()
      |> Enum.filter(&(&1.pipeline_id == pipeline_id))
      |> Enum.sort_by(& &1.started_at, :desc)

    {:reply, runs, board}
  end

  def list_all_active_runs(board) do
    runs =
      board.pipeline_runs
      |> Map.values()
      |> Enum.filter(&(&1.status in ["running", "paused"]))
      |> Enum.sort_by(& &1.started_at, :desc)

    {:reply, runs, board}
  end

  # --- Graph Validation (Fix K) ---

  @doc "Validate pipeline graph structure. Returns :ok or {:error, reason}."
  def validate_graph(pipeline) do
    nodes = pipeline.nodes
    edges = pipeline.edges
    node_ids = MapSet.new(nodes, & &1.id)

    cond do
      # Must have at least one start node
      not Enum.any?(nodes, &(&1.type == "start")) ->
        {:error, :no_start_node}

      # Must have at least one end node
      not Enum.any?(nodes, &(&1.type == "end")) ->
        {:error, :no_end_node}

      # At most one start node
      Enum.count(nodes, &(&1.type == "start")) > 1 ->
        {:error, :multiple_start_nodes}

      # All edges must reference valid node IDs
      not edges_valid?(edges, node_ids) ->
        {:error, :invalid_edge_reference}

      # Graph must be connected (all nodes reachable from start)
      not graph_connected?(nodes, edges) ->
        {:error, :disconnected_graph}

      true ->
        :ok
    end
  end

  defp edges_valid?(edges, node_ids) do
    Enum.all?(edges, fn edge ->
      MapSet.member?(node_ids, edge.source_node_id) and
        MapSet.member?(node_ids, edge.target_node_id)
    end)
  end

  defp graph_connected?(nodes, edges) do
    if Enum.empty?(nodes) do
      true
    else
      start_node = Enum.find(nodes, &(&1.type == "start"))

      if start_node == nil do
        false
      else
        # BFS from start node following edges in both directions (undirected connectivity)
        adjacency =
          Enum.reduce(edges, %{}, fn edge, acc ->
            acc
            |> Map.update(edge.source_node_id, [edge.target_node_id], &[edge.target_node_id | &1])
            |> Map.update(edge.target_node_id, [edge.source_node_id], &[edge.source_node_id | &1])
          end)

        reachable = bfs(MapSet.new([start_node.id]), [start_node.id], adjacency)
        node_ids = MapSet.new(nodes, & &1.id)
        MapSet.equal?(reachable, node_ids)
      end
    end
  end

  defp bfs(visited, [], _adjacency), do: visited

  defp bfs(visited, queue, adjacency) do
    next_queue =
      Enum.flat_map(queue, fn node_id ->
        neighbors = Map.get(adjacency, node_id, [])

        Enum.filter(neighbors, fn n ->
          not MapSet.member?(visited, n)
        end)
      end)

    new_visited = Enum.reduce(next_queue, visited, &MapSet.put(&2, &1))
    bfs(new_visited, next_queue, adjacency)
  end

  # --- Parsing helpers ---

  defp parse_nodes(nodes) when is_list(nodes) do
    Enum.map(nodes, fn n ->
      type = Map.get(n, "type", "issue")

      %{
        id: Map.get(n, "id", generate_id()),
        type: if(type in @valid_node_types, do: type, else: "issue"),
        issue_id: Map.get(n, "issue_id"),
        label: Map.get(n, "label", ""),
        config: Map.get(n, "config", %{}),
        position: parse_position(Map.get(n, "position", %{})),
        loop_max_retries: Map.get(n, "loop_max_retries"),
        loop_condition: Map.get(n, "loop_condition")
      }
    end)
  end

  defp parse_nodes(_), do: []

  defp parse_edges(edges) when is_list(edges) do
    Enum.map(edges, fn e ->
      %{
        id: Map.get(e, "id", generate_id()),
        source_node_id: Map.get(e, "source_node_id"),
        target_node_id: Map.get(e, "target_node_id"),
        source_port: Map.get(e, "source_port", "output"),
        label: Map.get(e, "label")
      }
    end)
  end

  defp parse_edges(_), do: []

  defp parse_position(pos) when is_map(pos) do
    %{
      x: parse_float(Map.get(pos, "x", 0)),
      y: parse_float(Map.get(pos, "y", 0))
    }
  end

  defp parse_position(_), do: %{x: 0, y: 0}

  defp parse_float(val) when is_float(val), do: val
  defp parse_float(val) when is_integer(val), do: val * 1.0

  defp parse_float(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp parse_float(_), do: 0.0

  defp parse_settings(settings) when is_map(settings) do
    %{
      max_retries: Map.get(settings, "max_retries", %{}),
      notifications: Map.get(settings, "notifications", true),
      integrations: Map.get(settings, "integrations", %{})
    }
  end

  defp parse_settings(_), do: %{max_retries: %{}, notifications: true, integrations: %{}}

  defp maybe_update_nodes(pipeline, attrs) do
    if Map.has_key?(attrs, "nodes") do
      %{pipeline | nodes: parse_nodes(attrs["nodes"])}
    else
      pipeline
    end
  end

  defp maybe_update_edges(pipeline, attrs) do
    if Map.has_key?(attrs, "edges") do
      %{pipeline | edges: parse_edges(attrs["edges"])}
    else
      pipeline
    end
  end

  defp maybe_update_settings(pipeline, attrs) do
    if Map.has_key?(attrs, "settings") do
      %{pipeline | settings: parse_settings(attrs["settings"])}
    else
      pipeline
    end
  end

  # A2: State machine enforcement — validate transition is allowed
  defp valid_transition?(from, to) when from == to, do: true

  defp valid_transition?(from, to) do
    allowed = Map.get(@valid_transitions, from, [])
    to in allowed
  end
end

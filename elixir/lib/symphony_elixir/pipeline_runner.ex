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
  @run_timeout_ms 24 * 60 * 60 * 1_000
  @node_timeout_ms 4 * 60 * 60 * 1_000

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

  @doc "Re-register a run with the runner (used by resume)."
  def resume_run(pipeline_id, run_id) do
    GenServer.cast(__MODULE__, {:start_run, pipeline_id, run_id})
  end

  @doc "Force-complete a node (skip it). Used to unblock stuck pipelines."
  def force_complete_node(run_id, node_id) do
    GenServer.cast(__MODULE__, {:force_complete, run_id, node_id})
  end

  @doc "Get status of all tracked runs."
  def list_active do
    GenServer.call(__MODULE__, :list_active)
  end

  # --- Server ---

  @impl true
  def init(_opts) do
    # Fix G: Crash recovery — schedule recovery after init to avoid blocking startup
    Process.send_after(self(), :recover_active_runs, 500)
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
          timer_ref: schedule_tick(run_id),
          started_at: System.monotonic_time(:millisecond),
          node_activated_at: %{}
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

        case action do
          "approve" ->
            # Fix P: KB sync — execute sync BEFORE advancing
            node = Enum.find(pipeline.nodes, &(&1.id == node_id))

            if node && node.type == "kb_sync" do
              execute_kb_sync(node, pipeline, run_id)
            end

            # Gate passed — advance to successors via output edges
            advance_from_node(run_state.pipeline_id, run_id, node_id, pipeline)

          "reject" ->
            # Gate rejected — inject feedback into downstream issue rerun_hints
            feedback = get_gate_feedback(run_id, node_id)
            inject_feedback_into_downstream_issues(node_id, pipeline, run_id, feedback)

            # Follow reject edges and reset target nodes to pending
            reject_edges =
              Enum.filter(pipeline.edges, fn e ->
                e.source_node_id == node_id and e.source_port == "reject"
              end)

            Enum.each(reject_edges, fn edge ->
              reset_node_and_downstream(run_id, edge.target_node_id, pipeline)
            end)

            # Re-advance to pick up the newly pending nodes
            advance_run(run_state.pipeline_id, run_id, pipeline)

          "hold" ->
            # Gate on hold — node state already set to "on_hold" by LocalBoard
            Logger.info("PipelineRunner: gate #{node_id} put on hold")

          _ ->
            :ok
        end

        {:noreply, state}
    end
  end

  # Gap #9: Force-complete a stuck/failed node
  def handle_cast({:force_complete, run_id, node_id}, state) do
    case Map.get(state.runs, run_id) do
      nil ->
        {:noreply, state}

      run_state ->
        Logger.info("PipelineRunner: force-completing node #{node_id}")
        LocalBoard.update_node_state(run_id, node_id, "completed")
        advance_from_node(run_state.pipeline_id, run_id, node_id, run_state.pipeline)
        {:noreply, state}
    end
  end

  # Track node activation time (internal cast to avoid passing state around)
  def handle_cast({:_track_activation, run_id, node_id}, state) do
    now = System.monotonic_time(:millisecond)

    state =
      update_in(state, [:runs, run_id], fn
        nil ->
          nil

        run_state ->
          put_in(run_state, [:node_activated_at, node_id], now)
      end)

    {:noreply, state}
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
              # Run is done, stop tracking and cancel timer
              {:noreply, stop_run(state, run_id)}
            else
              # Fix C: If paused, just reschedule tick without advancing
              if run.status == "paused" do
                timer_ref = schedule_tick(run_id)
                state = put_in(state, [:runs, run_id, :timer_ref], timer_ref)
                {:noreply, state}
              else
                # Fix H: Check run-level timeout
                now = System.monotonic_time(:millisecond)
                elapsed = now - run_state.started_at

                if elapsed > @run_timeout_ms do
                  Logger.warning("PipelineRunner: run #{run_id} timed out after #{elapsed}ms")
                  LocalBoard.update_pipeline_run_status(run_id, "failed")
                  {:noreply, stop_run(state, run_id)}
                else
                  # Check if any issue nodes that are "running" have completed
                  check_issue_completions(
                    run_state.pipeline_id,
                    run_id,
                    run_state.pipeline,
                    run
                  )

                  # Fix H: Check per-node timeouts
                  check_node_timeouts(run_id, run_state)

                  # Gap #4: Auto-approve gates that have timed out
                  maybe_auto_approve_gates(run_id, run_state)

                  # Gap #10: Retry failed integration nodes with backoff
                  maybe_retry_failed_integrations(
                    run_state.pipeline_id,
                    run_id,
                    run_state
                  )

                  # Try to advance
                  advance_run(run_state.pipeline_id, run_id, run_state.pipeline)

                  # Check if all nodes are done
                  check_pipeline_completion(run_state.pipeline_id, run_id, run_state.pipeline)

                  # Schedule next tick
                  timer_ref = schedule_tick(run_id)
                  state = put_in(state, [:runs, run_id, :timer_ref], timer_ref)
                  {:noreply, state}
                end
              end
            end

          {:error, :not_found} ->
            {:noreply, stop_run(state, run_id)}
        end
    end
  end

  # Fix G: Crash recovery — resume any runs that are still "running" in LocalBoard
  def handle_info(:recover_active_runs, state) do
    active_runs = LocalBoard.list_all_active_runs()

    state =
      Enum.reduce(active_runs, state, fn run, acc ->
        if Map.has_key?(acc.runs, run.id) do
          acc
        else
          case LocalBoard.get_pipeline(run.pipeline_id) do
            {:ok, pipeline} ->
              run_state = %{
                pipeline_id: run.pipeline_id,
                run_id: run.id,
                pipeline: pipeline,
                timer_ref: schedule_tick(run.id),
                started_at: System.monotonic_time(:millisecond),
                node_activated_at: %{}
              }

              Logger.info("PipelineRunner: recovered active run #{run.id}")
              put_in(acc, [:runs, run.id], run_state)

            {:error, _} ->
              acc
          end
        end
      end)

    {:noreply, state}
  end

  # Fix I: Async integration completion callback
  def handle_info({:integration_done, run_id, node_id, result}, state) do
    case Map.get(state.runs, run_id) do
      nil ->
        {:noreply, state}

      run_state ->
        case result do
          {:ok, output} ->
            # A6: Store integration result as node output for downstream nodes
            if is_map(output) do
              LocalBoard.set_node_output(run_id, node_id, output)
            end

            LocalBoard.update_node_state(run_id, node_id, "completed")
            advance_from_node(run_state.pipeline_id, run_id, node_id, run_state.pipeline)

          {:error, reason} ->
            Logger.error("Integration failed for node #{node_id}: #{inspect(reason)}")
            LocalBoard.update_node_state(run_id, node_id, "failed")
        end

        {:noreply, state}
    end
  end

  # Gap #1: Quality gate automated check result
  def handle_info({:quality_check_done, run_id, node_id, result}, state) do
    case Map.get(state.runs, run_id) do
      nil ->
        {:noreply, state}

      run_state ->
        case result do
          {:ok, check_results} ->
            all_passed = Enum.all?(check_results, fn {_name, status} -> status == :pass end)

            if all_passed do
              Logger.info("Quality checks passed for node #{node_id}")
              LocalBoard.update_node_state(run_id, node_id, "completed")

              LocalBoard.record_gate_decision(
                run_id,
                node_id,
                "approve",
                "Auto-approved: all checks passed"
              )

              advance_from_node(run_state.pipeline_id, run_id, node_id, run_state.pipeline)
            else
              failed =
                check_results
                |> Enum.filter(fn {_name, status} -> status != :pass end)
                |> Enum.map(fn {name, _} -> name end)
                |> Enum.join(", ")

              Logger.info(
                "Quality checks failed for node #{node_id}: #{failed} — waiting for manual review"
              )

              # Store check results on the run for the UI to display
              store_check_results(run_id, node_id, check_results)
              LocalBoard.update_node_state(run_id, node_id, "waiting_gate")
            end

          {:error, reason} ->
            Logger.error("Quality check execution failed for node #{node_id}: #{inspect(reason)}")
            store_check_results(run_id, node_id, [{"error", :fail}])
            LocalBoard.update_node_state(run_id, node_id, "waiting_gate")
        end

        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --- Internal ---

  defp schedule_tick(run_id) do
    Process.send_after(self(), {:tick, run_id}, @poll_interval_ms)
  end

  # Fix J: Cancel existing timer before removing run
  defp stop_run(state, run_id) do
    case Map.get(state.runs, run_id) do
      %{timer_ref: ref} when is_reference(ref) ->
        Process.cancel_timer(ref)
        %{state | runs: Map.delete(state.runs, run_id)}

      _ ->
        %{state | runs: Map.delete(state.runs, run_id)}
    end
  end

  # Fix A: advance_run reads state once and uses it atomically
  defp advance_run(pipeline_id, run_id, pipeline) do
    case LocalBoard.get_pipeline_run(pipeline_id, run_id) do
      {:ok, run} ->
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

    # Fix A: Read state once for all successor checks
    case LocalBoard.get_pipeline_run(pipeline_id, run_id) do
      {:ok, _run} ->
        Enum.each(successor_edges, fn edge ->
          target = Enum.find(pipeline.nodes, &(&1.id == edge.target_node_id))

          if target do
            # Re-read state since activate_node may have changed it
            case LocalBoard.get_pipeline_run(pipeline_id, run_id) do
              {:ok, fresh_run} ->
                target_state = Map.get(fresh_run.node_states, target.id)

                if target_state == "pending" do
                  preds = predecessors(pipeline, target.id)

                  all_done =
                    Enum.all?(preds, fn pred_id ->
                      Map.get(fresh_run.node_states, pred_id) == "completed"
                    end)

                  if all_done do
                    activate_node(pipeline_id, run_id, target, pipeline)
                  end
                end

              {:error, _} ->
                :ok
            end
          end
        end)

      {:error, _} ->
        :ok
    end
  end

  defp activate_node(pipeline_id, run_id, node, pipeline) do
    # Fix A: Double-check node is still pending before activating
    case LocalBoard.get_pipeline_run(pipeline_id, run_id) do
      {:ok, run} ->
        current_state = Map.get(run.node_states, node.id)

        unless current_state == "pending" or node.type == "start" do
          # Node already activated by another path, skip
          :ok
        else
          # Fix E+F: Check max_retries before activating
          if should_fail_max_retries?(node, run) do
            Logger.warning(
              "PipelineRunner: node #{node.id} exceeded max retries " <>
                "(#{Map.get(run.node_attempts, node.id, 0)})"
            )

            LocalBoard.update_node_state(run_id, node.id, "failed")
          else
            do_activate_node(pipeline_id, run_id, node, pipeline)
          end
        end

      {:error, _} ->
        :ok
    end
  end

  defp do_activate_node(pipeline_id, run_id, node, pipeline) do
    # Track activation time for node timeout
    GenServer.cast(self(), {:_track_activation, run_id, node.id})

    case node.type do
      "start" ->
        LocalBoard.update_node_state(run_id, node.id, "completed")
        advance_from_node(pipeline_id, run_id, node.id, pipeline)

      "end" ->
        LocalBoard.update_node_state(run_id, node.id, "completed")

      "issue" ->
        LocalBoard.update_node_state(run_id, node.id, "running")

        # Resolve the issue_id: static link, runtime-created, or template
        issue_id = resolve_issue_for_node(pipeline, run_id, node)

        if issue_id do
          case LocalBoard.get_issue(issue_id) do
            {:ok, _issue} ->
              LocalBoard.move_issue(issue_id, "Todo")

            {:error, _} ->
              Logger.warning("PipelineRunner: issue #{issue_id} not found for node #{node.id}")

              LocalBoard.update_node_state(run_id, node.id, "failed")
          end
        else
          # No linked issue and no template — mark as completed immediately
          LocalBoard.update_node_state(run_id, node.id, "completed")
          advance_from_node(pipeline_id, run_id, node.id, pipeline)
        end

      "human_gate" ->
        LocalBoard.update_node_state(run_id, node.id, "waiting_gate")

      "quality_gate" ->
        # Run automated checks if configured, otherwise wait for manual decision
        checks = get_in(node, [:config, "checks"]) || []
        check_commands = get_in(node, [:config, "check_commands"]) || %{}

        if check_commands != %{} and map_size(check_commands) > 0 do
          # Has executable check commands — run them async
          LocalBoard.update_node_state(run_id, node.id, "running")
          runner_pid = self()

          Task.start(fn ->
            result = run_quality_checks(check_commands, checks)
            send(runner_pid, {:quality_check_done, run_id, node.id, result})
          end)
        else
          # No automated commands — fall back to manual gate
          LocalBoard.update_node_state(run_id, node.id, "waiting_gate")
        end

      "loop" ->
        # Loop nodes pass through — they act as markers
        # The actual looping is handled by reject edges going back
        LocalBoard.update_node_state(run_id, node.id, "completed")
        advance_from_node(pipeline_id, run_id, node.id, pipeline)

      "kb_sync" ->
        # KB sync — pause as gate, user decides to "Send to KB" or "Skip"
        LocalBoard.update_node_state(run_id, node.id, "waiting_gate")

      "integration" ->
        LocalBoard.update_node_state(run_id, node.id, "running")

        # Fix I: Execute integration async to avoid blocking the GenServer
        int_type = get_in(node, [:config, "integration_type"]) || "jira"
        action = get_in(node, [:config, "action"]) || ""
        action_config = get_in(node, [:config, "action_config"]) || %{}

        config =
          SymphonyElixir.Integrations.Registry.build_config(int_type, action_config)
          |> Map.put("action", action)

        # A6: Collect predecessor outputs for downstream context
        predecessor_outputs =
          case LocalBoard.get_predecessor_outputs(run_id, node.id) do
            {:ok, outputs} -> outputs
            _ -> %{}
          end

        context = %{
          "node_id" => node.id,
          "pipeline_id" => pipeline_id,
          "run_id" => run_id,
          "predecessor_outputs" => predecessor_outputs
        }

        runner_pid = self()

        Task.start(fn ->
          result = SymphonyElixir.Integrations.Registry.execute(int_type, config, context)
          send(runner_pid, {:integration_done, run_id, node.id, result})
        end)

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
    |> Enum.filter(fn e ->
      e.target_node_id == node_id and e.source_port == "output"
    end)
    |> Enum.map(& &1.source_node_id)
  end

  defp check_issue_completions(pipeline_id, run_id, pipeline, run) do
    # Check issue nodes that are "running" — see if the linked issue has reached Done/Review
    node_issue_ids = run.node_issue_ids || %{}

    pipeline.nodes
    |> Enum.filter(fn n ->
      n.type == "issue" and Map.get(run.node_states, n.id) == "running" and
        (n.issue_id || Map.get(node_issue_ids, n.id))
    end)
    |> Enum.each(fn node ->
      issue_id = node.issue_id || Map.get(node_issue_ids, node.id)

      case LocalBoard.get_issue(issue_id) do
        {:ok, issue} ->
          if MapSet.member?(terminal_states(), String.downcase(issue.state)) do
            # A6: Store issue result as node output
            LocalBoard.set_node_output(run_id, node.id, %{
              "issue_id" => issue_id,
              "identifier" => issue.identifier,
              "state" => issue.state,
              "title" => issue.title
            })

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

  # Fix H: Check per-node timeouts for running/waiting nodes
  defp check_node_timeouts(run_id, run_state) do
    now = System.monotonic_time(:millisecond)
    activated_at = run_state.node_activated_at

    case LocalBoard.get_pipeline_run(run_state.pipeline_id, run_id) do
      {:ok, run} ->
        run_state.pipeline.nodes
        |> Enum.filter(fn node ->
          state = Map.get(run.node_states, node.id)
          state in ["running", "waiting_gate"]
        end)
        |> Enum.each(fn node ->
          case Map.get(activated_at, node.id) do
            nil ->
              :ok

            start_time ->
              # Use per-node timeout from config, or default
              timeout =
                get_in(node, [:config, "timeout_ms"]) || @node_timeout_ms

              if now - start_time > timeout do
                Logger.warning("PipelineRunner: node #{node.id} timed out")
                LocalBoard.update_node_state(run_id, node.id, "failed")
              end
          end
        end)

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

  # Fix E+F: Check if a node has exceeded its max_retries
  defp should_fail_max_retries?(node, run) do
    max_retries = node.loop_max_retries

    if max_retries && max_retries > 0 do
      attempts = Map.get(run.node_attempts, node.id, 0)
      attempts >= max_retries
    else
      # Also check pipeline-level settings for this node type
      false
    end
  end

  # Resolve the issue_id for an issue node. Priority:
  # 1. Static issue_id on the node (classic behavior)
  # 2. Already-created runtime issue from node_issue_ids
  # 3. Auto-create from template config (title/description/labels)
  defp resolve_issue_for_node(pipeline, run_id, node) do
    cond do
      # Static link
      node.issue_id ->
        node.issue_id

      # Already created in a previous activation (e.g. after reject loop)
      true ->
        case LocalBoard.get_pipeline_run(pipeline.id, run_id) do
          {:ok, run} ->
            existing = (run.node_issue_ids || %{}) |> Map.get(node.id)

            if existing do
              existing
            else
              create_issue_from_template(pipeline, run_id, node)
            end

          _ ->
            create_issue_from_template(pipeline, run_id, node)
        end
    end
  end

  defp create_issue_from_template(pipeline, run_id, node) do
    config = node.config || %{}
    title = config["title"] || config[:title]

    if title do
      # Gap #11: Include run short ID to disambiguate concurrent runs
      run_suffix = " [#{String.slice(run_id, 0, 6)}]"
      scoped_title = title <> run_suffix

      attrs = %{
        "title" => scoped_title,
        "description" => config["description"] || config[:description] || "",
        "labels" => config["labels"] || config[:labels] || [],
        "priority" => config["priority"] || config[:priority] || 3,
        "skill_ids" => config["skill_ids"] || config[:skill_ids] || [],
        "product_id" => pipeline.product_id,
        "state" => "Backlog",
        "propose_followups" => false
      }

      case LocalBoard.create_issue(attrs) do
        {:ok, issue} ->
          LocalBoard.set_run_node_issue_id(run_id, node.id, issue.id)

          Logger.info(
            "PipelineRunner: created issue #{issue.identifier} from template " <>
              "for node #{node.id} (#{node.label})"
          )

          issue.id

        {:error, reason} ->
          Logger.error(
            "PipelineRunner: failed to create issue from template for node #{node.id}: " <>
              inspect(reason)
          )

          nil
      end
    else
      nil
    end
  end

  # Fix P: Execute KB sync action when a kb_sync gate is approved
  # When the node has no static content, collects reports from predecessor issues
  # and writes each one as a separate KB note.
  defp execute_kb_sync(node, pipeline, run_id) do
    config = node.config || %{}
    static_content = config["content"] || ""

    if static_content != "" do
      # Static content mode: write a single note from node config
      write_kb_note(node, pipeline, run_id, config)
    else
      # Auto-collect mode: gather reports from predecessor issue nodes
      collect_and_sync_predecessor_reports(node, pipeline, run_id, config)
    end
  end

  defp write_kb_note(node, pipeline, run_id, config) do
    action = config["action"] || "write_note"

    kb_config =
      SymphonyElixir.Integrations.Registry.build_config("knowledge_base", config)
      |> Map.put("action", action)

    context = %{
      "node_id" => node.id,
      "pipeline_id" => pipeline.id,
      "run_id" => run_id,
      "title" => config["title"] || node.label || "Pipeline Note",
      "content" => config["content"] || ""
    }

    case SymphonyElixir.Integrations.Registry.execute("knowledge_base", kb_config, context) do
      {:ok, result} ->
        Logger.info("KB sync completed for node #{node.id}: #{inspect(result)}")

      {:error, reason} ->
        Logger.warning("KB sync failed for node #{node.id}: #{inspect(reason)}")
    end
  end

  defp collect_and_sync_predecessor_reports(node, pipeline, run_id, config) do
    # Find predecessor issue nodes and their created issues
    predecessor_issue_ids = get_predecessor_issue_ids(node, pipeline, run_id)
    Logger.info("KB sync node #{node.id}: predecessor issue IDs = #{inspect(predecessor_issue_ids)}")

    if predecessor_issue_ids == [] do
      Logger.info("KB sync node #{node.id}: no predecessor issues found, skipping")
      :ok
    else
      product_name = resolve_pipeline_product_name(pipeline)
      Logger.info("KB sync node #{node.id}: product_name = #{inspect(product_name)}")

      kb_config =
        SymphonyElixir.Integrations.Registry.build_config("knowledge_base", config)
        |> Map.put("action", "write_note")

      notes_written =
        Enum.flat_map(predecessor_issue_ids, fn issue_id ->
          case LocalBoard.get_issue(issue_id) do
            {:ok, issue} ->
              report_files = SymphonyElixir.Workspace.find_issue_reports(issue)
              Logger.info("KB sync: issue #{issue[:identifier]}: found #{length(report_files)} reports: #{inspect(report_files)}")

              Enum.flat_map(report_files, fn report_path ->
                title = Path.basename(report_path, ".md")
                content = File.read!(report_path)

                context = %{
                  "node_id" => node.id,
                  "pipeline_id" => pipeline.id,
                  "run_id" => run_id,
                  "title" => title,
                  "content" => content,
                  "product_name" => product_name,
                  "tags" => ["symphony", "extraction"]
                }

                case SymphonyElixir.Integrations.Registry.execute(
                       "knowledge_base",
                       kb_config,
                       context
                     ) do
                  {:ok, %{path: path}} ->
                    Logger.info("KB sync: wrote #{path}")
                    [path]

                  {:ok, _} ->
                    [title]

                  {:error, reason} ->
                    Logger.warning("KB sync failed for '#{title}': #{inspect(reason)}")
                    []
                end
              end)

            _ ->
              []
          end
        end)

      Logger.info(
        "KB sync node #{node.id}: wrote #{length(notes_written)} notes for " <>
          "#{length(predecessor_issue_ids)} predecessor issues"
      )
    end
  end

  defp get_predecessor_issue_ids(node, pipeline, run_id) do
    # Get predecessor node IDs from edges
    predecessor_node_ids =
      pipeline.edges
      |> Enum.filter(&(&1.target_node_id == node.id && &1.source_port != "reject"))
      |> Enum.map(& &1.source_node_id)

    # Look up the issue IDs created/linked for those nodes
    case LocalBoard.get_pipeline_run_by_id(run_id) do
      {:ok, run} ->
        node_issue_ids = run.node_issue_ids || %{}

        predecessor_node_ids
        |> Enum.flat_map(fn nid ->
          # Check runtime-created issues first, then static issue_id on node
          case Map.get(node_issue_ids, nid) do
            nil ->
              node_def = Enum.find(pipeline.nodes, &(&1.id == nid))
              if node_def && node_def.issue_id, do: [node_def.issue_id], else: []

            issue_id ->
              [issue_id]
          end
        end)

      _ ->
        []
    end
  end

  defp resolve_pipeline_product_name(pipeline) do
    if pipeline.product_id do
      case LocalBoard.get_product(pipeline.product_id) do
        {:ok, product} -> product.name || "unknown"
        _ -> nil
      end
    else
      nil
    end
  end

  # --- Gap #3+#7: Inject gate feedback into predecessor issues on reject ---

  defp get_gate_feedback(run_id, node_id) do
    case LocalBoard.get_pipeline_run_by_id(run_id) do
      {:ok, run} ->
        run.gate_decisions
        |> Enum.filter(fn d -> d.node_id == node_id end)
        |> Enum.map(fn d -> d.feedback end)
        |> Enum.reject(&(is_nil(&1) or &1 == ""))
        |> Enum.join("\n\n")

      _ ->
        ""
    end
  end

  defp inject_feedback_into_downstream_issues(gate_node_id, pipeline, run_id, feedback) do
    if feedback == "" do
      :ok
    else
      # Find predecessor issue nodes that feed into this gate
      predecessor_issue_ids = collect_predecessor_issue_ids(gate_node_id, pipeline, run_id)

      Enum.each(predecessor_issue_ids, fn issue_id ->
        hint =
          "[Pipeline gate rejected]\n#{feedback}"

        LocalBoard.update_issue(issue_id, %{"rerun_hint" => hint})

        Logger.info("PipelineRunner: injected gate feedback into issue #{issue_id} rerun_hint")
      end)
    end
  end

  defp collect_predecessor_issue_ids(node_id, pipeline, run_id) do
    collect_predecessor_issue_ids(node_id, pipeline, run_id, MapSet.new(), [])
  end

  defp collect_predecessor_issue_ids(node_id, pipeline, run_id, visited, acc) do
    if MapSet.member?(visited, node_id) do
      acc
    else
      visited = MapSet.put(visited, node_id)
      node = Enum.find(pipeline.nodes, &(&1.id == node_id))

      # If this is an issue node, resolve its issue_id
      acc =
        if node && node.type == "issue" do
          issue_id = resolve_predecessor_issue_id(node, run_id)
          if issue_id, do: [issue_id | acc], else: acc
        else
          acc
        end

      # Walk backwards through incoming edges
      predecessors =
        pipeline.edges
        |> Enum.filter(fn e -> e.target_node_id == node_id end)
        |> Enum.map(& &1.source_node_id)

      Enum.reduce(predecessors, acc, fn pred_id, inner_acc ->
        collect_predecessor_issue_ids(pred_id, pipeline, run_id, visited, inner_acc)
      end)
    end
  end

  defp resolve_predecessor_issue_id(node, run_id) do
    if node.issue_id do
      node.issue_id
    else
      case LocalBoard.get_pipeline_run_by_id(run_id) do
        {:ok, run} -> Map.get(run.node_issue_ids || %{}, node.id)
        _ -> nil
      end
    end
  end

  # --- Gap #1: Run automated quality checks ---

  defp run_quality_checks(check_commands, check_names) do
    results =
      check_names
      |> Enum.map(fn name ->
        command = Map.get(check_commands, name, Map.get(check_commands, to_string(name)))

        if command && command != "" do
          case System.cmd("sh", ["-c", command], stderr_to_stdout: true, timeout: 120_000) do
            {_output, 0} -> {name, :pass}
            {_output, _code} -> {name, :fail}
          end
        else
          # No command for this check — treat as manual (pass to let auto-decide work)
          {name, :pass}
        end
      end)

    {:ok, results}
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp store_check_results(run_id, node_id, check_results) do
    # Store as a gate decision with special feedback format
    feedback =
      "Check results: " <>
        Enum.map_join(check_results, ", ", fn {name, status} ->
          "#{name}: #{status}"
        end)

    LocalBoard.record_gate_decision(run_id, node_id, "hold", feedback)
  end

  # --- Gap #4: Auto-approve gate after timeout ---

  defp maybe_auto_approve_gates(run_id, run_state) do
    pipeline = run_state.pipeline
    activated_at = run_state.node_activated_at

    case LocalBoard.get_pipeline_run(run_state.pipeline_id, run_id) do
      {:ok, run} ->
        now = System.monotonic_time(:millisecond)

        pipeline.nodes
        |> Enum.filter(fn node ->
          Map.get(run.node_states, node.id) == "waiting_gate" and
            node.type in ["human_gate", "quality_gate", "kb_sync"]
        end)
        |> Enum.each(fn node ->
          cond do
            # 1. Timeout-based auto-approve
            timeout_auto_approve?(node, activated_at, now) ->
              Logger.info("PipelineRunner: auto-approving gate #{node.id} after timeout")

              LocalBoard.record_gate_decision(
                run_id,
                node.id,
                "approve",
                "Auto-approved after timeout"
              )

              # Execute KB sync BEFORE advancing so data is written before pipeline moves on
              if node.type == "kb_sync" do
                execute_kb_sync(node, run_state.pipeline, run_id)
              end

              advance_from_node(run_state.pipeline_id, run_id, node.id, pipeline)

            # 2. Condition-based: auto-approve when all predecessors completed
            condition_auto_approve?(node, run, pipeline) ->
              Logger.info(
                "PipelineRunner: auto-approving gate #{node.id} — all predecessors completed"
              )

              LocalBoard.record_gate_decision(
                run_id,
                node.id,
                "approve",
                "Auto-approved: all predecessor nodes completed successfully"
              )

              # Execute KB sync BEFORE advancing so data is written before pipeline moves on
              if node.type == "kb_sync" do
                execute_kb_sync(node, pipeline, run_id)
              end

              advance_from_node(run_state.pipeline_id, run_id, node.id, pipeline)

            # 3. Webhook-based: fire webhook and approve on 2xx response
            webhook_auto_approve?(node) ->
              fire_webhook_auto_approve(run_id, node, run_state, pipeline)

            true ->
              :ok
          end
        end)

      {:error, _} ->
        :ok
    end
  end

  defp timeout_auto_approve?(node, activated_at, now) do
    auto_timeout = get_in(node, [:config, "auto_approve_timeout_ms"])

    if auto_timeout && auto_timeout > 0 do
      start_time = Map.get(activated_at, node.id)
      start_time && now - start_time > auto_timeout
    else
      false
    end
  end

  defp condition_auto_approve?(node, run, pipeline) do
    auto_condition = get_in(node, [:config, "auto_approve_condition"])

    if auto_condition == "all_predecessors_completed" do
      predecessor_ids =
        pipeline.edges
        |> Enum.filter(&(&1.target_node_id == node.id && &1.source_port != "reject"))
        |> Enum.map(& &1.source_node_id)

      Enum.all?(predecessor_ids, fn pid ->
        Map.get(run.node_states, pid) == "completed"
      end)
    else
      false
    end
  end

  defp webhook_auto_approve?(node) do
    url = get_in(node, [:config, "auto_approve_webhook_url"])
    url && url != ""
  end

  defp fire_webhook_auto_approve(run_id, node, run_state, _pipeline) do
    url = get_in(node, [:config, "auto_approve_webhook_url"])
    pipeline_id = run_state.pipeline_id
    node_id = node.id

    Task.start(fn ->
      body =
        Jason.encode!(%{
          run_id: run_id,
          pipeline_id: pipeline_id,
          node_id: node_id,
          node_type: node.type,
          label: node.label
        })

      case :httpc.request(
             :post,
             {String.to_charlist(url), [], ~c"application/json", body},
             [{:timeout, 10_000}],
             []
           ) do
        {:ok, {{_, status, _}, _, _}} when status >= 200 and status < 300 ->
          Logger.info("PipelineRunner: webhook approved gate #{node_id} (HTTP #{status})")

          LocalBoard.record_gate_decision(
            run_id,
            node_id,
            "approve",
            "Auto-approved via webhook (HTTP #{status})"
          )

          GenServer.cast(__MODULE__, {:gate_decided, run_id, node_id, "approve"})

        {:ok, {{_, status, _}, _, _}} ->
          Logger.info("PipelineRunner: webhook rejected gate #{node_id} (HTTP #{status})")

        {:error, reason} ->
          Logger.warning("PipelineRunner: webhook failed for gate #{node_id}: #{inspect(reason)}")
      end
    end)
  end

  # --- Gap #10: Integration node retry with backoff ---

  defp maybe_retry_failed_integrations(pipeline_id, run_id, run_state) do
    pipeline = run_state.pipeline

    case LocalBoard.get_pipeline_run(pipeline_id, run_id) do
      {:ok, run} ->
        pipeline.nodes
        |> Enum.filter(fn node ->
          node.type == "integration" and
            Map.get(run.node_states, node.id) == "failed"
        end)
        |> Enum.each(fn node ->
          max_retries = get_in(node, [:config, "max_retries"]) || 0
          attempts = Map.get(run.node_attempts, node.id, 0)

          if max_retries > 0 and attempts < max_retries do
            # Exponential backoff: 5s * 2^(attempt-1), max 5 min
            backoff = min((5_000 * :math.pow(2, attempts - 1)) |> round(), 300_000)
            activated_at = Map.get(run_state.node_activated_at, node.id, 0)
            now = System.monotonic_time(:millisecond)

            if now - activated_at > backoff do
              Logger.info(
                "PipelineRunner: retrying integration #{node.id} " <>
                  "(attempt #{attempts + 1}/#{max_retries})"
              )

              # Reset to pending so activate_node will re-run it
              LocalBoard.update_node_state(run_id, node.id, "pending")
              activate_node(pipeline_id, run_id, node, pipeline)
            end
          end
        end)

      {:error, _} ->
        :ok
    end
  end

  defp terminal_states do
    # States considered "done" for issue nodes. Uses lowercased matching.
    MapSet.new(["done", "review", "archived", "cancelled"])
  end
end

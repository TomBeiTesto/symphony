defmodule SymphonyElixir.Orchestrator do
  @moduledoc """
  Main orchestrator GenServer. Owns the poll tick, dispatch, reconciliation,
  and in-memory runtime state.

  See SPEC Sections 7-8.
  """

  use GenServer

  require Logger

  alias SymphonyElixir.{Config, Issue, Prompt, Workspace}
  alias SymphonyElixir.AppServer.Client, as: AppServerClient
  alias SymphonyElixir.AppServer.ClaudeAdapter
  alias SymphonyElixir.Orchestrator.{Dispatch, Reconciliation, Retry, State}

  @type init_opts :: [
          config: Config.t(),
          prompt_template: String.t()
        ]

  # --- Client API ---

  @spec start_link(init_opts()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec get_state() :: State.t()
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @spec get_snapshot() :: map()
  def get_snapshot do
    GenServer.call(__MODULE__, :get_snapshot)
  end

  @spec get_issue_detail(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_issue_detail(identifier) do
    GenServer.call(__MODULE__, {:get_issue_detail, identifier})
  end

  @spec request_refresh() :: :ok
  def request_refresh do
    GenServer.cast(__MODULE__, :request_refresh)
  end

  @spec reload_config(Config.t(), String.t()) :: :ok
  def reload_config(config, prompt_template) do
    GenServer.cast(__MODULE__, {:reload_config, config, prompt_template})
  end

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    config = Keyword.fetch!(opts, :config)
    prompt_template = Keyword.fetch!(opts, :prompt_template)

    state = %State{
      config: config,
      prompt_template: prompt_template
    }

    Logger.info("Orchestrator starting, performing initial cleanup...")

    state = startup_terminal_cleanup(state)

    # Schedule immediate first tick
    send(self(), :tick)

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:get_snapshot, _from, state) do
    snapshot = build_snapshot(state)
    {:reply, snapshot, state}
  end

  def handle_call({:get_issue_detail, identifier}, _from, state) do
    result = find_issue_detail(state, identifier)
    {:reply, result, state}
  end

  @impl true
  def handle_cast(:request_refresh, state) do
    Logger.info("Manual refresh requested")
    send(self(), :tick)
    {:noreply, state}
  end

  def handle_cast({:reload_config, config, prompt_template}, state) do
    Logger.info("Configuration reloaded")
    {:noreply, %{state | config: config, prompt_template: prompt_template}}
  end

  @impl true
  def handle_info(:tick, state) do
    state =
      if state.token_budget_exceeded do
        Logger.debug("Skipping tick — token budget exceeded")
        state
      else
        run_tick(state)
      end

    # Schedule next tick (keep scheduling so it resumes if budget is reset)
    interval = state.config.poll_interval_ms
    Process.send_after(self(), :tick, interval)

    {:noreply, state}
  end

  def handle_info({:retry_timer, _due_at}, state) do
    state = process_due_retries(state)
    {:noreply, state}
  end

  def handle_info({:worker_done, issue_id, result}, state) do
    state = handle_worker_result(state, issue_id, result)
    {:noreply, state}
  end

  def handle_info({:agent_event, issue_id, event}, state) do
    state = handle_agent_event(state, issue_id, event)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # --- Tick Logic ---

  defp run_tick(state) do
    config = state.config
    tracker_client = tracker_client_module(config)

    # Part 0: Auto-archive Done issues older than 7 days
    if config.tracker_kind == "local" do
      auto_archive_done_issues()
      auto_promote_backlog_to_todo()
    end

    # Part 1: Reconcile running issues
    state = reconcile_running(state, config, tracker_client)

    # Part 2: Validate config
    case Config.validate_dispatch(config) do
      :ok ->
        # Part 3: Fetch candidates
        case tracker_client.fetch_candidate_issues(config) do
          {:ok, candidates} ->
            # Part 4: Sort and dispatch
            dispatchable = Dispatch.select_dispatchable(config, state, candidates)
            dispatch_loop(state, config, dispatchable)

          {:error, reason} ->
            Logger.error("Failed to fetch candidates: #{inspect(reason)}")
            state
        end

      {:error, reasons} ->
        Logger.error("Config validation failed, skipping dispatch: #{inspect(reasons)}")
        state
    end
  end

  defp dispatch_loop(state, _config, []), do: state

  defp dispatch_loop(state, config, [issue | rest]) do
    slots = State.available_slots(state, config.max_concurrent_agents)

    if slots <= 0 do
      state
    else
      state = dispatch_issue(state, config, issue)
      dispatch_loop(state, config, rest)
    end
  end

  defp dispatch_issue(state, config, %Issue{} = issue) do
    Logger.info("Dispatching issue=#{issue.identifier} state=#{issue.state}")

    orchestrator_pid = self()
    issue_id = issue.id
    identifier = issue.identifier

    # Move to "In Progress" on local board
    if config.tracker_kind == "local" do
      SymphonyElixir.LocalBoard.move_issue(issue_id, "In Progress")
    end

    # Claim the issue
    state = %{state | claimed: MapSet.put(state.claimed, issue_id)}

    # Add to running
    state = State.add_running(state, issue_id, State.new_running_entry(issue, nil))

    # Spawn worker task
    Task.start(fn ->
      result = run_worker(config, state.prompt_template, issue, orchestrator_pid)
      send(orchestrator_pid, {:worker_done, issue_id, result})
    end)

    Logger.metadata(issue_id: issue_id, issue_identifier: identifier)
    state
  end

  # --- Worker ---

  defp run_worker(config, prompt_template, issue, orchestrator_pid) do
    with {:ok, workspace_info} <- Workspace.ensure_workspace(config, issue),
         workspace_path = resolve_project_workspace(config, issue, workspace_info.path),
         :ok <- run_before_run_hook(config, workspace_path),
         {:ok, prompt} <- render_prompt(prompt_template, issue, nil),
         :ok <- validate_cwd(workspace_path) do
      callback = fn event ->
        send(orchestrator_pid, {:agent_event, issue.id, event})
        :ok
      end

      client = agent_client_module()

      case client.start_session(config, workspace_path, prompt, callback) do
        {:ok, session} ->
          result = run_turn_loop(config, prompt_template, issue, session, 1)

          # after_run hook (failure ignored per spec)
          Workspace.run_hook(config, :after_run, workspace_path)

          result

        {:error, reason} ->
          {:error, {:startup_failed, reason}}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_turn_loop(_config, _prompt_template, _issue, session, turn_count) do
    client = agent_client_module()

    case client.stream_turn(session) do
      {:ok, :completed, session} ->
        # Claude --print is single-shot: one turn completes the entire task.
        # No continuation needed — the agent finishes when the process exits 0.
        client.stop(session)
        {:ok, {:completed_after_turns, turn_count, nil}}

      {:ok, :failed, session} ->
        client.stop(session)
        {:error, {:turn_failed, turn_count}}

      {:ok, :cancelled, session} ->
        client.stop(session)
        {:error, {:turn_cancelled, turn_count}}

      {:error, reason} ->
        client.stop(session)
        {:error, {reason, turn_count}}
    end
  end

  # If the issue belongs to a product, use the first project's path as workspace.
  # If the issue belongs to a project, use that project's path.
  defp resolve_project_workspace(
         %Config{tracker_kind: "local"},
         %Issue{product_id: prod_id},
         fallback
       )
       when is_binary(prod_id) and prod_id != "" do
    case resolve_product_project_paths(prod_id) do
      [first_path | _] ->
        Logger.info("Using product's first project path as workspace: #{first_path}")
        first_path

      [] ->
        fallback
    end
  end

  defp resolve_project_workspace(
         %Config{tracker_kind: "local"},
         %Issue{project_id: pid},
         fallback
       )
       when is_binary(pid) and pid != "" do
    case SymphonyElixir.LocalBoard.get_project(pid) do
      {:ok, %{path: path}} when is_binary(path) and path != "" ->
        if File.dir?(path) do
          Logger.info("Using project path as workspace: #{path}")
          path
        else
          Logger.warning("Project path #{path} does not exist, using default workspace")
          fallback
        end

      _ ->
        fallback
    end
  end

  defp resolve_project_workspace(_config, _issue, fallback), do: fallback

  defp resolve_product_project_paths(product_id) do
    case SymphonyElixir.LocalBoard.get_product(product_id) do
      {:ok, product} ->
        (product.project_ids || [])
        |> Enum.map(fn pid ->
          case SymphonyElixir.LocalBoard.get_project(pid) do
            {:ok, %{path: path}} when is_binary(path) and path != "" -> path
            _ -> nil
          end
        end)
        |> Enum.filter(&(&1 != nil && File.dir?(&1)))

      _ ->
        []
    end
  end

  defp run_before_run_hook(config, workspace_path) do
    case Workspace.run_hook(config, :before_run, workspace_path) do
      :ok -> :ok
      {:error, reason} -> {:error, {:hook_failed, :before_run, reason}}
    end
  end

  defp agent_client_module do
    provider =
      try do
        SymphonyElixir.Settings.get("agent_provider")
      catch
        :exit, _ -> nil
      end

    case provider do
      "claude-code" -> ClaudeAdapter
      "codex" -> AppServerClient
      _ -> ClaudeAdapter
    end
  end

  defp render_prompt(template, issue, attempt) do
    case Prompt.render(template, issue, attempt) do
      {:ok, rendered} -> {:ok, rendered}
      {:error, reason} -> {:error, {:prompt_render_failed, reason}}
    end
  end

  defp validate_cwd(workspace_path) do
    if File.dir?(workspace_path) do
      :ok
    else
      {:error, :invalid_workspace_cwd}
    end
  end

  # --- Worker Result Handling ---

  defp handle_worker_result(state, issue_id, result) do
    running_entry = Map.get(state.running, issue_id)
    identifier = running_entry_identifier(running_entry)

    state = preserve_completed_run(state, issue_id, running_entry, identifier)
    state = State.remove_running(state, issue_id)

    case result do
      {:ok, _} ->
        handle_worker_success(state, issue_id, identifier, running_entry, result)

      {:error, reason} ->
        handle_worker_failure(state, issue_id, identifier, reason)
    end
  end

  defp running_entry_identifier(nil), do: "unknown"
  defp running_entry_identifier(entry), do: entry[:identifier] || "unknown"

  defp preserve_completed_run(state, _issue_id, nil, identifier) do
    Logger.warning("No running entry to preserve for #{identifier}")
    state
  end

  defp preserve_completed_run(state, issue_id, running_entry, identifier) do
    event_count = length(running_entry[:event_log] || [])
    tokens = running_entry[:tokens]

    Logger.info(
      "Preserving completed run for #{identifier}: #{event_count} events, tokens=#{inspect(tokens)}"
    )

    %{state | completed_runs: Map.put(state.completed_runs, issue_id, running_entry)}
  end

  defp handle_worker_success(state, issue_id, identifier, running_entry, result) do
    Logger.info("Worker completed issue=#{identifier} result=#{inspect(result)}")

    if state.config.tracker_kind == "local" and running_entry do
      persist_agent_run(issue_id, running_entry)
    end

    if state.config.tracker_kind == "local" do
      SymphonyElixir.LocalBoard.move_issue(issue_id, resolve_done_state(issue_id))
    end

    %{state | completed: MapSet.put(state.completed, issue_id)}
  end

  defp resolve_done_state(issue_id) do
    case SymphonyElixir.LocalBoard.get_issue(issue_id) do
      {:ok, issue} ->
        follow_ups = (issue[:agent_run] && issue[:agent_run]["follow_ups"]) || []
        if Enum.any?(follow_ups, &(&1["status"] == "proposed")), do: "Review", else: "Done"

      _ ->
        "Done"
    end
  end

  defp handle_worker_failure(state, issue_id, identifier, reason) do
    Logger.error("Worker failed issue=#{identifier} error=#{inspect(reason)}")

    if token_exhaustion_error?(reason) do
      handle_token_exhaustion(state, issue_id, identifier, reason)
    else
      if state.config.tracker_kind == "local" do
        SymphonyElixir.LocalBoard.move_issue(issue_id, "Todo")
      end

      attempt =
        case Map.get(state.retry_attempts, issue_id) do
          %{attempt: a} -> a + 1
          _ -> 1
        end

      Retry.schedule_failure_retry(
        state,
        state.config,
        issue_id,
        identifier,
        attempt,
        inspect(reason)
      )
    end
  end

  # Detect if an error indicates the LLM token quota/budget is exhausted
  defp token_exhaustion_error?(reason) do
    msg = inspect(reason) |> String.downcase()

    Enum.any?(
      ["rate limit", "rate_limit", "ratelimit", "quota", "token limit", "budget exceeded",
       "too many requests", "429", "resource_exhausted", "tokens_exceeded",
       "billing", "usage limit", "plan limit"],
      &String.contains?(msg, &1)
    )
  end

  defp handle_token_exhaustion(state, issue_id, identifier, reason) do
    Logger.warning(
      "Token exhaustion detected for #{identifier}: #{inspect(reason)}. " <>
        "Deactivating auto-polling and moving all in-progress issues to Backlog."
    )

    # Move this failed issue to Backlog
    if state.config.tracker_kind == "local" do
      SymphonyElixir.LocalBoard.move_issue(issue_id, "Backlog")
    end

    # Move all other running issues to Backlog
    if state.config.tracker_kind == "local" do
      for {other_id, entry} <- state.running, other_id != issue_id do
        case SymphonyElixir.LocalBoard.move_issue(other_id, "Backlog") do
          :ok ->
            Logger.info("Moved issue #{entry.identifier} to Backlog (token exhaustion)")

          {:error, move_reason} ->
            Logger.warning(
              "Failed to move #{entry.identifier} to Backlog: #{inspect(move_reason)}"
            )
        end
      end
    end

    %{state | token_budget_exceeded: true}
  end

  # --- Agent Events ---

  @max_event_log 100

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp handle_agent_event(state, issue_id, event) do
    now_mono = System.monotonic_time(:millisecond)

    case Map.get(state.running, issue_id) do
      nil ->
        Logger.debug("Agent event for non-running issue #{issue_id}: #{event[:event]}")
        state

      entry ->
        entry =
          entry
          |> Map.put(:last_event, event[:event])
          |> Map.put(:last_event_at, event[:timestamp])
          |> Map.put(:last_event_at_mono, now_mono)
          |> Map.put(:last_message, get_in(event, [:payload, :message]) || "")

        # Append to event log (keep last N events)
        log_entry = %{
          event: event[:event],
          timestamp: event[:timestamp],
          message: get_in(event, [:payload, :message]),
          tool: get_in(event, [:payload, :tool]),
          detail: get_in(event, [:payload, :detail]),
          line: get_in(event, [:payload, :line])
        }

        event_log = (entry[:event_log] || []) ++ [log_entry]

        event_log =
          if length(event_log) > @max_event_log,
            do: Enum.drop(event_log, length(event_log) - @max_event_log),
            else: event_log

        entry = Map.put(entry, :event_log, event_log)

        # Accumulate agent result text (agents may emit multiple result messages)
        entry =
          case get_in(event, [:payload, :result]) do
            result when is_binary(result) and result != "" ->
              existing = entry[:result_text] || ""
              separator = if existing != "", do: "\n\n---\n\n", else: ""
              Map.put(entry, :result_text, existing <> separator <> result)

            _ ->
              entry
          end

        # Update token usage (per-issue and aggregate)
        {entry, state} =
          case get_in(event, [:payload]) do
            %{input_tokens: inp, output_tokens: out, total_tokens: tot} = tokens ->
              updated_entry = Map.put(entry, :tokens, tokens)
              # Update aggregate totals with the delta from previous tokens
              prev = entry[:tokens] || %{input_tokens: 0, output_tokens: 0, total_tokens: 0}
              delta_in = inp - (prev[:input_tokens] || 0)
              delta_out = out - (prev[:output_tokens] || 0)
              delta_tot = tot - (prev[:total_tokens] || 0)

              totals = state.agent_totals

              updated_totals = %{
                totals
                | input_tokens: totals.input_tokens + max(delta_in, 0),
                  output_tokens: totals.output_tokens + max(delta_out, 0),
                  total_tokens: totals.total_tokens + max(delta_tot, 0)
              }

              {updated_entry, %{state | agent_totals: updated_totals}}

            _ ->
              {entry, state}
          end

        running = Map.put(state.running, issue_id, entry)

        # Update rate limits if present
        state =
          case get_in(event, [:payload]) do
            %{rate_limits: rl} when is_map(rl) -> %{state | rate_limits: rl}
            _ -> state
          end

        state = %{state | running: running}
        state
    end
  end

  # --- Reconciliation ---

  defp reconcile_running(state, config, tracker_client) do
    # Part A: Stall detection
    stalled_ids = Reconciliation.detect_stalls(state, config)

    state =
      Enum.reduce(stalled_ids, state, fn issue_id, s ->
        Logger.warning("Stall detected for issue_id=#{issue_id}")
        entry = Map.get(s.running, issue_id, %{})
        identifier = entry[:identifier] || ""
        s = State.remove_running(s, issue_id)

        attempt =
          case Map.get(s.retry_attempts, issue_id) do
            %{attempt: a} -> a + 1
            _ -> 1
          end

        Retry.schedule_failure_retry(s, config, issue_id, identifier, attempt, "stall_timeout")
      end)

    # Part B: Tracker state refresh
    running_ids = Map.keys(state.running)

    if running_ids == [] do
      state
    else
      case tracker_client.fetch_issue_states_by_ids(config, running_ids) do
        {:ok, fresh_issues} ->
          {actions, state} = Reconciliation.reconcile_tracker_states(state, config, fresh_issues)
          apply_reconciliation_actions(state, config, actions)

        {:error, reason} ->
          Logger.error("State refresh failed: #{inspect(reason)}, keeping workers running")
          state
      end
    end
  end

  defp apply_reconciliation_actions(state, config, actions) do
    Enum.reduce(actions, state, fn action, s ->
      case action do
        {:stop_terminal, issue_id, identifier} ->
          Logger.info("Terminating worker issue=#{identifier} (terminal state)")
          s = State.remove_running(s, issue_id)
          s = State.release_claim(s, issue_id)
          workspace_key = Issue.sanitize_identifier(identifier)
          Workspace.remove_workspace(config, workspace_key)
          s

        {:stop_inactive, issue_id, identifier} ->
          Logger.info("Terminating worker issue=#{identifier} (no longer active)")
          s = State.remove_running(s, issue_id)
          State.release_claim(s, issue_id)

        {:update, _issue_id, _fresh_issue} ->
          # Already updated in reconcile_tracker_states
          s
      end
    end)
  end

  # --- Retry Processing ---

  defp process_due_retries(state) do
    due = Retry.due_retries(state)

    if due == [] do
      state
    else
      tracker_client = tracker_client_module(state.config)

      case tracker_client.fetch_candidate_issues(state.config) do
        {:ok, candidates} ->
          Enum.reduce(due, state, fn entry, s ->
            case Retry.handle_retry(s, s.config, entry.issue_id, candidates) do
              {{:dispatch, issue}, s} ->
                dispatch_issue(s, s.config, issue)

              {{:requeue, reason}, s} ->
                Logger.info("Retry requeued issue=#{entry.identifier}: #{reason}")
                s

              {:released, s} ->
                Logger.info("Retry released claim issue=#{entry.identifier}")
                s
            end
          end)

        {:error, reason} ->
          Logger.error("Retry candidate fetch failed: #{inspect(reason)}")
          state
      end
    end
  end

  # --- Startup Cleanup ---

  defp startup_terminal_cleanup(state) do
    config = state.config
    tracker_client = tracker_client_module(config)
    terminal_states = config.terminal_states

    case tracker_client.fetch_issues_by_states(config, terminal_states) do
      {:ok, terminal_issues} ->
        Enum.each(terminal_issues, fn issue ->
          workspace_key = Issue.workspace_key(issue)
          Logger.info("Cleaning up terminal workspace: #{workspace_key}")
          Workspace.remove_workspace(config, workspace_key)
        end)

        state

      {:error, reason} ->
        Logger.warning("Startup terminal cleanup failed: #{inspect(reason)}")
        state
    end
  end

  # --- Snapshot ---

  defp build_snapshot(state) do
    now = DateTime.utc_now()
    totals = State.live_seconds_running(state)

    %{
      generated_at: now,
      counts: %{
        running: State.running_count(state),
        retrying: map_size(state.retry_attempts)
      },
      running:
        Enum.map(state.running, fn {_id, entry} ->
          %{
            issue_id: entry[:issue_id],
            issue_identifier: entry[:identifier],
            state: entry[:issue_state],
            session_id: entry[:session_id],
            turn_count: entry[:turn_count] || 0,
            last_event: entry[:last_event],
            last_message: entry[:last_message] || "",
            started_at: entry[:started_at],
            last_event_at: entry[:last_event_at],
            tokens: entry[:tokens] || %{input_tokens: 0, output_tokens: 0, total_tokens: 0}
          }
        end),
      retrying:
        Enum.map(state.retry_attempts, fn {_id, entry} ->
          %{
            issue_id: entry.issue_id,
            issue_identifier: entry.identifier,
            attempt: entry.attempt,
            due_at: monotonic_to_datetime(entry.due_at_ms),
            error: entry.error
          }
        end),
      agent_totals: %{
        input_tokens: state.agent_totals.input_tokens,
        output_tokens: state.agent_totals.output_tokens,
        total_tokens: state.agent_totals.total_tokens,
        seconds_running: totals
      },
      rate_limits: state.rate_limits,
      token_budget_exceeded: state.token_budget_exceeded
    }
  end

  defp find_issue_detail(state, identifier) do
    # Check running
    running_entry =
      Enum.find(state.running, fn {_id, entry} ->
        entry[:identifier] == identifier
      end)

    # Check retrying
    retry_entry =
      Enum.find(state.retry_attempts, fn {_id, entry} ->
        entry.identifier == identifier
      end)

    # Check completed runs (preserved after worker finishes)
    completed_entry =
      Enum.find(state.completed_runs, fn {_id, entry} ->
        entry[:identifier] == identifier
      end)

    cond do
      running_entry != nil ->
        {_id, entry} = running_entry
        {:ok, build_issue_detail(identifier, entry, nil, "running")}

      retry_entry != nil ->
        {_id, entry} = retry_entry
        {:ok, build_issue_detail(identifier, nil, entry, "retrying")}

      completed_entry != nil ->
        {_id, entry} = completed_entry
        {:ok, build_issue_detail(identifier, entry, nil, "completed")}

      true ->
        {:error, :not_found}
    end
  end

  defp build_issue_detail(identifier, running_entry, retry_entry, status) do
    %{
      issue_identifier: identifier,
      issue_id:
        (running_entry && running_entry[:issue_id]) || (retry_entry && retry_entry.issue_id),
      status: status,
      workspace: %{
        path: nil
      },
      running:
        if running_entry do
          %{
            session_id: running_entry[:session_id],
            turn_count: running_entry[:turn_count] || 0,
            state: running_entry[:issue_state],
            started_at: running_entry[:started_at],
            last_event: running_entry[:last_event],
            last_message: running_entry[:last_message] || "",
            last_event_at: running_entry[:last_event_at],
            tokens:
              running_entry[:tokens] || %{input_tokens: 0, output_tokens: 0, total_tokens: 0}
          }
        else
          nil
        end,
      retry:
        if retry_entry do
          %{
            attempt: retry_entry.attempt,
            due_at: monotonic_to_datetime(retry_entry.due_at_ms),
            error: retry_entry.error
          }
        else
          nil
        end,
      event_log: (running_entry && running_entry[:event_log]) || [],
      result_text: (running_entry && running_entry[:result_text]) || nil,
      follow_ups: load_follow_ups(running_entry),
      last_error: nil,
      tracked: %{}
    }
  end

  @archive_after_days 1

  defp auto_archive_done_issues do
    case SymphonyElixir.LocalBoard.list_issues_by_states(["Done"]) do
      issues when is_list(issues) ->
        cutoff = DateTime.utc_now() |> DateTime.add(-@archive_after_days * 86_400, :second)

        Enum.each(issues, fn issue ->
          completed_at = get_completed_at(issue)

          if completed_at && DateTime.compare(completed_at, cutoff) == :lt do
            Logger.info("Auto-archiving #{issue.identifier} (completed #{completed_at})")
            SymphonyElixir.LocalBoard.move_issue(issue.id, "Archived")
          end
        end)

      _ ->
        :ok
    end
  end

  defp auto_promote_backlog_to_todo do
    if SymphonyElixir.Settings.get("auto_add_enabled") == "true" do
      max = parse_max_todo(SymphonyElixir.Settings.get("max_todo_parallel"))

      active_issues = SymphonyElixir.LocalBoard.list_issues_by_states(["Todo", "In Progress"])
      backlog_issues = SymphonyElixir.LocalBoard.list_issues_by_states(["Backlog"])

      # Group by project_id (nil = unassigned); count Todo + In Progress together
      todo_by_project = Enum.group_by(active_issues, & &1.project_id)
      backlog_by_project = Enum.group_by(backlog_issues, & &1.project_id)

      Enum.each(backlog_by_project, fn {project_id, candidates} ->
        current_count = length(Map.get(todo_by_project, project_id, []))
        slots = max - current_count

        if slots > 0 do
          candidates
          |> Enum.sort_by(& &1.priority)
          |> Enum.take(slots)
          |> Enum.each(fn issue ->
            Logger.info("Auto-promoting #{issue.identifier} from Backlog to Todo")
            SymphonyElixir.LocalBoard.move_issue(issue.id, "Todo")
          end)
        end
      end)
    end
  end

  defp parse_max_todo(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> max(1, min(n, 3))
      :error -> 3
    end
  end

  defp parse_max_todo(_), do: 3

  defp get_completed_at(issue) do
    # Try agent_run completed_at, then fall back to updated_at
    dt_str =
      (issue[:agent_run] && issue[:agent_run]["completed_at"]) ||
        issue[:updated_at] || issue.updated_at

    case dt_str do
      %DateTime{} = dt -> dt
      str when is_binary(str) -> parse_datetime(str)
      _ -> nil
    end
  end

  defp parse_datetime(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp load_follow_ups(nil), do: []

  defp load_follow_ups(running_entry) do
    issue_id = running_entry[:issue_id]

    if issue_id do
      case SymphonyElixir.LocalBoard.get_issue(issue_id) do
        {:ok, issue} ->
          (issue[:agent_run] && issue[:agent_run]["follow_ups"]) || []

        _ ->
          []
      end
    else
      []
    end
  end

  # Convert monotonic time (ms) to a wall-clock DateTime.
  # Monotonic time is relative to an arbitrary anchor, so we compute the
  # delta from "now" and add it to the current UTC wall clock.
  defp monotonic_to_datetime(mono_ms) do
    delta_ms = mono_ms - System.monotonic_time(:millisecond)
    DateTime.add(DateTime.utc_now(), delta_ms, :millisecond)
  end

  defp persist_agent_run(issue_id, running_entry) do
    event_log = Enum.map(running_entry[:event_log] || [], &event_to_json/1)
    tokens = normalize_tokens(running_entry[:tokens])

    follow_ups =
      case SymphonyElixir.LocalBoard.get_issue(issue_id) do
        {:ok, issue} when issue.propose_followups != false ->
          extract_follow_ups(running_entry[:result_text])

        _ ->
          []
      end

    run_data = %{
      "event_log" => event_log,
      "result_text" => running_entry[:result_text],
      "tokens" => tokens,
      "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "follow_ups" => follow_ups
    }

    try do
      SymphonyElixir.LocalBoard.save_agent_run(issue_id, run_data)
    catch
      kind, reason ->
        Logger.warning("Failed to persist agent run: #{kind} #{inspect(reason)}")
    end
  end

  defp extract_follow_ups(result_text) when is_binary(result_text) do
    case Regex.run(~r/```follow-ups\s*\n([\s\S]*?)```/, result_text) do
      [_, json_str] ->
        case Jason.decode(json_str) do
          {:ok, list} when is_list(list) ->
            Enum.map(list, fn item ->
              %{
                "id" => "fu_" <> Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false),
                "title" => item["title"] || "Untitled follow-up",
                "description" => item["description"],
                "labels" => item["labels"] || [],
                "priority" => item["priority"] || 3,
                "status" => "proposed"
              }
            end)

          _ ->
            []
        end

      nil ->
        []
    end
  end

  defp extract_follow_ups(_), do: []

  defp event_to_json(ev) do
    %{
      "event" => to_string(ev[:event] || "unknown"),
      "timestamp" => to_string(ev[:timestamp] || ""),
      "message" => ev[:message],
      "tool" => ev[:tool],
      "detail" => ev[:detail],
      "line" => ev[:line]
    }
  end

  defp normalize_tokens(nil),
    do: %{"input_tokens" => 0, "output_tokens" => 0, "total_tokens" => 0}

  defp normalize_tokens(t) do
    %{
      "input_tokens" => t[:input_tokens] || 0,
      "output_tokens" => t[:output_tokens] || 0,
      "total_tokens" => t[:total_tokens] || 0
    }
  end

  defp tracker_client_module(config) do
    case Application.get_env(:symphony_elixir, :tracker_client) do
      nil ->
        case config do
          %Config{tracker_kind: "local"} -> SymphonyElixir.LocalBoard.Client
          %Config{tracker_kind: "gitlab"} -> SymphonyElixir.GitLab.Client
        end

      module ->
        module
    end
  end
end

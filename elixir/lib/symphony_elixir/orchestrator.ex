defmodule SymphonyElixir.Orchestrator do
  @moduledoc """
  Main orchestrator GenServer. Owns the poll tick, dispatch, reconciliation,
  and in-memory runtime state.

  See SPEC Sections 7-8.
  """

  use GenServer

  require Logger

  alias SymphonyElixir.{Config, Issue, Workspace}

  alias SymphonyElixir.Orchestrator.{
    Dispatch,
    Events,
    Lifecycle,
    Maintenance,
    Reconciliation,
    Retry,
    Snapshot,
    State,
    Worker
  }

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

  @doc "Approve a plan and dispatch the execution phase."
  @spec approve_plan(String.t()) :: :ok | {:error, term()}
  def approve_plan(issue_id) do
    GenServer.call(__MODULE__, {:approve_plan, issue_id})
  end

  @doc "Reject a plan and re-dispatch the planning phase."
  @spec reject_plan(String.t(), String.t() | nil) :: :ok | {:error, term()}
  def reject_plan(issue_id, feedback \\ nil) do
    GenServer.call(__MODULE__, {:reject_plan, issue_id, feedback})
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
    snapshot = Snapshot.build_snapshot(state)
    {:reply, snapshot, state}
  end

  def handle_call({:get_issue_detail, identifier}, _from, state) do
    result = Snapshot.find_issue_detail(state, identifier)
    {:reply, result, state}
  end

  def handle_call({:approve_plan, issue_id}, _from, state) do
    case SymphonyElixir.LocalBoard.get_issue(issue_id) do
      {:ok, issue} when issue.plan_status == "plan_review" ->
        # Update plan_status to approved — the plan_text stays as-is
        SymphonyElixir.LocalBoard.update_issue(issue_id, %{"plan_status" => "approved"})

        # Clear completed state so the issue is eligible for dispatch
        state = %{state | completed: MapSet.delete(state.completed, issue_id)}
        state = %{state | claimed: MapSet.delete(state.claimed, issue_id)}

        # Clear the old agent_run so the execution phase starts fresh
        SymphonyElixir.LocalBoard.save_agent_run(issue_id, nil)

        # Trigger a tick to pick it up
        send(self(), :tick)
        {:reply, :ok, state}

      {:ok, _} ->
        {:reply, {:error, :not_in_plan_review}, state}

      {:error, _} = err ->
        {:reply, err, state}
    end
  end

  def handle_call({:reject_plan, issue_id, feedback}, _from, state) do
    case SymphonyElixir.LocalBoard.get_issue(issue_id) do
      {:ok, issue} when issue.plan_status == "plan_review" ->
        # Reset plan_status back to planning, clear old plan
        new_desc =
          if feedback do
            (issue.description || "") <>
              "\n\n---\n**Plan Feedback:** #{feedback}\n"
          else
            issue.description
          end

        SymphonyElixir.LocalBoard.update_issue(issue_id, %{
          "plan_status" => "planning",
          "plan_text" => nil,
          "description" => new_desc
        })

        # Clear completed/claimed so it can be re-dispatched
        state = %{state | completed: MapSet.delete(state.completed, issue_id)}
        state = %{state | claimed: MapSet.delete(state.claimed, issue_id)}

        # Clear old agent_run
        SymphonyElixir.LocalBoard.save_agent_run(issue_id, nil)

        # Trigger dispatch
        send(self(), :tick)
        {:reply, :ok, state}

      {:ok, _} ->
        {:reply, {:error, :not_in_plan_review}, state}

      {:error, _} = err ->
        {:reply, err, state}
    end
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
    state = Lifecycle.handle_worker_result(state, issue_id, result)
    {:noreply, state}
  end

  def handle_info({:agent_event, issue_id, event}, state) do
    state = Events.handle_agent_event(state, issue_id, event)
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
      Maintenance.auto_archive_done_issues()
      Maintenance.auto_promote_backlog_to_todo()
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
      state = Worker.dispatch_issue(state, config, issue)
      dispatch_loop(state, config, rest)
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
                Worker.dispatch_issue(s, s.config, issue)

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

  # --- Helpers ---

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

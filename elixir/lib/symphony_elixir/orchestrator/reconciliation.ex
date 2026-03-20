defmodule SymphonyElixir.Orchestrator.Reconciliation do
  @moduledoc """
  Active-run reconciliation: stall detection and tracker state refresh.

  See SPEC Section 8.5.
  """

  alias SymphonyElixir.{Config, Issue}
  alias SymphonyElixir.Orchestrator.State

  @typep action ::
           {:stop_terminal, String.t(), String.t()}
           | {:stop_inactive, String.t(), String.t()}
           | {:update, String.t(), Issue.t()}

  @doc """
  Detect stalled workers based on event inactivity.

  Returns a list of issue IDs whose workers have exceeded `stall_timeout_ms`.
  """
  @spec detect_stalls(State.t(), Config.t()) :: [String.t()]
  def detect_stalls(%State{} = state, %Config{} = config) do
    stall_timeout = config.stall_timeout_ms

    if stall_timeout <= 0 do
      []
    else
      now_ms = System.monotonic_time(:millisecond)

      state.running
      |> Enum.filter(fn {_id, entry} ->
        last_activity = entry[:last_event_at_mono] || entry[:started_at_mono] || now_ms
        elapsed = now_ms - last_activity
        elapsed > stall_timeout
      end)
      |> Enum.map(fn {id, _entry} -> id end)
    end
  end

  @doc """
  Reconcile running issues against fresh tracker states.

  Returns `{actions, updated_state}` where actions is a list of:
  - `{:stop_terminal, issue_id, identifier}` - worker should be stopped, workspace cleaned
  - `{:stop_inactive, issue_id, identifier}` - worker should be stopped (no cleanup)
  - `{:update, issue_id, fresh_issue}` - update in-memory issue snapshot
  """
  @spec reconcile_tracker_states(State.t(), Config.t(), [Issue.t()]) ::
          {[action()], State.t()}
  def reconcile_tracker_states(%State{} = state, %Config{} = config, fresh_issues) do
    active_set = Config.active_state_set(config)
    terminal_set = Config.terminal_state_set(config)

    # Build a lookup from issue ID to fresh issue
    fresh_by_id = Map.new(fresh_issues, fn i -> {i.id, i} end)

    running_ids = Map.keys(state.running)

    {actions, state} =
      Enum.reduce(running_ids, {[], state}, fn issue_id, {actions_acc, state_acc} ->
        running_entry = Map.get(state_acc.running, issue_id)
        identifier = running_entry[:identifier] || ""

        case Map.get(fresh_by_id, issue_id) do
          nil ->
            # Issue not found in tracker response - keep running, try again next tick
            {actions_acc, state_acc}

          %Issue{} = fresh ->
            fresh_state = Issue.normalize_state(fresh.state)

            cond do
              MapSet.member?(terminal_set, fresh_state) ->
                # Terminal state: stop worker, clean workspace
                {[{:stop_terminal, issue_id, identifier} | actions_acc], state_acc}

              MapSet.member?(active_set, fresh_state) ->
                # Still active: update snapshot
                updated_running =
                  Map.update(state_acc.running, issue_id, running_entry, fn entry ->
                    Map.put(entry, :issue_state, fresh.state)
                  end)

                state_acc = %{state_acc | running: updated_running}
                {[{:update, issue_id, fresh} | actions_acc], state_acc}

              true ->
                # Neither active nor terminal: stop without workspace cleanup
                {[{:stop_inactive, issue_id, identifier} | actions_acc], state_acc}
            end
        end
      end)

    {Enum.reverse(actions), state}
  end
end

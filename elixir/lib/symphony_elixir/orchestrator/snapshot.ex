defmodule SymphonyElixir.Orchestrator.Snapshot do
  @moduledoc """
  Snapshot and issue detail building for the orchestrator.
  
  Produces dashboard-ready data structures from the orchestrator state.
  """

  alias SymphonyElixir.Orchestrator.{Lifecycle, State}

  @doc "Build a full snapshot of the orchestrator state for the dashboard."
  @spec build_snapshot(State.t()) :: map()
  def build_snapshot(state) do
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

  @doc "Find and build issue detail by identifier, checking running, retrying, and completed."
  @spec find_issue_detail(State.t(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def find_issue_detail(state, identifier) do
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

  @doc "Build an issue detail map from running and/or retry entries."
  @spec build_issue_detail(String.t(), map() | nil, map() | nil, atom()) :: map()
  def build_issue_detail(identifier, running_entry, retry_entry, status) do
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
      follow_ups: Lifecycle.load_follow_ups(running_entry),
      last_error: nil,
      tracked: %{}
    }
  end

  # Convert monotonic time (ms) to a wall-clock DateTime.
  defp monotonic_to_datetime(mono_ms) do
    delta_ms = mono_ms - System.monotonic_time(:millisecond)
    DateTime.add(DateTime.utc_now(), delta_ms, :millisecond)
  end
end

defmodule SymphonyElixir.Orchestrator.State do
  @moduledoc """
  Single authoritative in-memory state owned by the orchestrator.

  See SPEC Section 4.1.8.
  """

  alias SymphonyElixir.Issue

  @type running_entry :: %{
          worker_pid: pid() | nil,
          monitor_ref: reference() | nil,
          issue_id: String.t(),
          identifier: String.t(),
          issue: Issue.t(),
          issue_state: String.t() | nil,
          session_id: String.t() | nil,
          agent_process_pid: String.t() | nil,
          last_event: atom() | String.t() | nil,
          last_event_at: DateTime.t() | nil,
          last_event_at_mono: integer(),
          last_message: String.t() | nil,
          started_at_mono: integer(),
          agent_input_tokens: non_neg_integer(),
          agent_output_tokens: non_neg_integer(),
          agent_total_tokens: non_neg_integer(),
          last_reported_input_tokens: non_neg_integer(),
          last_reported_output_tokens: non_neg_integer(),
          last_reported_total_tokens: non_neg_integer(),
          turn_count: non_neg_integer(),
          retry_attempt: non_neg_integer() | nil,
          started_at: DateTime.t(),
          tokens: map()
        }

  @type retry_entry :: %{
          issue_id: String.t(),
          identifier: String.t(),
          attempt: pos_integer(),
          due_at_ms: integer(),
          timer_ref: reference() | nil,
          error: String.t() | nil
        }

  @type agent_totals :: %{
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          total_tokens: non_neg_integer(),
          seconds_running: float()
        }

  @type t :: %__MODULE__{
          config: map() | nil,
          prompt_template: String.t(),
          running: %{String.t() => running_entry()},
          claimed: MapSet.t(),
          retry_attempts: %{String.t() => retry_entry()},
          completed: MapSet.t(),
          agent_totals: agent_totals(),
          rate_limits: map() | nil,
          token_budget_exceeded: boolean()
        }

  defstruct config: nil,
            prompt_template: "",
            running: %{},
            claimed: MapSet.new(),
            retry_attempts: %{},
            completed: MapSet.new(),
            completed_runs: %{},
            agent_totals: %{
              input_tokens: 0,
              output_tokens: 0,
              total_tokens: 0,
              seconds_running: 0.0
            },
            rate_limits: nil,
            token_budget_exceeded: false

  @doc "Number of currently running issues."
  @spec running_count(t()) :: non_neg_integer()
  def running_count(%__MODULE__{running: running}), do: map_size(running)

  @doc "Number of available global concurrency slots."
  @spec available_slots(t(), pos_integer()) :: non_neg_integer()
  def available_slots(%__MODULE__{} = state, max_concurrent) do
    max(max_concurrent - running_count(state), 0)
  end

  @doc "Check if an issue is already claimed."
  @spec claimed?(t(), String.t()) :: boolean()
  def claimed?(%__MODULE__{claimed: claimed}, issue_id) do
    MapSet.member?(claimed, issue_id)
  end

  @doc "Check if an issue is currently running."
  @spec running?(t(), String.t()) :: boolean()
  def running?(%__MODULE__{running: running}, issue_id) do
    Map.has_key?(running, issue_id)
  end

  @doc "Count running issues in a given normalized state."
  @spec running_count_by_state(t(), String.t()) :: non_neg_integer()
  def running_count_by_state(%__MODULE__{running: running}, normalized_state) do
    running
    |> Map.values()
    |> Enum.count(fn entry ->
      Issue.normalize_state(entry.issue.state) == normalized_state
    end)
  end

  @doc "Add a running entry for an issue."
  @spec add_running(t(), String.t(), running_entry()) :: t()
  def add_running(%__MODULE__{} = state, issue_id, entry) do
    %{
      state
      | running: Map.put(state.running, issue_id, entry),
        claimed: MapSet.put(state.claimed, issue_id),
        retry_attempts: Map.delete(state.retry_attempts, issue_id)
    }
  end

  @doc "Remove a running entry and return updated state. Also accumulates runtime."
  @spec remove_running(t(), String.t()) :: t()
  def remove_running(%__MODULE__{} = state, issue_id) do
    case Map.pop(state.running, issue_id) do
      {nil, _} ->
        state

      {entry, running} ->
        state = %{state | running: running}
        add_runtime_seconds(state, entry)
    end
  end

  @doc "Release a claim (remove from claimed set)."
  @spec release_claim(t(), String.t()) :: t()
  def release_claim(%__MODULE__{} = state, issue_id) do
    %{
      state
      | claimed: MapSet.delete(state.claimed, issue_id),
        retry_attempts: Map.delete(state.retry_attempts, issue_id)
    }
  end

  @doc "Add runtime seconds from a finished running entry."
  @spec add_runtime_seconds(t(), running_entry()) :: t()
  def add_runtime_seconds(%__MODULE__{agent_totals: totals} = state, entry) do
    elapsed = DateTime.diff(DateTime.utc_now(), entry.started_at, :millisecond) / 1_000
    updated = %{totals | seconds_running: totals.seconds_running + elapsed}
    %{state | agent_totals: updated}
  end

  @doc "Compute live aggregate seconds_running including in-flight sessions."
  @spec live_seconds_running(t()) :: float()
  def live_seconds_running(%__MODULE__{agent_totals: totals, running: running}) do
    now = DateTime.utc_now()

    active =
      running
      |> Map.values()
      |> Enum.reduce(0.0, fn entry, acc ->
        acc + DateTime.diff(now, entry.started_at, :millisecond) / 1_000
      end)

    totals.seconds_running + active
  end

  @doc "Build a new running entry for dispatch."
  @spec new_running_entry(Issue.t(), non_neg_integer() | nil) :: running_entry()
  def new_running_entry(%Issue{} = issue, attempt) do
    now = DateTime.utc_now()
    now_mono = System.monotonic_time(:millisecond)

    %{
      worker_pid: nil,
      monitor_ref: nil,
      issue_id: issue.id,
      identifier: issue.identifier,
      issue: issue,
      issue_state: issue.state,
      session_id: nil,
      agent_process_pid: nil,
      last_event: nil,
      last_event_at: nil,
      last_message: nil,
      last_event_at_mono: now_mono,
      started_at_mono: now_mono,
      agent_input_tokens: 0,
      agent_output_tokens: 0,
      agent_total_tokens: 0,
      last_reported_input_tokens: 0,
      last_reported_output_tokens: 0,
      last_reported_total_tokens: 0,
      turn_count: 0,
      retry_attempt: normalize_attempt(attempt),
      started_at: now,
      tokens: %{input_tokens: 0, output_tokens: 0, total_tokens: 0}
    }
  end

  defp normalize_attempt(nil), do: nil
  defp normalize_attempt(n) when is_integer(n) and n >= 0, do: n
  defp normalize_attempt(_), do: nil
end

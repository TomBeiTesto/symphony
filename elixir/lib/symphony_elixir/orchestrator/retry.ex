defmodule SymphonyElixir.Orchestrator.Retry do
  @moduledoc """
  Retry and backoff logic for failed/completed worker runs.

  See SPEC Section 8.4.
  """

  alias SymphonyElixir.{Config, Issue}
  alias SymphonyElixir.Orchestrator.State

  @continuation_delay_ms 1_000
  @base_delay_ms 10_000

  @doc """
  Schedule a continuation retry (after normal worker exit).
  Uses a short fixed delay.
  """
  @spec schedule_continuation(State.t(), String.t(), String.t()) :: State.t()
  def schedule_continuation(%State{} = state, issue_id, identifier) do
    due_at = System.monotonic_time(:millisecond) + @continuation_delay_ms

    entry = %{
      issue_id: issue_id,
      identifier: identifier,
      attempt: 1,
      error: nil,
      due_at_ms: due_at,
      timer_ref: schedule_timer(due_at)
    }

    state = cancel_existing_retry(state, issue_id)
    %{state | retry_attempts: Map.put(state.retry_attempts, issue_id, entry)}
  end

  @doc """
  Schedule an exponential-backoff retry (after failure).
  """
  @spec schedule_failure_retry(
          State.t(),
          Config.t(),
          String.t(),
          String.t(),
          non_neg_integer(),
          String.t()
        ) ::
          State.t()
  def schedule_failure_retry(
        %State{} = state,
        %Config{} = config,
        issue_id,
        identifier,
        attempt,
        error
      ) do
    delay = compute_backoff(attempt, config.max_retry_backoff_ms)
    due_at = System.monotonic_time(:millisecond) + delay

    entry = %{
      issue_id: issue_id,
      identifier: identifier,
      attempt: attempt,
      error: error,
      due_at_ms: due_at,
      timer_ref: schedule_timer(due_at)
    }

    state = cancel_existing_retry(state, issue_id)
    %{state | retry_attempts: Map.put(state.retry_attempts, issue_id, entry)}
  end

  @doc "Compute exponential backoff delay, capped by max."
  @spec compute_backoff(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def compute_backoff(attempt, max_backoff_ms) do
    delay = @base_delay_ms * :math.pow(2, max(attempt - 1, 0))
    min(round(delay), max_backoff_ms)
  end

  @doc "Get all retry entries that are due now."
  @spec due_retries(State.t()) :: [map()]
  def due_retries(%State{} = state) do
    now = System.monotonic_time(:millisecond)

    state.retry_attempts
    |> Map.values()
    |> Enum.filter(fn entry -> entry.due_at_ms <= now end)
  end

  @doc """
  Handle a fired retry timer. Re-checks eligibility and dispatches or releases.

  Returns `{action, updated_state}` where action is:
  - `{:dispatch, issue}` - ready to dispatch
  - `{:requeue, reason}` - requeued with new backoff
  - `:released` - claim released
  """
  @spec handle_retry(State.t(), Config.t(), String.t(), [Issue.t()]) ::
          {{:dispatch, Issue.t()}, State.t()}
          | {{:requeue, String.t()}, State.t()}
          | {:released, State.t()}
  def handle_retry(%State{} = state, %Config{} = config, issue_id, active_candidates) do
    retry_entry = Map.get(state.retry_attempts, issue_id)

    if is_nil(retry_entry) do
      {:released, state}
    else
      identifier = retry_entry.identifier
      attempt = retry_entry.attempt

      # Remove the retry entry first
      state = %{state | retry_attempts: Map.delete(state.retry_attempts, issue_id)}

      # Find the issue in active candidates
      case Enum.find(active_candidates, fn i -> i.id == issue_id end) do
        nil ->
          # Issue no longer in active candidates -> release
          state = State.release_claim(state, issue_id)
          {:released, state}

        %Issue{} = issue ->
          # Check if we can dispatch
          slots = State.available_slots(state, config.max_concurrent_agents)

          if slots > 0 do
            {{:dispatch, issue}, state}
          else
            # Requeue
            state =
              schedule_failure_retry(
                state,
                config,
                issue_id,
                identifier,
                attempt + 1,
                "no available orchestrator slots"
              )

            {{:requeue, "no available orchestrator slots"}, state}
          end
      end
    end
  end

  @doc "Cancel a retry for an issue."
  @spec cancel_retry(State.t(), String.t()) :: State.t()
  def cancel_retry(%State{} = state, issue_id) do
    cancel_existing_retry(state, issue_id)
  end

  # --- Private ---

  defp cancel_existing_retry(%State{} = state, issue_id) do
    case Map.get(state.retry_attempts, issue_id) do
      %{timer_ref: ref} when is_reference(ref) ->
        Process.cancel_timer(ref)
        %{state | retry_attempts: Map.delete(state.retry_attempts, issue_id)}

      _ ->
        state
    end
  end

  defp schedule_timer(due_at_ms) do
    delay = max(due_at_ms - System.monotonic_time(:millisecond), 0)
    Process.send_after(self(), {:retry_timer, due_at_ms}, delay)
  end
end

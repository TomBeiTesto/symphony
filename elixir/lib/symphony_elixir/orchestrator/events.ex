defmodule SymphonyElixir.Orchestrator.Events do
  @moduledoc """
  Agent event handling for the orchestrator.

  Processes streaming events from agent sessions, updating running entries
  with event logs, token usage, rate limits, and result text.
  """

  require Logger

  @max_event_log 100

  @doc """
  Handle an agent event for a running issue.

  Updates the running entry with event metadata, appends to the event log,
  accumulates result text, and tracks token usage.

  Returns the updated state.
  """
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def handle_agent_event(state, issue_id, event) do
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

        event_log = Enum.take(event_log, -@max_event_log)

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

end

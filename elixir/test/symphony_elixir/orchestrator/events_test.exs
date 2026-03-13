defmodule SymphonyElixir.Orchestrator.EventsTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Orchestrator.{Events, State}

  @issue %Issue{id: "issue-1", identifier: "MT-1", title: "Test", state: "In Progress"}

  defp state_with_running do
    entry = State.new_running_entry(@issue, nil)
    State.add_running(%State{}, "issue-1", entry)
  end

  describe "handle_agent_event/3" do
    test "ignores events for non-running issues" do
      state = %State{}
      event = %{event: :turn_completed, timestamp: DateTime.utc_now(), payload: %{}}
      result = Events.handle_agent_event(state, "unknown-id", event)
      assert result == state
    end

    test "updates last_event and last_event_at" do
      state = state_with_running()
      now = DateTime.utc_now()
      event = %{event: :turn_completed, timestamp: now, payload: %{}}

      result = Events.handle_agent_event(state, "issue-1", event)
      entry = result.running["issue-1"]

      assert entry[:last_event] == :turn_completed
      assert entry[:last_event_at] == now
    end

    test "updates last_message from payload" do
      state = state_with_running()
      event = %{event: :message, timestamp: DateTime.utc_now(), payload: %{message: "Working..."}}

      result = Events.handle_agent_event(state, "issue-1", event)
      assert result.running["issue-1"][:last_message] == "Working..."
    end

    test "appends to event log" do
      state = state_with_running()
      event = %{event: :tool_call, timestamp: DateTime.utc_now(), payload: %{tool: "Read"}}

      result = Events.handle_agent_event(state, "issue-1", event)
      log = result.running["issue-1"][:event_log]

      assert length(log) == 1
      assert hd(log).event == :tool_call
      assert hd(log).tool == "Read"
    end

    test "accumulates result text with separator" do
      state = state_with_running()
      ts = DateTime.utc_now()

      state =
        Events.handle_agent_event(state, "issue-1", %{
          event: :result,
          timestamp: ts,
          payload: %{result: "First result"}
        })

      state =
        Events.handle_agent_event(state, "issue-1", %{
          event: :result,
          timestamp: ts,
          payload: %{result: "Second result"}
        })

      text = state.running["issue-1"][:result_text]
      assert String.contains?(text, "First result")
      assert String.contains?(text, "Second result")
      assert String.contains?(text, "---")
    end

    test "tracks token usage and updates aggregate totals" do
      state = state_with_running()

      event = %{
        event: :tokens,
        timestamp: DateTime.utc_now(),
        payload: %{input_tokens: 100, output_tokens: 50, total_tokens: 150}
      }

      result = Events.handle_agent_event(state, "issue-1", event)

      assert result.agent_totals.input_tokens == 100
      assert result.agent_totals.output_tokens == 50
      assert result.agent_totals.total_tokens == 150
      assert result.running["issue-1"][:tokens].input_tokens == 100
    end

    test "does not produce negative token deltas" do
      state = state_with_running()

      # Set initial tokens high
      state =
        Events.handle_agent_event(state, "issue-1", %{
          event: :tokens,
          timestamp: DateTime.utc_now(),
          payload: %{input_tokens: 500, output_tokens: 200, total_tokens: 700}
        })

      # Receive lower tokens (should not subtract from aggregate)
      state =
        Events.handle_agent_event(state, "issue-1", %{
          event: :tokens,
          timestamp: DateTime.utc_now(),
          payload: %{input_tokens: 100, output_tokens: 50, total_tokens: 150}
        })

      assert state.agent_totals.input_tokens >= 500
    end

    test "updates rate limits from payload" do
      state = state_with_running()

      event = %{
        event: :rate_limits,
        timestamp: DateTime.utc_now(),
        payload: %{rate_limits: %{"remaining" => 50}}
      }

      result = Events.handle_agent_event(state, "issue-1", event)
      assert result.rate_limits == %{"remaining" => 50}
    end

    test "truncates event log to max 100 entries" do
      state = state_with_running()
      ts = DateTime.utc_now()

      # Add 105 events
      state =
        Enum.reduce(1..105, state, fn i, s ->
          Events.handle_agent_event(s, "issue-1", %{
            event: :msg,
            timestamp: ts,
            payload: %{message: "event #{i}"}
          })
        end)

      log = state.running["issue-1"][:event_log]
      assert length(log) == 100
    end
  end
end

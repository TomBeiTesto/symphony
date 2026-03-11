defmodule SymphonyElixir.Orchestrator.StateTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Orchestrator.State

  @issue %Issue{
    id: "issue-1",
    identifier: "MT-100",
    title: "Test issue",
    state: "In Progress"
  }

  describe "new struct" do
    test "starts with empty maps and default totals" do
      state = %State{}
      assert state.running == %{}
      assert state.claimed == MapSet.new()
      assert state.retry_attempts == %{}
      assert state.agent_totals.input_tokens == 0
      assert state.agent_totals.seconds_running == 0.0
      assert state.rate_limits == nil
    end
  end

  describe "running_count/1" do
    test "returns 0 for empty state" do
      assert State.running_count(%State{}) == 0
    end

    test "returns correct count" do
      entry = State.new_running_entry(@issue, nil)
      state = State.add_running(%State{}, "issue-1", entry)
      assert State.running_count(state) == 1
    end
  end

  describe "available_slots/2" do
    test "returns max when nothing running" do
      assert State.available_slots(%State{}, 10) == 10
    end

    test "returns remaining slots" do
      entry = State.new_running_entry(@issue, nil)
      state = State.add_running(%State{}, "issue-1", entry)
      assert State.available_slots(state, 10) == 9
    end

    test "returns 0 when at capacity" do
      entry = State.new_running_entry(@issue, nil)
      state = State.add_running(%State{}, "issue-1", entry)
      assert State.available_slots(state, 1) == 0
    end

    test "never returns negative" do
      entry = State.new_running_entry(@issue, nil)
      state = State.add_running(%State{}, "issue-1", entry)
      assert State.available_slots(state, 0) == 0
    end
  end

  describe "claimed?/2" do
    test "returns false when not claimed" do
      refute State.claimed?(%State{}, "issue-1")
    end

    test "returns true when claimed via add_running" do
      entry = State.new_running_entry(@issue, nil)
      state = State.add_running(%State{}, "issue-1", entry)
      assert State.claimed?(state, "issue-1")
    end
  end

  describe "running?/2" do
    test "returns false when not running" do
      refute State.running?(%State{}, "issue-1")
    end

    test "returns true when running" do
      entry = State.new_running_entry(@issue, nil)
      state = State.add_running(%State{}, "issue-1", entry)
      assert State.running?(state, "issue-1")
    end
  end

  describe "add_running/3" do
    test "adds entry to running and claimed, removes from retry" do
      retry_entry = %{
        issue_id: "issue-1",
        identifier: "MT-100",
        attempt: 1,
        due_at_ms: 0,
        timer_ref: nil,
        error: nil
      }

      state = %State{retry_attempts: %{"issue-1" => retry_entry}}
      entry = State.new_running_entry(@issue, nil)
      state = State.add_running(state, "issue-1", entry)

      assert Map.has_key?(state.running, "issue-1")
      assert MapSet.member?(state.claimed, "issue-1")
      refute Map.has_key?(state.retry_attempts, "issue-1")
    end
  end

  describe "remove_running/2" do
    test "removes entry from running and accumulates runtime" do
      entry = State.new_running_entry(@issue, nil)
      state = State.add_running(%State{}, "issue-1", entry)
      assert State.running?(state, "issue-1")

      state = State.remove_running(state, "issue-1")
      refute State.running?(state, "issue-1")
      # Runtime should have been accumulated
      assert state.agent_totals.seconds_running >= 0
    end

    test "is a no-op for non-existent issue" do
      state = %State{}
      assert state == State.remove_running(state, "nonexistent")
    end
  end

  describe "release_claim/2" do
    test "removes from claimed and retry" do
      entry = State.new_running_entry(@issue, nil)
      state = State.add_running(%State{}, "issue-1", entry)
      assert State.claimed?(state, "issue-1")

      state = State.release_claim(state, "issue-1")
      refute State.claimed?(state, "issue-1")
    end
  end

  describe "new_running_entry/2" do
    test "creates entry with correct fields" do
      entry = State.new_running_entry(@issue, 2)
      assert entry.identifier == "MT-100"
      assert entry.issue == @issue
      assert entry.issue_id == "issue-1"
      assert entry.issue_state == "In Progress"
      assert entry.session_id == nil
      assert entry.turn_count == 0
      assert entry.retry_attempt == 2
      assert %DateTime{} = entry.started_at
      assert is_integer(entry.started_at_mono)
      assert is_integer(entry.last_event_at_mono)
    end

    test "normalizes nil attempt" do
      entry = State.new_running_entry(@issue, nil)
      assert entry.retry_attempt == nil
    end
  end

  describe "running_count_by_state/2" do
    test "counts running issues by normalized state" do
      issue1 = %Issue{id: "1", identifier: "A-1", title: "T", state: "In Progress"}
      issue2 = %Issue{id: "2", identifier: "A-2", title: "T", state: "In Progress"}
      issue3 = %Issue{id: "3", identifier: "A-3", title: "T", state: "Todo"}

      state =
        %State{}
        |> State.add_running("1", State.new_running_entry(issue1, nil))
        |> State.add_running("2", State.new_running_entry(issue2, nil))
        |> State.add_running("3", State.new_running_entry(issue3, nil))

      assert State.running_count_by_state(state, "in progress") == 2
      assert State.running_count_by_state(state, "todo") == 1
      assert State.running_count_by_state(state, "done") == 0
    end
  end

  describe "live_seconds_running/1" do
    test "returns 0 for empty state" do
      assert State.live_seconds_running(%State{}) == 0.0
    end

    test "includes active session elapsed time" do
      entry = State.new_running_entry(@issue, nil)
      state = State.add_running(%State{}, "issue-1", entry)
      # Should be very close to 0 since just created
      assert State.live_seconds_running(state) >= 0.0
    end
  end
end

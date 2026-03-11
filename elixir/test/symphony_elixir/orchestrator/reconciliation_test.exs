defmodule SymphonyElixir.Orchestrator.ReconciliationTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.{Config, Issue}
  alias SymphonyElixir.Orchestrator.{Reconciliation, State}

  @config_map %{
    "tracker" => %{
      "kind" => "local",
      "project_slug" => "test",
      "api_key" => "key",
      "active_states" => ["Todo", "In Progress"],
      "terminal_states" => ["Done", "Closed"]
    },
    "agent_process" => %{
      "stall_timeout_ms" => 5000
    }
  }

  setup do
    {:ok, config} = Config.from_workflow(@config_map)
    %{config: config}
  end

  defp make_issue(id, identifier, state) do
    %Issue{id: id, identifier: identifier, title: "T", state: state}
  end

  describe "detect_stalls/2" do
    test "returns empty for no running entries", %{config: config} do
      assert [] = Reconciliation.detect_stalls(%State{}, config)
    end

    test "returns stalled entries based on monotonic time", %{config: config} do
      # Create a running entry with stale monotonic time
      entry = State.new_running_entry(make_issue("1", "MT-1", "In Progress"), nil)

      stale_entry =
        Map.put(entry, :last_event_at_mono, System.monotonic_time(:millisecond) - 10_000)

      state = %State{running: %{"1" => stale_entry}}
      stalled = Reconciliation.detect_stalls(state, config)
      assert "1" in stalled
    end

    test "does not flag fresh entries", %{config: config} do
      entry = State.new_running_entry(make_issue("1", "MT-1", "In Progress"), nil)
      state = %State{running: %{"1" => entry}}

      stalled = Reconciliation.detect_stalls(state, config)
      assert stalled == []
    end

    test "skips when stall_timeout_ms is 0" do
      {:ok, config} =
        Config.from_workflow(%{
          "tracker" => %{"kind" => "local", "project_slug" => "t", "api_key" => "k"},
          "agent_process" => %{"stall_timeout_ms" => 0}
        })

      entry = State.new_running_entry(make_issue("1", "MT-1", "In Progress"), nil)

      stale_entry =
        Map.put(entry, :last_event_at_mono, System.monotonic_time(:millisecond) - 999_999)

      state = %State{running: %{"1" => stale_entry}}

      assert [] = Reconciliation.detect_stalls(state, config)
    end
  end

  describe "reconcile_tracker_states/3" do
    test "marks terminal issues for stop+cleanup", %{config: config} do
      entry = State.new_running_entry(make_issue("1", "MT-1", "In Progress"), nil)
      state = %State{running: %{"1" => entry}}

      fresh = [make_issue("1", "MT-1", "Done")]
      {actions, _state} = Reconciliation.reconcile_tracker_states(state, config, fresh)

      assert {:stop_terminal, "1", "MT-1"} in actions
    end

    test "marks inactive (non-active, non-terminal) issues for stop without cleanup", %{
      config: config
    } do
      entry = State.new_running_entry(make_issue("1", "MT-1", "In Progress"), nil)
      state = %State{running: %{"1" => entry}}

      fresh = [make_issue("1", "MT-1", "Backlog")]
      {actions, _state} = Reconciliation.reconcile_tracker_states(state, config, fresh)

      assert {:stop_inactive, "1", "MT-1"} in actions
    end

    test "updates snapshot for still-active issues", %{config: config} do
      entry = State.new_running_entry(make_issue("1", "MT-1", "Todo"), nil)
      state = %State{running: %{"1" => entry}}

      fresh = [make_issue("1", "MT-1", "In Progress")]
      {actions, state} = Reconciliation.reconcile_tracker_states(state, config, fresh)

      assert {:update, "1", _} = Enum.find(actions, fn {type, _, _} -> type == :update end)
      assert state.running["1"][:issue_state] == "In Progress"
    end

    test "ignores missing issues in tracker response", %{config: config} do
      entry = State.new_running_entry(make_issue("1", "MT-1", "In Progress"), nil)
      state = %State{running: %{"1" => entry}}

      # Empty fresh response - issue not found
      {actions, _state} = Reconciliation.reconcile_tracker_states(state, config, [])
      assert actions == []
    end
  end
end

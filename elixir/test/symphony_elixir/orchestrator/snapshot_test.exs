defmodule SymphonyElixir.Orchestrator.SnapshotTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Orchestrator.{Snapshot, State}

  @issue %Issue{id: "issue-1", identifier: "MT-1", title: "Test", state: "In Progress"}

  setup do
    board_store = "test_snapshot_board_#{System.unique_integer([:positive])}.json"

    start_supervised!({SymphonyElixir.LocalBoard, store_path: board_store, project_prefix: "MT"})

    on_exit(fn -> File.rm(board_store) end)
    :ok
  end

  defp base_state, do: %State{}

  defp state_with_running do
    entry = State.new_running_entry(@issue, nil)
    State.add_running(base_state(), "issue-1", entry)
  end

  describe "build_snapshot/1" do
    test "returns expected structure for empty state" do
      snapshot = Snapshot.build_snapshot(base_state())

      assert %DateTime{} = snapshot.generated_at
      assert snapshot.counts == %{running: 0, retrying: 0}
      assert snapshot.running == []
      assert snapshot.retrying == []
      assert snapshot.agent_totals.input_tokens == 0
      assert snapshot.agent_totals.output_tokens == 0
      assert snapshot.agent_totals.total_tokens == 0
      assert is_float(snapshot.agent_totals.seconds_running)
      assert snapshot.rate_limits == nil
      assert snapshot.token_budget_exceeded == false
    end

    test "counts running and retrying entries" do
      state = state_with_running()
      snapshot = Snapshot.build_snapshot(state)

      assert snapshot.counts.running == 1
      assert snapshot.counts.retrying == 0
      assert length(snapshot.running) == 1
    end

    test "running entry has expected fields" do
      state = state_with_running()
      [entry] = Snapshot.build_snapshot(state).running

      assert entry.issue_id == "issue-1"
      assert entry.issue_identifier == "MT-1"
      assert entry.turn_count == 0
      assert is_map(entry.tokens)
    end

    test "reflects token_budget_exceeded" do
      state = %{base_state() | token_budget_exceeded: true}
      snapshot = Snapshot.build_snapshot(state)
      assert snapshot.token_budget_exceeded == true
    end
  end

  describe "find_issue_detail/2" do
    test "returns not_found for unknown identifier" do
      assert {:error, :not_found} = Snapshot.find_issue_detail(base_state(), "MT-999")
    end

    test "finds running issue by identifier" do
      state = state_with_running()
      assert {:ok, detail} = Snapshot.find_issue_detail(state, "MT-1")
      assert detail.issue_identifier == "MT-1"
      assert detail.status == "running"
      assert detail.running != nil
      assert detail.retry == nil
    end

    test "finds completed issue by identifier" do
      state = state_with_running()
      entry = state.running["issue-1"]
      state = State.remove_running(state, "issue-1")
      state = %{state | completed_runs: Map.put(state.completed_runs, "issue-1", entry)}

      assert {:ok, detail} = Snapshot.find_issue_detail(state, "MT-1")
      assert detail.status == "completed"
    end

    test "running takes priority over completed" do
      state = state_with_running()
      entry = state.running["issue-1"]
      # Add same issue to completed_runs while still running
      state = %{state | completed_runs: Map.put(state.completed_runs, "issue-1", entry)}

      assert {:ok, detail} = Snapshot.find_issue_detail(state, "MT-1")
      assert detail.status == "running"
    end
  end
end

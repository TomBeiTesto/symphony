defmodule SymphonyElixir.OrchestratorTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.{Config, LocalBoard, Orchestrator}

  import SymphonyElixir.TestHelpers, only: [wait_until: 1]

  @minimal_config %Config{
    tracker_kind: "local",
    workspace_root: System.tmp_dir!() |> Path.join("symphony_orch_test"),
    poll_interval_ms: 999_999_999,
    max_concurrent_agents: 2,
    stall_timeout_ms: 600_000
  }

  setup do
    board_store = "test_orch_board_#{System.unique_integer([:positive])}.json"
    settings_store = "test_orch_settings_#{System.unique_integer([:positive])}.json"

    start_supervised!({LocalBoard, store_path: board_store, project_prefix: "ORCH"})
    start_supervised!({SymphonyElixir.Settings, store_path: settings_store})
    start_supervised!({Task.Supervisor, name: SymphonyElixir.WorkerTaskSupervisor})

    on_exit(fn ->
      File.rm(board_store)
      File.rm(settings_store)
    end)

    %{board_store: board_store, settings_store: settings_store}
  end

  defp start_orchestrator do
    pid =
      start_supervised!(
        {Orchestrator,
         config: %{@minimal_config | poll_interval_ms: 999_999_999},
         prompt_template: "Work on {{ issue.identifier }}"},
        restart: :temporary
      )

    # Wait for init + initial tick to complete
    wait_until(fn -> Process.alive?(pid) and Orchestrator.get_snapshot() != nil end)
    pid
  end

  # --- approve_plan ---

  describe "approve_plan/1" do
    test "changes plan_status from plan_review to approved" do
      {:ok, issue} =
        LocalBoard.create_issue(%{
          "title" => "Plan issue",
          "state" => "Todo",
          "plan_status" => "plan_review",
          "plan_text" => "Refactor module X."
        })

      start_orchestrator()

      assert :ok = Orchestrator.approve_plan(issue.id)

      {:ok, updated} = LocalBoard.get_issue(issue.id)
      assert updated.plan_status == "approved"
      assert updated.plan_text == "Refactor module X."
    end

    test "returns error when issue is not in plan_review" do
      {:ok, issue} =
        LocalBoard.create_issue(%{
          "title" => "Not in review",
          "state" => "Todo",
          "plan_status" => "planning"
        })

      start_orchestrator()

      assert {:error, :not_in_plan_review} = Orchestrator.approve_plan(issue.id)
    end

    test "returns error for nonexistent issue" do
      start_orchestrator()
      assert {:error, :not_found} = Orchestrator.approve_plan("nonexistent_id")
    end
  end

  # --- reject_plan ---

  describe "reject_plan/2" do
    test "appends feedback to description and resets plan_status to planning" do
      {:ok, issue} =
        LocalBoard.create_issue(%{
          "title" => "Rejectable plan",
          "state" => "Todo",
          "description" => "Original description",
          "plan_status" => "plan_review",
          "plan_text" => "Some plan text"
        })

      start_orchestrator()

      assert :ok = Orchestrator.reject_plan(issue.id, "Please add error handling")

      {:ok, updated} = LocalBoard.get_issue(issue.id)
      assert updated.plan_status == "planning"
      assert updated.plan_text == nil
      assert String.contains?(updated.description, "Original description")
      assert String.contains?(updated.description, "Plan Feedback:")
      assert String.contains?(updated.description, "Please add error handling")
    end

    test "resets plan without feedback, description unchanged" do
      {:ok, issue} =
        LocalBoard.create_issue(%{
          "title" => "Reject no feedback",
          "state" => "Todo",
          "description" => "Desc",
          "plan_status" => "plan_review",
          "plan_text" => "Old plan"
        })

      start_orchestrator()

      assert :ok = Orchestrator.reject_plan(issue.id, nil)

      {:ok, updated} = LocalBoard.get_issue(issue.id)
      assert updated.plan_status == "planning"
      assert updated.plan_text == nil
      assert updated.description == "Desc"
    end

    test "returns error when issue is not in plan_review" do
      {:ok, issue} =
        LocalBoard.create_issue(%{
          "title" => "Wrong state",
          "state" => "Todo",
          "plan_status" => "approved"
        })

      start_orchestrator()

      assert {:error, :not_in_plan_review} = Orchestrator.reject_plan(issue.id, "feedback")
    end
  end

  # --- rerun_issue ---

  describe "rerun_issue/2" do
    test "resets issue to In Progress with hint" do
      {:ok, issue} =
        LocalBoard.create_issue(%{
          "title" => "Completed task",
          "state" => "Done"
        })

      start_orchestrator()

      assert :ok = Orchestrator.rerun_issue(issue.id, "Be more thorough")

      {:ok, updated} = LocalBoard.get_issue(issue.id)
      assert updated.state == "In Progress"
      assert updated.rerun_hint == "Be more thorough"
      assert updated.plan_status == nil
      assert updated.plan_text == nil
    end

    test "resets issue without hint" do
      {:ok, issue} =
        LocalBoard.create_issue(%{
          "title" => "Rerun no hint",
          "state" => "Done"
        })

      start_orchestrator()

      assert :ok = Orchestrator.rerun_issue(issue.id, nil)

      {:ok, updated} = LocalBoard.get_issue(issue.id)
      assert updated.state == "In Progress"
      assert updated.rerun_hint == nil
    end

    test "clears previous agent_run" do
      {:ok, issue} =
        LocalBoard.create_issue(%{
          "title" => "Has agent run",
          "state" => "Done"
        })

      LocalBoard.save_agent_run(issue.id, %{"completed_at" => "2026-03-18T00:00:00Z"})

      start_orchestrator()

      assert :ok = Orchestrator.rerun_issue(issue.id)

      {:ok, updated} = LocalBoard.get_issue(issue.id)
      assert Map.get(updated, :agent_run) == nil
    end

    test "returns error for nonexistent issue" do
      start_orchestrator()
      assert {:error, :not_found} = Orchestrator.rerun_issue("nonexistent_id")
    end
  end

  # --- auto_archive_done_issues ---

  describe "auto_archive_done_issues/0" do
    test "archives Done issues with agent_run completed_at older than 1 day" do
      {:ok, issue} =
        LocalBoard.create_issue(%{
          "title" => "Old done issue",
          "state" => "Done"
        })

      # Set agent_run with a completed_at 2 days ago
      two_days_ago =
        DateTime.utc_now()
        |> DateTime.add(-2 * 86_400, :second)
        |> DateTime.to_iso8601()

      LocalBoard.save_agent_run(issue.id, %{"completed_at" => two_days_ago})

      start_orchestrator()

      wait_until(fn ->
        {:ok, i} = LocalBoard.get_issue(issue.id)
        i.state == "Archived"
      end)
    end

    test "does not archive recent Done issues" do
      {:ok, issue} =
        LocalBoard.create_issue(%{
          "title" => "Recent done issue",
          "state" => "Done"
        })

      start_orchestrator()

      # Give the tick a chance to run, then verify it wasn't archived
      Process.sleep(200)

      {:ok, updated} = LocalBoard.get_issue(issue.id)
      assert updated.state == "Done"
    end
  end

  # --- auto_promote_backlog_to_todo ---

  describe "auto_promote_backlog_to_todo/0" do
    test "promotes backlog issues when auto_add_enabled and slots available" do
      SymphonyElixir.Settings.update(%{
        "auto_add_enabled" => "true",
        "max_todo_parallel" => "2"
      })

      {:ok, issue} =
        LocalBoard.create_issue(%{
          "title" => "Backlog task",
          "state" => "Backlog",
          "priority" => 1
        })

      start_orchestrator()

      wait_until(fn ->
        {:ok, i} = LocalBoard.get_issue(issue.id)
        i.state in ["Todo", "In Progress"]
      end)
    end

    test "respects per-project max_todo limit" do
      SymphonyElixir.Settings.update(%{
        "auto_add_enabled" => "true",
        "max_todo_parallel" => "1"
      })

      {:ok, project} = LocalBoard.create_project(%{"name" => "Test Proj"})

      {:ok, _existing} =
        LocalBoard.create_issue(%{
          "title" => "Existing todo",
          "state" => "Todo",
          "project_id" => project.id
        })

      {:ok, backlog} =
        LocalBoard.create_issue(%{
          "title" => "Backlog waiting",
          "state" => "Backlog",
          "project_id" => project.id,
          "priority" => 1
        })

      start_orchestrator()

      # Give the tick a chance to run, then verify it stayed in Backlog
      Process.sleep(200)

      {:ok, updated} = LocalBoard.get_issue(backlog.id)
      assert updated.state == "Backlog"
    end

    test "does not promote when auto_add_enabled is false" do
      SymphonyElixir.Settings.update(%{"auto_add_enabled" => "false"})

      {:ok, issue} =
        LocalBoard.create_issue(%{
          "title" => "Stays in backlog",
          "state" => "Backlog"
        })

      start_orchestrator()

      # Give the tick a chance to run, then verify it stayed in Backlog
      Process.sleep(200)

      {:ok, updated} = LocalBoard.get_issue(issue.id)
      assert updated.state == "Backlog"
    end
  end

  # --- get_snapshot ---

  describe "get_snapshot/0" do
    test "returns snapshot with expected structure" do
      start_orchestrator()

      snapshot = Orchestrator.get_snapshot()

      assert %{
               generated_at: %DateTime{},
               counts: %{running: 0, retrying: 0},
               running: [],
               retrying: [],
               agent_totals: %{
                 input_tokens: 0,
                 output_tokens: 0,
                 total_tokens: 0,
                 seconds_running: _
               },
               rate_limits: nil,
               token_budget_exceeded: false
             } = snapshot
    end
  end

  # --- get_issue_detail ---

  describe "get_issue_detail/1" do
    test "returns not_found for unknown identifier" do
      start_orchestrator()
      assert {:error, :not_found} = Orchestrator.get_issue_detail("ORCH-999")
    end

    test "returns not_found for issue that exists on board but is not running" do
      {:ok, _} =
        LocalBoard.create_issue(%{
          "title" => "Idle issue",
          "state" => "Done"
        })

      start_orchestrator()

      # The issue is on the board in a terminal state, so not tracked in running
      assert {:error, :not_found} = Orchestrator.get_issue_detail("ORCH-1")
    end
  end
end

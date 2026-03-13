defmodule SymphonyElixir.OrchestratorTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.{Config, LocalBoard, Orchestrator}

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

    on_exit(fn ->
      File.rm(board_store)
      File.rm(settings_store)
    end)

    %{board_store: board_store, settings_store: settings_store}
  end

  defp start_orchestrator do
    config = %{@minimal_config | poll_interval_ms: 999_999_999}

    pid =
      start_supervised!(
        {Orchestrator, config: config, prompt_template: "Work on {{ issue.identifier }}"},
        restart: :temporary
      )

    # Allow init + initial tick to complete
    Process.sleep(150)
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
      Process.sleep(200)

      {:ok, updated} = LocalBoard.get_issue(issue.id)
      assert updated.state == "Archived"
    end

    test "does not archive recent Done issues" do
      {:ok, issue} =
        LocalBoard.create_issue(%{
          "title" => "Recent done issue",
          "state" => "Done"
        })

      start_orchestrator()
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
      Process.sleep(200)

      {:ok, updated} = LocalBoard.get_issue(issue.id)
      # Issue gets promoted from Backlog to Todo, then may get dispatched to In Progress
      assert updated.state in ["Todo", "In Progress"]
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

defmodule SymphonyElixir.Orchestrator.RetryTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.{Config, Issue}
  alias SymphonyElixir.Orchestrator.{Retry, State}

  setup do
    {:ok, config} =
      Config.from_workflow(%{
        "tracker" => %{"kind" => "local", "project_slug" => "test", "api_key" => "key"},
        "agent" => %{"max_concurrent_agents" => 5, "max_retry_backoff_ms" => 300_000}
      })

    %{config: config}
  end

  defp make_issue(id, identifier, state) do
    %Issue{id: id, identifier: identifier, title: "T", state: state}
  end

  describe "compute_backoff/2" do
    test "first attempt uses base delay" do
      assert Retry.compute_backoff(1, 300_000) == 10_000
    end

    test "exponential growth" do
      assert Retry.compute_backoff(2, 300_000) == 20_000
      assert Retry.compute_backoff(3, 300_000) == 40_000
      assert Retry.compute_backoff(4, 300_000) == 80_000
    end

    test "caps at max_retry_backoff_ms" do
      assert Retry.compute_backoff(100, 300_000) == 300_000
    end

    test "handles 0 attempt" do
      assert Retry.compute_backoff(0, 300_000) == 10_000
    end
  end

  describe "schedule_failure_retry/6" do
    test "creates a retry entry with backoff delay", %{config: config} do
      state = %State{}
      state = Retry.schedule_failure_retry(state, config, "issue-1", "MT-100", 2, "turn_failed")

      entry = state.retry_attempts["issue-1"]
      assert entry.attempt == 2
      assert entry.error == "turn_failed"
      assert is_integer(entry.due_at_ms)
    end

    test "replaces existing retry entry", %{config: config} do
      old_entry = %{issue_id: "issue-1", identifier: "MT-100", attempt: 1, error: nil, due_at_ms: 0, timer_ref: nil}
      state = %State{retry_attempts: %{"issue-1" => old_entry}}

      state = Retry.schedule_failure_retry(state, config, "issue-1", "MT-100", 3, "error")
      new_entry = state.retry_attempts["issue-1"]

      assert new_entry.attempt == 3
      assert new_entry.due_at_ms != old_entry.due_at_ms
    end
  end

  describe "due_retries/1" do
    test "returns entries that are past due" do
      state = %State{
        retry_attempts: %{
          "past" => %{
            issue_id: "past",
            identifier: "MT-1",
            attempt: 1,
            due_at_ms: System.monotonic_time(:millisecond) - 1000,
            timer_ref: nil,
            error: nil
          },
          "future" => %{
            issue_id: "future",
            identifier: "MT-2",
            attempt: 1,
            due_at_ms: System.monotonic_time(:millisecond) + 60_000,
            timer_ref: nil,
            error: nil
          }
        }
      }

      due = Retry.due_retries(state)
      assert length(due) == 1
      assert hd(due).issue_id == "past"
    end
  end

  describe "handle_retry/4" do
    test "dispatches when issue found and slots available", %{config: config} do
      issue = make_issue("issue-1", "MT-100", "In Progress")
      entry = %{issue_id: "issue-1", identifier: "MT-100", attempt: 1, error: nil, due_at_ms: 0, timer_ref: nil}
      state = %State{retry_attempts: %{"issue-1" => entry}}

      {result, _state} = Retry.handle_retry(state, config, "issue-1", [issue])
      assert {:dispatch, %Issue{}} = result
    end

    test "releases claim when issue not in candidates", %{config: config} do
      entry = %{issue_id: "issue-1", identifier: "MT-100", attempt: 1, error: nil, due_at_ms: 0, timer_ref: nil}
      state = %State{retry_attempts: %{"issue-1" => entry}, claimed: MapSet.new(["issue-1"])}

      {result, state} = Retry.handle_retry(state, config, "issue-1", [])
      assert result == :released
      refute State.claimed?(state, "issue-1")
    end

    test "requeues when no slots available", %{config: config} do
      issue = make_issue("issue-1", "MT-100", "In Progress")

      # Fill all 5 slots
      running =
        for i <- 1..5, into: %{} do
          iss = make_issue("other-#{i}", "MT-#{i}", "In Progress")
          {"other-#{i}", State.new_running_entry(iss, nil)}
        end

      state = %State{
        running: running,
        retry_attempts: %{
          "issue-1" => %{
            issue_id: "issue-1",
            identifier: "MT-100",
            attempt: 1,
            due_at_ms: 0,
            timer_ref: nil,
            error: nil
          }
        },
        claimed: MapSet.new(["issue-1"])
      }

      {result, state} = Retry.handle_retry(state, config, "issue-1", [issue])
      assert {:requeue, _reason} = result
      assert Map.has_key?(state.retry_attempts, "issue-1")
    end
  end

end

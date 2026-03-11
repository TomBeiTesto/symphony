defmodule SymphonyElixir.Server.DashboardTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Server.Dashboard

  @empty_snapshot %{
    generated_at: ~U[2026-01-15 10:00:00Z],
    counts: %{running: 0, retrying: 0},
    running: [],
    retrying: [],
    agent_totals: %{
      input_tokens: 0,
      output_tokens: 0,
      total_tokens: 0,
      seconds_running: 0.0
    },
    rate_limits: nil
  }

  @active_snapshot %{
    generated_at: ~U[2026-01-15 10:00:00Z],
    counts: %{running: 2, retrying: 1},
    running: [
      %{
        issue_id: "abc123",
        issue_identifier: "MT-649",
        state: "In Progress",
        session_id: "thread-1-turn-1",
        turn_count: 7,
        last_event: :turn_completed,
        last_message: "Working on tests",
        started_at: ~U[2026-01-15 09:50:00Z],
        last_event_at: ~U[2026-01-15 09:59:00Z],
        tokens: %{input_tokens: 1200, output_tokens: 800, total_tokens: 2000}
      },
      %{
        issue_id: "def456",
        issue_identifier: "MT-650",
        state: "Todo",
        session_id: "thread-2-turn-1",
        turn_count: 3,
        last_event: :notification,
        last_message: "Refactoring module",
        started_at: ~U[2026-01-15 09:55:00Z],
        last_event_at: ~U[2026-01-15 09:58:00Z],
        tokens: %{input_tokens: 500, output_tokens: 300, total_tokens: 800}
      }
    ],
    retrying: [
      %{
        issue_id: "ghi789",
        issue_identifier: "MT-651",
        attempt: 3,
        due_at: ~U[2026-01-15 10:05:00Z],
        error: "turn_failed"
      }
    ],
    agent_totals: %{
      input_tokens: 5000,
      output_tokens: 2400,
      total_tokens: 7400,
      seconds_running: 1834.2
    },
    rate_limits: nil
  }

  describe "render/1" do
    test "renders valid HTML for empty snapshot" do
      html = Dashboard.render(@empty_snapshot)
      assert is_binary(html)
      assert String.contains?(html, "<!DOCTYPE html>")
      assert String.contains?(html, "Symphony")
      assert String.contains?(html, "No running sessions")
      assert String.contains?(html, "No retries queued")
    end

    test "renders running sessions table" do
      html = Dashboard.render(@active_snapshot)
      assert String.contains?(html, "MT-649")
      assert String.contains?(html, "MT-650")
      assert String.contains?(html, "In Progress")
      assert String.contains?(html, "Working on tests")
    end

    test "renders retry queue table" do
      html = Dashboard.render(@active_snapshot)
      assert String.contains?(html, "MT-651")
      assert String.contains?(html, "turn_failed")
    end

    test "renders aggregate totals" do
      html = Dashboard.render(@active_snapshot)
      assert String.contains?(html, "7,400")
      assert String.contains?(html, "Input Tokens")
      assert String.contains?(html, "Runtime")
    end

    test "escapes HTML entities" do
      snapshot = %{
        @empty_snapshot
        | running: [
            %{
              issue_id: "1",
              issue_identifier: "<script>alert('xss')</script>",
              state: "Test",
              session_id: nil,
              turn_count: 0,
              last_event: nil,
              last_message: nil,
              started_at: nil,
              last_event_at: nil,
              tokens: nil
            }
          ],
          counts: %{running: 1, retrying: 0}
      }

      html = Dashboard.render(snapshot)
      refute String.contains?(html, "<script>")
      assert String.contains?(html, "&lt;script&gt;")
    end

    test "includes auto-refresh meta tag" do
      html = Dashboard.render(@empty_snapshot)
      assert String.contains?(html, ~s(http-equiv="refresh"))
    end

    test "includes prominent board link in topbar" do
      html = Dashboard.render(@empty_snapshot)
      assert String.contains?(html, "dash-topbar")
      assert String.contains?(html, ~s(href="/board"))
      assert String.contains?(html, "Board")
    end

    test "renders rate limits when present" do
      snapshot = %{@active_snapshot | rate_limits: %{"remaining" => 100, "limit" => 1000}}
      html = Dashboard.render(snapshot)
      assert String.contains?(html, "Rate Limits")
      assert String.contains?(html, "remaining")
    end
  end
end

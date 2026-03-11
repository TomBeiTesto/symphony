defmodule SymphonyElixir.Orchestrator.DispatchTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.{Config, Issue}
  alias SymphonyElixir.Orchestrator.{Dispatch, State}

  @config_map %{
    "tracker" => %{
      "kind" => "local",
      "project_slug" => "test",
      "api_key" => "key",
      "active_states" => ["Todo", "In Progress"],
      "terminal_states" => ["Done", "Closed"]
    },
    "agent" => %{
      "max_concurrent_agents" => 3,
      "max_concurrent_agents_by_state" => %{"In Progress" => 2}
    }
  }

  setup do
    {:ok, config} = Config.from_workflow(@config_map)
    %{config: config}
  end

  defp make_issue(id, identifier, state, opts \\ []) do
    %Issue{
      id: id,
      identifier: identifier,
      title: "Issue #{identifier}",
      state: state,
      priority: Keyword.get(opts, :priority),
      created_at: Keyword.get(opts, :created_at),
      labels: Keyword.get(opts, :labels, []),
      blocked_by: Keyword.get(opts, :blocked_by, [])
    }
  end

  describe "select_dispatchable/3" do
    test "returns eligible candidates sorted by priority", %{config: config} do
      candidates = [
        make_issue("3", "MT-3", "Todo", priority: 3),
        make_issue("1", "MT-1", "In Progress", priority: 1),
        make_issue("2", "MT-2", "Todo", priority: 2)
      ]

      state = %State{}
      result = Dispatch.select_dispatchable(config, state, candidates)

      assert length(result) == 3
      assert Enum.map(result, & &1.identifier) == ["MT-1", "MT-2", "MT-3"]
    end

    test "excludes already running issues", %{config: config} do
      issue = make_issue("1", "MT-1", "In Progress", priority: 1)
      entry = State.new_running_entry(issue, nil)
      state = State.add_running(%State{}, "1", entry)

      candidates = [issue, make_issue("2", "MT-2", "Todo", priority: 2)]
      result = Dispatch.select_dispatchable(config, state, candidates)

      assert length(result) == 1
      assert hd(result).identifier == "MT-2"
    end

    test "excludes terminal state issues", %{config: config} do
      candidates = [
        make_issue("1", "MT-1", "Done"),
        make_issue("2", "MT-2", "In Progress")
      ]

      result = Dispatch.select_dispatchable(config, %State{}, candidates)
      assert length(result) == 1
      assert hd(result).identifier == "MT-2"
    end

    test "excludes issues without required fields", %{config: config} do
      candidates = [
        %Issue{id: "", identifier: "MT-1", title: "T", state: "Todo"},
        make_issue("2", "MT-2", "In Progress")
      ]

      result = Dispatch.select_dispatchable(config, %State{}, candidates)
      assert length(result) == 1
    end

    test "blocks Todo issues with non-terminal blockers", %{config: config} do
      candidates = [
        make_issue("1", "MT-1", "Todo",
          blocked_by: [%{id: "b1", identifier: "MT-0", state: "In Progress"}]
        ),
        make_issue("2", "MT-2", "Todo")
      ]

      result = Dispatch.select_dispatchable(config, %State{}, candidates)
      assert length(result) == 1
      assert hd(result).identifier == "MT-2"
    end

    test "allows Todo issues with only terminal blockers", %{config: config} do
      candidates = [
        make_issue("1", "MT-1", "Todo",
          blocked_by: [%{id: "b1", identifier: "MT-0", state: "Done"}]
        )
      ]

      result = Dispatch.select_dispatchable(config, %State{}, candidates)
      assert length(result) == 1
    end

    test "respects global concurrency limit", %{config: config} do
      # Config has max_concurrent_agents = 3
      issues =
        for i <- 1..3 do
          issue = make_issue("#{i}", "MT-#{i}", "In Progress")
          {issue, State.new_running_entry(issue, nil)}
        end

      state =
        Enum.reduce(issues, %State{}, fn {issue, entry}, s ->
          State.add_running(s, issue.id, entry)
        end)

      candidates = [make_issue("4", "MT-4", "Todo")]
      result = Dispatch.select_dispatchable(config, state, candidates)
      assert result == []
    end

    test "respects per-state concurrency limit", %{config: config} do
      # Config has max_concurrent_agents_by_state "in progress" => 2
      issues =
        for i <- 1..2 do
          issue = make_issue("#{i}", "MT-#{i}", "In Progress")
          {issue, State.new_running_entry(issue, nil)}
        end

      state =
        Enum.reduce(issues, %State{}, fn {issue, entry}, s ->
          State.add_running(s, issue.id, entry)
        end)

      candidates = [make_issue("3", "MT-3", "In Progress")]
      result = Dispatch.select_dispatchable(config, state, candidates)
      assert result == []
    end
  end

  describe "sort_by_priority/1" do
    test "sorts by priority asc, created_at asc, identifier asc" do
      now = DateTime.utc_now()
      earlier = DateTime.add(now, -3600)

      issues = [
        make_issue("3", "MT-3", "Todo", priority: 3, created_at: now),
        make_issue("1", "MT-1", "Todo", priority: 1, created_at: now),
        make_issue("2", "MT-2", "Todo", priority: 1, created_at: earlier),
        make_issue("4", "MT-4", "Todo", priority: nil, created_at: now)
      ]

      sorted = Dispatch.sort_by_priority(issues)
      identifiers = Enum.map(sorted, & &1.identifier)

      # priority 1 (earlier comes first), then priority 3, then nil
      assert identifiers == ["MT-2", "MT-1", "MT-3", "MT-4"]
    end
  end
end

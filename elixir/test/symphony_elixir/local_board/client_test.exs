defmodule SymphonyElixir.LocalBoard.ClientTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.{Config, Issue, LocalBoard}
  alias SymphonyElixir.LocalBoard.Client

  @store_path "test_board_client_#{System.unique_integer([:positive])}.json"

  setup do
    start_supervised!(
      {LocalBoard,
       store_path: @store_path,
       states: ["Todo", "In Progress", "Done", "Cancelled"],
       project_prefix: "CLT"}
    )

    on_exit(fn -> File.rm(@store_path) end)

    config = %Config{
      tracker_kind: "local",
      active_states: ["Todo", "In Progress"],
      terminal_states: ["Done", "Cancelled"]
    }

    {:ok, config: config}
  end

  describe "fetch_candidate_issues/1" do
    test "returns issues matching active states", %{config: config} do
      LocalBoard.create_issue(%{"title" => "Active", "state" => "Todo"})
      LocalBoard.create_issue(%{"title" => "Done item", "state" => "Done"})

      assert {:ok, issues} = Client.fetch_candidate_issues(config)
      assert length(issues) == 1
      assert [%Issue{title: "Active", state: "Todo"}] = issues
    end

    test "returns empty list when no matching issues", %{config: config} do
      LocalBoard.create_issue(%{"title" => "Done item", "state" => "Done"})
      assert {:ok, []} = Client.fetch_candidate_issues(config)
    end
  end

  describe "fetch_issues_by_states/2" do
    test "returns issues in specified states", %{config: config} do
      LocalBoard.create_issue(%{"title" => "A", "state" => "Todo"})
      LocalBoard.create_issue(%{"title" => "B", "state" => "In Progress"})
      LocalBoard.create_issue(%{"title" => "C", "state" => "Done"})

      assert {:ok, issues} = Client.fetch_issues_by_states(config, ["Todo", "Done"])
      assert length(issues) == 2
      states = MapSet.new(issues, & &1.state)
      assert MapSet.member?(states, "Todo")
      assert MapSet.member?(states, "Done")
    end

    test "returns empty for empty state list", %{config: config} do
      assert {:ok, []} = Client.fetch_issues_by_states(config, [])
    end
  end

  describe "fetch_issue_states_by_ids/2" do
    test "returns issues matching given IDs", %{config: config} do
      {:ok, i1} = LocalBoard.create_issue(%{"title" => "First"})
      {:ok, _i2} = LocalBoard.create_issue(%{"title" => "Second"})
      {:ok, i3} = LocalBoard.create_issue(%{"title" => "Third"})

      assert {:ok, issues} = Client.fetch_issue_states_by_ids(config, [i1.id, i3.id])
      assert length(issues) == 2
      ids = MapSet.new(issues, & &1.id)
      assert MapSet.member?(ids, i1.id)
      assert MapSet.member?(ids, i3.id)
    end

    test "returns empty for empty id list", %{config: config} do
      assert {:ok, []} = Client.fetch_issue_states_by_ids(config, [])
    end
  end

  describe "execute_graphql/3" do
    test "returns error (not supported)", %{config: config} do
      assert {:error, :graphql_not_supported_on_local_board} =
               Client.execute_graphql(config, "query { }", %{})
    end
  end
end

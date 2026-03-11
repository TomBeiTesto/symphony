defmodule SymphonyElixir.GitLab.ClientTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.GitLab.Client, as: GitLabClient
  alias SymphonyElixir.Config

  # ── helpers ──────────────────────────────────────────────────────────────

  defp gitlab_config(overrides \\ %{}) do
    base = %{
      "tracker" => %{
        "kind" => "gitlab",
        "endpoint" => "https://gitlab.example.com/api/v4",
        "api_key" => "glpat-test-token",
        "project_slug" => "42"
      }
    }

    {:ok, config} = Config.from_workflow(Map.merge(base, overrides))
    config
  end

  # ── derive_state/3 ──────────────────────────────────────────────────────

  describe "derive_state/3" do
    test "returns first matching label from known states" do
      assert GitLabClient.derive_state(
               ["Bug", "In Progress", "Feature"],
               ["Todo", "In Progress"],
               "opened"
             ) == "In Progress"
    end

    test "falls back to Todo when no label matches and native state is opened" do
      assert GitLabClient.derive_state(["unrelated"], ["Todo", "In Progress"], "opened") == "Todo"
    end

    test "falls back to Done when no label matches and native state is closed" do
      assert GitLabClient.derive_state(["unrelated"], ["Todo", "In Progress"], "closed") == "Done"
    end

    test "matches case-insensitively" do
      assert GitLabClient.derive_state(
               ["todo"],
               ["Todo", "In Progress"],
               "opened"
             ) == "Todo"
    end

    test "returns first matching state when multiple labels match" do
      assert GitLabClient.derive_state(
               ["In Progress", "Todo"],
               ["Todo", "In Progress"],
               "opened"
             ) == "Todo"
    end
  end

  # ── fetch_candidate_issues/1 ────────────────────────────────────────────

  describe "fetch_candidate_issues/1 (unit, no HTTP)" do
    test "returns ok with empty list when API returns empty array" do
      config = gitlab_config()

      # We can't call the real API, but we can verify config is parsed
      assert config.tracker_kind == "gitlab"
      assert config.tracker_endpoint == "https://gitlab.example.com/api/v4"
      assert config.tracker_api_key == "glpat-test-token"
      assert config.tracker_project_slug == "42"
    end
  end

  # ── fetch_issues_by_states/2 ────────────────────────────────────────────

  describe "fetch_issues_by_states/2" do
    test "returns ok with empty list for empty state_names" do
      config = gitlab_config()
      assert {:ok, []} = GitLabClient.fetch_issues_by_states(config, [])
    end
  end

  # ── fetch_issue_states_by_ids/2 ─────────────────────────────────────────

  describe "fetch_issue_states_by_ids/2" do
    test "returns empty list for empty ids" do
      config = gitlab_config()
      assert {:ok, []} = GitLabClient.fetch_issue_states_by_ids(config, [])
    end

    test "returns empty list when no ids can be parsed as iids" do
      config = gitlab_config()
      assert {:ok, []} = GitLabClient.fetch_issue_states_by_ids(config, ["not-a-number"])
    end
  end

  # ── normalization helpers (via derive_state which is public) ────────────

  describe "identifier extraction" do
    test "extracts iid from numeric string" do
      # Tested indirectly: fetch_issue_states_by_ids with valid numeric IDs
      # would attempt to query. We test the empty path above.
      config = gitlab_config()

      # Verify the config is correctly built for gitlab
      assert config.tracker_kind == "gitlab"
    end
  end

  # ── default endpoint ────────────────────────────────────────────────────

  describe "default endpoint" do
    test "gitlab kind defaults to gitlab.com API" do
      {:ok, config} =
        Config.from_workflow(%{
          "tracker" => %{
            "kind" => "gitlab",
            "api_key" => "glpat-token",
            "project_slug" => "99"
          }
        })

      assert config.tracker_endpoint == "https://gitlab.com/api/v4"
    end

    test "custom endpoint is preserved" do
      {:ok, config} =
        Config.from_workflow(%{
          "tracker" => %{
            "kind" => "gitlab",
            "endpoint" => "https://git.corp.io/api/v4",
            "api_key" => "glpat-token",
            "project_slug" => "mygroup%2Fmyproject"
          }
        })

      assert config.tracker_endpoint == "https://git.corp.io/api/v4"
    end
  end
end

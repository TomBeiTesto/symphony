defmodule SymphonyElixir.ConfigTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Config

  @minimal_config %{
    "tracker" => %{
      "kind" => "gitlab",
      "project_slug" => "my-project",
      "api_key" => "test-key"
    }
  }

  @full_config %{
    "tracker" => %{
      "kind" => "gitlab",
      "endpoint" => "https://gitlab.example.com/api/v4",
      "api_key" => "my-api-key",
      "project_slug" => "test-slug",
      "active_states" => ["Todo", "In Progress", "In Review"],
      "terminal_states" => ["Done", "Closed"]
    },
    "polling" => %{"interval_ms" => 60_000},
    "workspace" => %{"root" => "/tmp/test_workspaces"},
    "hooks" => %{
      "after_create" => "git clone repo",
      "before_run" => "npm install",
      "timeout_ms" => 120_000,
      "shell" => "/bin/bash"
    },
    "agent" => %{
      "max_concurrent_agents" => 5,
      "max_turns" => 10,
      "max_retry_backoff_ms" => 60_000,
      "max_concurrent_agents_by_state" => %{
        "In Progress" => 3,
        "Todo" => 2
      }
    },
    "agent_process" => %{
      "command" => "my-agent",
      "turn_timeout_ms" => 1_800_000,
      "read_timeout_ms" => 10_000,
      "stall_timeout_ms" => 600_000
    },
    "server" => %{"port" => 4000}
  }

  describe "from_workflow/1" do
    test "creates config with defaults from minimal input" do
      assert {:ok, config} = Config.from_workflow(@minimal_config)
      assert config.tracker_kind == "gitlab"
      assert config.tracker_project_slug == "my-project"
      assert config.tracker_api_key == "test-key"
      assert config.tracker_endpoint == "https://gitlab.com/api/v4"
      assert config.active_states == ["Todo", "In Progress"]

      assert config.terminal_states == [
               "Closed",
               "Cancelled",
               "Canceled",
               "Duplicate",
               "Done",
               "Review",
               "Archived"
             ]

      assert config.poll_interval_ms == 30_000
      assert config.max_concurrent_agents == 10
      assert config.max_turns == 20
      assert config.max_retry_backoff_ms == 300_000
      assert config.agent_command == "agent-server"
      assert config.turn_timeout_ms == 3_600_000
      assert config.read_timeout_ms == 5_000
      assert config.stall_timeout_ms == 600_000
      assert config.hooks.timeout_ms == 60_000
      assert config.server_port == nil
    end

    test "creates config with all custom values" do
      assert {:ok, config} = Config.from_workflow(@full_config)
      assert config.tracker_endpoint == "https://gitlab.example.com/api/v4"
      assert config.active_states == ["Todo", "In Progress", "In Review"]
      assert config.terminal_states == ["Done", "Closed"]
      assert config.poll_interval_ms == 60_000
      assert config.max_concurrent_agents == 5
      assert config.max_turns == 10
      assert config.max_retry_backoff_ms == 60_000
      assert config.agent_command == "my-agent"
      assert config.turn_timeout_ms == 1_800_000
      assert config.read_timeout_ms == 10_000
      assert config.stall_timeout_ms == 600_000
      assert config.hooks.after_create == "git clone repo"
      assert config.hooks.before_run == "npm install"
      assert config.hooks.timeout_ms == 120_000
      assert config.hooks.shell == "/bin/bash"
      assert config.server_port == 4000
      assert config.max_concurrent_agents_by_state["in progress"] == 3
      assert config.max_concurrent_agents_by_state["todo"] == 2
    end

    test "falls back to codex key for backward compatibility" do
      config_map = %{
        "tracker" => %{"kind" => "gitlab", "project_slug" => "proj", "api_key" => "key"},
        "codex" => %{"command" => "codex-agent"}
      }

      assert {:ok, config} = Config.from_workflow(config_map)
      assert config.agent_command == "codex-agent"
    end

    test "agent_process takes precedence over codex" do
      config_map = %{
        "tracker" => %{"kind" => "gitlab", "project_slug" => "proj", "api_key" => "key"},
        "codex" => %{"command" => "old-agent"},
        "agent_process" => %{"command" => "new-agent"}
      }

      assert {:ok, config} = Config.from_workflow(config_map)
      assert config.agent_command == "new-agent"
    end

    test "resolves $VAR syntax for api_key" do
      System.put_env("TEST_GITLAB_KEY_9382", "resolved-key")
      on_exit(fn -> System.delete_env("TEST_GITLAB_KEY_9382") end)

      config_map = %{
        "tracker" => %{
          "kind" => "gitlab",
          "project_slug" => "proj",
          "api_key" => "$TEST_GITLAB_KEY_9382"
        }
      }

      assert {:ok, config} = Config.from_workflow(config_map)
      assert config.tracker_api_key == "resolved-key"
    end

    test "workspace root defaults to system temp" do
      assert {:ok, config} = Config.from_workflow(@minimal_config)
      assert String.contains?(config.workspace_root, "symphony_workspaces")
    end

    test "parses comma-separated state strings" do
      config_map = %{
        "tracker" => %{
          "kind" => "gitlab",
          "project_slug" => "proj",
          "api_key" => "key",
          "active_states" => "Todo, In Progress, Custom State"
        }
      }

      assert {:ok, config} = Config.from_workflow(config_map)
      assert config.active_states == ["Todo", "In Progress", "Custom State"]
    end
  end

  describe "validate_dispatch/1" do
    test "returns :ok for valid config" do
      assert {:ok, config} = Config.from_workflow(@minimal_config)
      assert :ok = Config.validate_dispatch(config)
    end

    test "returns error for missing tracker kind" do
      assert {:ok, config} = Config.from_workflow(%{})
      assert {:error, :missing_tracker_kind} = Config.validate_dispatch(config)
    end

    test "returns error for unsupported tracker kind" do
      assert {:ok, config} = Config.from_workflow(%{"tracker" => %{"kind" => "jira"}})
      assert {:error, :unsupported_tracker_kind} = Config.validate_dispatch(config)
    end

    test "returns error for missing api key" do
      assert {:ok, config} =
               Config.from_workflow(%{
                 "tracker" => %{"kind" => "gitlab", "project_slug" => "proj"}
               })

      # Only fails if no env fallback
      if is_nil(System.get_env("GITLAB_API_TOKEN")) do
        assert {:error, :missing_tracker_api_key} = Config.validate_dispatch(config)
      end
    end

    test "returns error for missing project slug" do
      assert {:ok, config} =
               Config.from_workflow(%{
                 "tracker" => %{"kind" => "gitlab", "api_key" => "key"}
               })

      assert {:error, :missing_tracker_project_slug} = Config.validate_dispatch(config)
    end

    # --- GitLab validation ---

    test "returns :ok for valid gitlab config" do
      assert {:ok, config} =
               Config.from_workflow(%{
                 "tracker" => %{
                   "kind" => "gitlab",
                   "api_key" => "glpat-token",
                   "project_slug" => "42"
                 }
               })

      assert :ok = Config.validate_dispatch(config)
    end

    test "gitlab accepts as valid tracker kind" do
      assert {:ok, config} =
               Config.from_workflow(%{
                 "tracker" => %{
                   "kind" => "gitlab",
                   "api_key" => "glpat-tok",
                   "project_slug" => "my/proj"
                 }
               })

      refute {:error, :unsupported_tracker_kind} == Config.validate_dispatch(config)
    end

    test "returns error for gitlab missing api key" do
      assert {:ok, config} =
               Config.from_workflow(%{
                 "tracker" => %{"kind" => "gitlab", "project_slug" => "42"}
               })

      if is_nil(System.get_env("GITLAB_API_TOKEN")) do
        assert {:error, :missing_tracker_api_key} = Config.validate_dispatch(config)
      end
    end

    test "returns error for gitlab missing project slug" do
      assert {:ok, config} =
               Config.from_workflow(%{
                 "tracker" => %{"kind" => "gitlab", "api_key" => "glpat-token"}
               })

      assert {:error, :missing_tracker_project_slug} = Config.validate_dispatch(config)
    end

    test "gitlab resolves GITLAB_API_TOKEN env var" do
      System.put_env("GITLAB_API_TOKEN", "env-gitlab-token")
      on_exit(fn -> System.delete_env("GITLAB_API_TOKEN") end)

      assert {:ok, config} =
               Config.from_workflow(%{
                 "tracker" => %{"kind" => "gitlab", "project_slug" => "42"}
               })

      assert config.tracker_api_key == "env-gitlab-token"
    end

    test "gitlab defaults endpoint to gitlab.com" do
      assert {:ok, config} =
               Config.from_workflow(%{
                 "tracker" => %{
                   "kind" => "gitlab",
                   "api_key" => "tok",
                   "project_slug" => "42"
                 }
               })

      assert config.tracker_endpoint == "https://gitlab.com/api/v4"
    end
  end

  describe "active_state_set/1 and terminal_state_set/1" do
    test "returns normalized state sets" do
      assert {:ok, config} = Config.from_workflow(@minimal_config)
      active = Config.active_state_set(config)
      terminal = Config.terminal_state_set(config)

      assert MapSet.member?(active, "todo")
      assert MapSet.member?(active, "in progress")
      assert MapSet.member?(terminal, "closed")
      assert MapSet.member?(terminal, "done")
    end
  end
end

defmodule SymphonyElixir.WorkspaceTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.{Config, Issue, Workspace}

  setup do
    test_root = Path.join(System.tmp_dir!(), "symphony_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(test_root)
    on_exit(fn -> File.rm_rf!(test_root) end)

    {:ok, config} =
      Config.from_workflow(%{
        "tracker" => %{"kind" => "local", "project_slug" => "test", "api_key" => "key"},
        "workspace" => %{"root" => test_root}
      })

    issue = %Issue{
      id: "issue-1",
      identifier: "MT-100",
      title: "Test issue",
      state: "In Progress"
    }

    %{config: config, issue: issue, test_root: test_root}
  end

  describe "ensure_workspace/2" do
    test "creates workspace directory for issue", %{config: config, issue: issue, test_root: root} do
      assert {:ok, %{path: path, created_now: true}} = Workspace.ensure_workspace(config, issue)
      assert String.contains?(path, "MT-100")
      assert File.dir?(path)
      assert String.starts_with?(Path.expand(path), Path.expand(root))
    end

    test "reuses existing workspace", %{config: config, issue: issue} do
      assert {:ok, %{path: path1, created_now: true}} = Workspace.ensure_workspace(config, issue)
      assert {:ok, %{path: path2, created_now: false}} = Workspace.ensure_workspace(config, issue)
      assert path1 == path2
    end

    test "workspace path uses sanitized identifier", %{config: config, issue: issue} do
      {:ok, %{path: path}} = Workspace.ensure_workspace(config, issue)
      basename = Path.basename(path)
      assert basename == "MT-100"
    end

    test "runs after_create hook on new workspace", %{test_root: root, issue: issue} do
      {:ok, hook_config} =
        Config.from_workflow(%{
          "tracker" => %{"kind" => "local", "project_slug" => "test", "api_key" => "key"},
          "workspace" => %{"root" => root},
          "hooks" => %{"after_create" => "echo hook_ran"}
        })

      assert {:ok, %{created_now: true}} = Workspace.ensure_workspace(hook_config, issue)
    end

    test "fails when after_create hook fails and cleans up", %{test_root: root, issue: issue} do
      {:ok, hook_config} =
        Config.from_workflow(%{
          "tracker" => %{"kind" => "local", "project_slug" => "test", "api_key" => "key"},
          "workspace" => %{"root" => root},
          "hooks" => %{"after_create" => "exit 1"}
        })

      assert {:error, {:hook_failed, :after_create, _}} =
               Workspace.ensure_workspace(hook_config, issue)

      # workspace should be cleaned up on hook failure
      ws_path = Workspace.workspace_path(hook_config, Issue.workspace_key(issue))
      refute File.dir?(ws_path)
    end

    test "rejects issue with unsafe identifier", %{config: config} do
      bad_issue = %Issue{
        id: "issue-bad",
        identifier: "../../etc/passwd",
        title: "Bad Issue",
        state: "Todo"
      }

      # The identifier gets sanitized by Issue.workspace_key, so the sanitized
      # key ".._.._etc_passwd" should still be valid characters but may fail
      # path validation depending on expansion. Verify it does not escape root.
      case Workspace.ensure_workspace(config, bad_issue) do
        {:ok, %{path: path}} ->
          # If it succeeds, the path must be under the workspace root
          root_normalized =
            config.workspace_root
            |> Path.expand()
            |> String.replace("\\", "/")
            |> String.downcase()

          path_normalized =
            path |> String.replace("\\", "/") |> String.downcase()

          assert String.starts_with?(path_normalized, root_normalized)

        {:error, _} ->
          # Rejection is also acceptable for unsafe identifiers
          assert true
      end
    end
  end

  describe "remove_workspace/2" do
    test "removes existing workspace", %{config: config, issue: issue} do
      {:ok, %{path: path}} = Workspace.ensure_workspace(config, issue)
      assert File.dir?(path)

      workspace_key = Issue.workspace_key(issue)
      assert :ok = Workspace.remove_workspace(config, workspace_key)
      refute File.dir?(path)
    end

    test "succeeds when workspace doesn't exist", %{config: config} do
      assert :ok = Workspace.remove_workspace(config, "nonexistent-key")
    end

    test "runs before_remove hook before removal", %{test_root: root, issue: issue} do
      {:ok, base_config} =
        Config.from_workflow(%{
          "tracker" => %{"kind" => "local", "project_slug" => "test", "api_key" => "key"},
          "workspace" => %{"root" => root}
        })

      {:ok, %{path: path}} = Workspace.ensure_workspace(base_config, issue)
      assert File.dir?(path)

      {:ok, hook_config} =
        Config.from_workflow(%{
          "tracker" => %{"kind" => "local", "project_slug" => "test", "api_key" => "key"},
          "workspace" => %{"root" => root},
          "hooks" => %{"before_remove" => "echo removing"}
        })

      ws_key = Issue.workspace_key(issue)
      assert :ok = Workspace.remove_workspace(hook_config, ws_key)
      refute File.dir?(path)
    end

    test "still removes workspace even when before_remove hook fails", %{
      test_root: root,
      issue: issue
    } do
      {:ok, base_config} =
        Config.from_workflow(%{
          "tracker" => %{"kind" => "local", "project_slug" => "test", "api_key" => "key"},
          "workspace" => %{"root" => root}
        })

      {:ok, %{path: path}} = Workspace.ensure_workspace(base_config, issue)
      assert File.dir?(path)

      {:ok, hook_config} =
        Config.from_workflow(%{
          "tracker" => %{"kind" => "local", "project_slug" => "test", "api_key" => "key"},
          "workspace" => %{"root" => root},
          "hooks" => %{"before_remove" => "exit 1"}
        })

      ws_key = Issue.workspace_key(issue)
      assert :ok = Workspace.remove_workspace(hook_config, ws_key)
      refute File.dir?(path)
    end

    test "removes workspace with files inside", %{config: config, issue: issue} do
      {:ok, %{path: path}} = Workspace.ensure_workspace(config, issue)
      File.write!(Path.join(path, "test_file.txt"), "content")
      File.mkdir_p!(Path.join(path, "subdir"))
      File.write!(Path.join(path, "subdir/nested.txt"), "nested")

      ws_key = Issue.workspace_key(issue)
      assert :ok = Workspace.remove_workspace(config, ws_key)
      refute File.dir?(path)
    end
  end

  describe "run_hook/3" do
    test "succeeds when no hook configured", %{config: config, test_root: root} do
      assert :ok = Workspace.run_hook(config, :after_create, root)
      assert :ok = Workspace.run_hook(config, :before_run, root)
      assert :ok = Workspace.run_hook(config, :after_run, root)
      assert :ok = Workspace.run_hook(config, :before_remove, root)
    end

    test "succeeds when hook script is empty string", %{test_root: root} do
      {:ok, config} =
        Config.from_workflow(%{
          "tracker" => %{"kind" => "local", "project_slug" => "test", "api_key" => "key"},
          "workspace" => %{"root" => root},
          "hooks" => %{"before_run" => ""}
        })

      assert :ok = Workspace.run_hook(config, :before_run, root)
    end

    test "executes a simple echo command", %{test_root: root} do
      {:ok, config} =
        Config.from_workflow(%{
          "tracker" => %{"kind" => "local", "project_slug" => "test", "api_key" => "key"},
          "workspace" => %{"root" => root},
          "hooks" => %{"before_run" => "echo hello"}
        })

      assert :ok = Workspace.run_hook(config, :before_run, root)
    end

    test "returns error for failing hook", %{test_root: root} do
      {:ok, config} =
        Config.from_workflow(%{
          "tracker" => %{"kind" => "local", "project_slug" => "test", "api_key" => "key"},
          "workspace" => %{"root" => root},
          "hooks" => %{"after_create" => "exit 1"}
        })

      assert {:error, _} = Workspace.run_hook(config, :after_create, root)
    end

    test "returns specific exit code on failure", %{test_root: root} do
      {:ok, config} =
        Config.from_workflow(%{
          "tracker" => %{"kind" => "local", "project_slug" => "test", "api_key" => "key"},
          "workspace" => %{"root" => root},
          "hooks" => %{"after_run" => "exit 42"}
        })

      assert {:error, {:exit_code, 42}} = Workspace.run_hook(config, :after_run, root)
    end

    @tag :skip_on_windows
    test "returns timeout error for slow command", %{test_root: root} do
      {:ok, config} =
        Config.from_workflow(%{
          "tracker" => %{"kind" => "local", "project_slug" => "test", "api_key" => "key"},
          "workspace" => %{"root" => root},
          "hooks" => %{"before_run" => "sleep 30", "timeout_ms" => 500}
        })

      assert {:error, :timeout} = Workspace.run_hook(config, :before_run, root)
    end
  end

  describe "path sanitization and validation" do
    test "valid_workspace_key? accepts alphanumeric with dashes and dots" do
      assert Workspace.valid_workspace_key?("TEST-42")
      assert Workspace.valid_workspace_key?("my.project-name_v2")
      assert Workspace.valid_workspace_key?("ABC123")
      assert Workspace.valid_workspace_key?("a")
    end

    test "valid_workspace_key? rejects special characters" do
      refute Workspace.valid_workspace_key?("has space")
      refute Workspace.valid_workspace_key?("has/slash")
      refute Workspace.valid_workspace_key?("has@special")
      refute Workspace.valid_workspace_key?("has\\backslash")
      refute Workspace.valid_workspace_key?("")
    end

    test "validate_workspace_path rejects path traversal", %{config: config} do
      traversal_path = Path.join([config.workspace_root, "..", "escape"])
      assert {:error, _} = Workspace.validate_workspace_path(config, traversal_path)
    end

    test "validate_workspace_path rejects paths outside root", %{config: config} do
      assert {:error, :workspace_outside_root} =
               Workspace.validate_workspace_path(config, "/some/other/location/evil")
    end

    test "validate_workspace_path rejects invalid key characters" do
      {:ok, config} =
        Config.from_workflow(%{
          "tracker" => %{"kind" => "local", "project_slug" => "test", "api_key" => "key"},
          "workspace" => %{"root" => "/tmp/test_root"}
        })

      path = Path.join("/tmp/test_root", "bad key with spaces")
      assert {:error, :invalid_workspace_key} = Workspace.validate_workspace_path(config, path)
    end

    test "validate_workspace_path accepts valid path under root", %{
      config: config,
      test_root: root
    } do
      valid_path = Path.join(root, "TEST-42")
      assert :ok = Workspace.validate_workspace_path(config, valid_path)
    end
  end

  describe "workspace_path/2" do
    test "computes correct path under root", %{config: config} do
      path = Workspace.workspace_path(config, "MT-100")
      assert String.ends_with?(path, "MT-100")
    end

    test "returns an expanded absolute path", %{config: config} do
      path = Workspace.workspace_path(config, "MY-KEY")
      assert Path.type(path) == :absolute
    end
  end
end

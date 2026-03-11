defmodule SymphonyElixir.WorkspaceTest do
  use ExUnit.Case, async: true

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
      assert {:ok, %{path: path, created_now: _}} = Workspace.ensure_workspace(config, issue)
      assert String.contains?(path, "MT-100")
      assert File.dir?(path)
      assert String.starts_with?(Path.expand(path), Path.expand(root))
    end

    test "reuses existing workspace", %{config: config, issue: issue} do
      assert {:ok, %{path: path1}} = Workspace.ensure_workspace(config, issue)
      # Slight delay to ensure mtime is different
      Process.sleep(100)
      assert {:ok, %{path: path2, created_now: false}} = Workspace.ensure_workspace(config, issue)
      assert path1 == path2
    end
  end

  describe "workspace_path/2" do
    test "computes correct path under root", %{config: config} do
      path = Workspace.workspace_path(config, "MT-100")
      assert String.ends_with?(path, "MT-100")
    end
  end

  describe "validate_workspace_path/2" do
    test "accepts valid path under root", %{config: config, test_root: root} do
      path = Path.join(root, "valid-key")
      assert :ok = Workspace.validate_workspace_path(config, path)
    end

    test "rejects path outside root", %{config: config} do
      path = "/some/other/location/evil"
      assert {:error, :workspace_outside_root} = Workspace.validate_workspace_path(config, path)
    end

    test "rejects invalid workspace key characters" do
      {:ok, config} =
        Config.from_workflow(%{
          "tracker" => %{"kind" => "local", "project_slug" => "test", "api_key" => "key"},
          "workspace" => %{"root" => "/tmp/test_root"}
        })

      path = Path.join("/tmp/test_root", "bad key with spaces")
      assert {:error, :invalid_workspace_key} = Workspace.validate_workspace_path(config, path)
    end
  end

  describe "valid_workspace_key?/1" do
    test "accepts valid keys" do
      assert Workspace.valid_workspace_key?("MT-100")
      assert Workspace.valid_workspace_key?("abc.123_test")
      assert Workspace.valid_workspace_key?("SIMPLE")
    end

    test "rejects invalid keys" do
      refute Workspace.valid_workspace_key?("has spaces")
      refute Workspace.valid_workspace_key?("has/slash")
      refute Workspace.valid_workspace_key?("has@special")
      refute Workspace.valid_workspace_key?("")
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
  end

  describe "run_hook/3" do
    test "succeeds when no hook configured", %{config: config, test_root: root} do
      assert :ok = Workspace.run_hook(config, :after_create, root)
    end

    test "succeeds with a valid hook script", %{test_root: root} do
      script =
        case :os.type() do
          {:win32, _} -> "echo hello"
          _ -> "echo hello"
        end

      {:ok, config} =
        Config.from_workflow(%{
          "tracker" => %{"kind" => "local", "project_slug" => "test", "api_key" => "key"},
          "workspace" => %{"root" => root},
          "hooks" => %{"before_run" => script}
        })

      assert :ok = Workspace.run_hook(config, :before_run, root)
    end

    test "returns error for failing hook", %{test_root: root} do
      script =
        case :os.type() do
          {:win32, _} -> "exit /b 1"
          _ -> "exit 1"
        end

      {:ok, config} =
        Config.from_workflow(%{
          "tracker" => %{"kind" => "local", "project_slug" => "test", "api_key" => "key"},
          "workspace" => %{"root" => root},
          "hooks" => %{"after_create" => script}
        })

      assert {:error, _} = Workspace.run_hook(config, :after_create, root)
    end
  end
end

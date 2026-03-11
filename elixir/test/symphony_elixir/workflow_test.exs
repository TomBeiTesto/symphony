defmodule SymphonyElixir.WorkflowTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow

  @valid_workflow """
  ---
  tracker:
    kind: local
    project_slug: my-project
    api_key: $GITLAB_API_TOKEN
  agent_process:
    command: agent-server
  ---
  You are an AI assistant working on {{ issue.identifier }}: {{ issue.title }}.
  """

  @legacy_codex_workflow """
  ---
  tracker:
    kind: local
    project_slug: my-project
  codex:
    command: codex --config some_flag
  ---
  Work on {{ issue.identifier }}.
  """

  describe "parse/1" do
    test "parses valid workflow with YAML front matter and prompt body" do
      assert {:ok, %{config: config, prompt_template: prompt}} = Workflow.parse(@valid_workflow)
      assert config["tracker"]["kind"] == "local"
      assert config["tracker"]["project_slug"] == "my-project"
      assert config["agent_process"]["command"] == "agent-server"
      assert String.contains?(prompt, "{{ issue.identifier }}")
    end

    test "parses legacy codex key in front matter" do
      assert {:ok, %{config: config, prompt_template: prompt}} =
               Workflow.parse(@legacy_codex_workflow)

      assert config["codex"]["command"] == "codex --config some_flag"
      assert String.contains?(prompt, "{{ issue.identifier }}")
    end

    test "returns prompt-only for input without front matter delimiters" do
      assert {:ok, %{config: config, prompt_template: prompt}} =
               Workflow.parse("no front matter here")

      assert config == %{}
      assert prompt == "no front matter here"
    end

    test "handles empty prompt body" do
      workflow = """
      ---
      tracker:
        kind: local
      ---
      """

      assert {:ok, %{prompt_template: prompt}} = Workflow.parse(workflow)
      assert String.trim(prompt) == ""
    end

    test "handles complex YAML with nested structures" do
      workflow = """
      ---
      tracker:
        kind: local
        active_states:
          - Todo
          - In Progress
      hooks:
        after_create: "git clone repo"
      ---
      Prompt text here.
      """

      assert {:ok, %{config: config}} = Workflow.parse(workflow)
      assert config["tracker"]["active_states"] == ["Todo", "In Progress"]
      assert config["hooks"]["after_create"] == "git clone repo"
    end
  end

  describe "load/1" do
    test "loads workflow from file" do
      path = Path.join(System.tmp_dir!(), "test_workflow_#{:rand.uniform(100_000)}.md")

      File.write!(path, @valid_workflow)

      on_exit(fn -> File.rm(path) end)

      assert {:ok, %{config: config, prompt_template: prompt}} = Workflow.load(path)
      assert config["tracker"]["kind"] == "local"
      assert String.contains?(prompt, "{{ issue.identifier }}")
    end

    test "returns error for missing file" do
      assert {:error, _} = Workflow.load("/nonexistent/workflow.md")
    end
  end
end

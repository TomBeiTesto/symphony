defmodule SymphonyElixir.Orchestrator.Worker do
  @moduledoc """
  Worker dispatch and execution logic for the orchestrator.

  Handles dispatching issues to worker tasks, running agent sessions,
  workspace resolution, prompt rendering, and agent session management.
  """

  require Logger

  alias SymphonyElixir.{Config, Issue, Prompt, Workspace}
  alias SymphonyElixir.AppServer.Client, as: AppServerClient
  alias SymphonyElixir.AppServer.ClaudeAdapter
  alias SymphonyElixir.Orchestrator.State

  @doc "Dispatch a single issue: claim it, add to running, and spawn a worker task."
  def dispatch_issue(state, config, %Issue{} = issue) do
    Logger.info("Dispatching issue=#{issue.identifier} state=#{issue.state}")

    orchestrator_pid = self()
    issue_id = issue.id
    identifier = issue.identifier

    # Move to "In Progress" on local board
    if config.tracker_kind == "local" do
      SymphonyElixir.LocalBoard.move_issue(issue_id, "In Progress")
    end

    # Claim the issue
    state = %{state | claimed: MapSet.put(state.claimed, issue_id)}

    # Add to running
    state = State.add_running(state, issue_id, State.new_running_entry(issue, nil))

    # Spawn worker task
    Task.start(fn ->
      result = run_worker(config, state.prompt_template, issue, orchestrator_pid)
      send(orchestrator_pid, {:worker_done, issue_id, result})
    end)

    Logger.metadata(issue_id: issue_id, issue_identifier: identifier)
    state
  end

  @doc "Run the worker: set up workspace, render prompt, start agent session, run turn loop."
  def run_worker(config, prompt_template, issue, orchestrator_pid) do
    with {:ok, workspace_info} <- Workspace.ensure_workspace(config, issue),
         workspace_path = resolve_project_workspace(config, issue, workspace_info.path),
         :ok <- run_before_run_hook(config, workspace_path),
         {:ok, prompt} <- render_prompt(prompt_template, issue, nil),
         :ok <- validate_cwd(workspace_path) do
      callback = fn event ->
        send(orchestrator_pid, {:agent_event, issue.id, event})
        :ok
      end

      client = agent_client_module()

      case client.start_session(config, workspace_path, prompt, callback) do
        {:ok, session} ->
          result = run_turn_loop(config, prompt_template, issue, session, 1)

          # after_run hook (failure ignored per spec)
          Workspace.run_hook(config, :after_run, workspace_path)

          result

        {:error, reason} ->
          {:error, {:startup_failed, reason}}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Run the agent turn loop until completion, failure, or cancellation."
  def run_turn_loop(_config, _prompt_template, _issue, session, turn_count) do
    client = agent_client_module()

    case client.stream_turn(session) do
      {:ok, :completed, session} ->
        client.stop(session)
        {:ok, {:completed_after_turns, turn_count, nil}}

      {:ok, :failed, session} ->
        client.stop(session)
        {:error, {:turn_failed, turn_count}}

      {:ok, :cancelled, session} ->
        client.stop(session)
        {:error, {:turn_cancelled, turn_count}}

      {:error, reason} ->
        client.stop(session)
        {:error, {reason, turn_count}}
    end
  end

  @doc """
  Resolve the workspace path for an issue based on its project/product association.

  If the issue belongs to a product, use the first project's path.
  If the issue belongs to a project, use that project's path.
  Otherwise, fall back to the default workspace path.
  """
  def resolve_project_workspace(
        %Config{tracker_kind: "local"},
        %Issue{product_id: prod_id},
        fallback
      )
      when is_binary(prod_id) and prod_id != "" do
    case resolve_product_project_paths(prod_id) do
      [first_path | _] ->
        Logger.info("Using product's first project path as workspace: #{first_path}")
        first_path

      [] ->
        fallback
    end
  end

  def resolve_project_workspace(
        %Config{tracker_kind: "local"},
        %Issue{project_id: pid},
        fallback
      )
      when is_binary(pid) and pid != "" do
    case SymphonyElixir.LocalBoard.get_project(pid) do
      {:ok, %{path: path}} when is_binary(path) and path != "" ->
        if File.dir?(path) do
          Logger.info("Using project path as workspace: #{path}")
          path
        else
          Logger.warning("Project path #{path} does not exist, using default workspace")
          fallback
        end

      _ ->
        fallback
    end
  end

  def resolve_project_workspace(_config, _issue, fallback), do: fallback

  # --- Private Helpers ---

  defp resolve_product_project_paths(product_id) do
    case SymphonyElixir.LocalBoard.get_product(product_id) do
      {:ok, product} ->
        (product.project_ids || [])
        |> Enum.map(fn pid ->
          case SymphonyElixir.LocalBoard.get_project(pid) do
            {:ok, %{path: path}} when is_binary(path) and path != "" -> path
            _ -> nil
          end
        end)
        |> Enum.filter(&(&1 != nil && File.dir?(&1)))

      _ ->
        []
    end
  end

  defp run_before_run_hook(config, workspace_path) do
    case Workspace.run_hook(config, :before_run, workspace_path) do
      :ok -> :ok
      {:error, reason} -> {:error, {:hook_failed, :before_run, reason}}
    end
  end

  defp agent_client_module do
    provider =
      try do
        SymphonyElixir.Settings.get("agent_provider")
      catch
        :exit, _ -> nil
      end

    case provider do
      "claude-code" -> ClaudeAdapter
      "codex" -> AppServerClient
      _ -> ClaudeAdapter
    end
  end

  defp render_prompt(template, issue, attempt) do
    case Prompt.render(template, issue, attempt) do
      {:ok, rendered} -> {:ok, rendered}
      {:error, reason} -> {:error, {:prompt_render_failed, reason}}
    end
  end

  defp validate_cwd(workspace_path) do
    if File.dir?(workspace_path) do
      :ok
    else
      {:error, :invalid_workspace_cwd}
    end
  end
end

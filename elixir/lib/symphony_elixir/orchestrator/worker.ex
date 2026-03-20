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

    # Add to running (pid populated after spawn)
    state = State.add_running(state, issue_id, State.new_running_entry(issue, nil))

    # B1: Spawn worker via supervised task with concurrency limit
    # B4: Wrap in try/catch so crashes always send worker_done
    {:ok, task_pid} =
      Task.Supervisor.start_child(SymphonyElixir.WorkerTaskSupervisor, fn ->
        result =
          try do
            run_worker(config, state.prompt_template, issue, orchestrator_pid)
          catch
            kind, reason ->
              Logger.error("Worker crashed for issue=#{identifier}: #{kind} #{inspect(reason)}")

              {:error, {:worker_crash, kind, inspect(reason)}}
          end

        send(orchestrator_pid, {:worker_done, issue_id, result})
      end)

    # Store the worker pid so we can kill it on cancel
    state = State.update_running(state, issue_id, %{worker_pid: task_pid})

    Logger.metadata(issue_id: issue_id, issue_identifier: identifier)
    state
  end

  @doc "Run the worker: set up workspace, render prompt, start agent session, run turn loop."
  def run_worker(config, prompt_template, issue, orchestrator_pid) do
    with {:ok, workspace_info} <- Workspace.ensure_workspace(config, issue) do
      workspace_path = resolve_project_workspace(config, issue, workspace_info.path)
      extra_mounts = resolve_extra_mounts(config, issue, workspace_path)

      with :ok <- run_before_run_hook(config, workspace_path),
           {:ok, prompt} <- render_prompt(prompt_template, issue, nil),
           :ok <- validate_cwd(workspace_path) do
        callback = fn event ->
          send(orchestrator_pid, {:agent_event, issue.id, event})
          :ok
        end

        client = agent_client_module()

        start_result =
          if extra_mounts != [] do
            if client == ClaudeAdapter do
              ClaudeAdapter.start_session(config, workspace_path, prompt, callback,
                extra_mounts: extra_mounts,
                issue_id: issue.id
              )
            else
              Logger.warning(
                "Extra mounts (#{length(extra_mounts)}) ignored — " <>
                  "provider #{inspect(agent_client_module())} does not support mounts"
              )

              client.start_session(config, workspace_path, prompt, callback)
            end
          else
            if client == ClaudeAdapter do
              ClaudeAdapter.start_session(config, workspace_path, prompt, callback,
                issue_id: issue.id
              )
            else
              client.start_session(config, workspace_path, prompt, callback)
            end
          end

        case start_result do
          {:ok, session} ->
            result = run_turn_loop(config, prompt_template, issue, session, 1)

            # after_run hook (failure ignored per spec)
            Workspace.run_hook(config, :after_run, workspace_path)

            # B3: Clean up temp artifacts on failure
            case result do
              {:error, _} -> cleanup_workspace_artifacts(workspace_path)
              _ -> :ok
            end

            result

          {:error, reason} ->
            cleanup_workspace_artifacts(workspace_path)
            {:error, {:startup_failed, reason}}
        end
      else
        {:error, reason} ->
          # B3: Clean up temp artifacts on hook/prompt/validation failures
          cleanup_workspace_artifacts(workspace_path)
          {:error, reason}
      end
    end
  end

  @doc """
  Run the agent turn loop until completion, failure, or cancellation.
  B2: Re-renders prompt from current issue state for continuation turns
  so that context changes (rerun_hint, labels, etc.) are picked up.
  """
  def run_turn_loop(config, prompt_template, issue, session, turn_count) do
    client = agent_client_module()

    case client.stream_turn(session) do
      {:ok, :completed, session} ->
        # Check if the issue was updated with a rerun_hint while the agent ran.
        # If so, start a continuation turn with fresh context (B2).
        case maybe_continue(config, issue) do
          {:continue, fresh_issue} ->
            case render_prompt(prompt_template, fresh_issue, turn_count) do
              {:ok, continuation_prompt} ->
                case client.start_continuation_turn(session, continuation_prompt) do
                  {:ok, new_session} ->
                    run_turn_loop(
                      config,
                      prompt_template,
                      fresh_issue,
                      new_session,
                      turn_count + 1
                    )

                  {:error, reason} ->
                    client.stop(session)
                    {:error, {:continuation_failed, reason, turn_count}}
                end

              {:error, reason} ->
                client.stop(session)
                {:error, {:prompt_render_failed, reason, turn_count}}
            end

          :done ->
            client.stop(session)
            {:ok, {:completed_after_turns, turn_count, nil}}
        end

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

  Priority: issue's own project_id (most specific) > product's first project > fallback.
  """
  def resolve_project_workspace(
        %Config{tracker_kind: "local"},
        %Issue{project_id: pid} = issue,
        fallback
      )
      when is_binary(pid) and pid != "" do
    case SymphonyElixir.LocalBoard.get_project(pid) do
      {:ok, %{path: path}} when is_binary(path) and path != "" ->
        if File.dir?(path) do
          Logger.info("Using project path as workspace: #{path}")
          path
        else
          Logger.warning("Project path #{path} does not exist, trying product fallback")
          resolve_product_workspace(issue, fallback)
        end

      _ ->
        resolve_product_workspace(issue, fallback)
    end
  end

  def resolve_project_workspace(
        %Config{tracker_kind: "local"},
        %Issue{} = issue,
        fallback
      ) do
    resolve_product_workspace(issue, fallback)
  end

  def resolve_project_workspace(_config, _issue, fallback), do: fallback

  defp resolve_product_workspace(%Issue{product_id: prod_id}, fallback)
       when is_binary(prod_id) and prod_id != "" do
    case resolve_product_project_paths(prod_id) do
      [first_path | _] ->
        Logger.info("Using product's first project path as workspace: #{first_path}")
        first_path

      [] ->
        fallback
    end
  end

  defp resolve_product_workspace(_issue, fallback), do: fallback

  @doc """
  For product-linked issues, return all project paths so the container
  can mount them as additional volumes alongside the primary workspace.
  """
  def resolve_extra_mounts(
        %Config{tracker_kind: "local"},
        %Issue{product_id: prod_id},
        primary_workspace
      )
      when is_binary(prod_id) and prod_id != "" do
    paths = resolve_product_project_paths(prod_id)
    # Exclude the primary workspace (already mounted at /workspace)
    extra = Enum.reject(paths, &(&1 == primary_workspace))

    if extra != [] do
      Logger.info(
        "Product task: #{length(extra)} extra project mounts: #{Enum.join(extra, ", ")}"
      )
    end

    extra
  end

  def resolve_extra_mounts(_config, _issue, _primary), do: []

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

  # Check if the issue was updated with a rerun_hint during the turn.
  # Returns {:continue, fresh_issue} or :done.
  defp maybe_continue(%Config{tracker_kind: "local"}, issue) do
    case SymphonyElixir.LocalBoard.get_issue(issue.id) do
      {:ok, fresh} ->
        hint = Map.get(fresh, :rerun_hint)

        if is_binary(hint) and hint != "" do
          Logger.info("Issue #{issue.identifier} has rerun_hint, continuing with new turn")
          {:continue, fresh}
        else
          :done
        end

      _ ->
        :done
    end
  end

  defp maybe_continue(_config, _issue), do: :done

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

  # B3: Clean up temporary artifacts left by failed agent runs
  defp cleanup_workspace_artifacts(workspace_path) do
    patterns = [
      Path.join(workspace_path, ".symphony_prompt_*"),
      Path.join(workspace_path, ".symphony_session_*"),
      Path.join(workspace_path, ".claude_tmp_*")
    ]

    Enum.each(patterns, fn pattern ->
      pattern
      |> Path.wildcard()
      |> Enum.each(fn file ->
        case File.rm(file) do
          :ok ->
            Logger.debug("Cleaned up temp artifact: #{file}")

          {:error, reason} ->
            Logger.warning("Failed to clean up #{file}: #{inspect(reason)}")
        end
      end)
    end)
  rescue
    _ -> :ok
  end
end

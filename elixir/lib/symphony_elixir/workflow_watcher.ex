defmodule SymphonyElixir.WorkflowWatcher do
  @moduledoc """
  Watches the WORKFLOW.md file for changes and triggers config reload.
  Uses the `file_system` library.
  """

  use GenServer

  require Logger

  alias SymphonyElixir.{Config, Orchestrator, Workflow}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Poll interval when native file watching is unavailable (Windows)
  @poll_interval_ms 5_000

  @impl true
  def init(opts) do
    workflow_path = Keyword.fetch!(opts, :workflow_path)
    hash = file_hash(workflow_path)

    state = %{
      workflow_path: workflow_path,
      watcher_pid: nil,
      last_hash: hash
    }

    case start_native_watcher(workflow_path) do
      {:ok, watcher_pid} ->
        {:ok, %{state | watcher_pid: watcher_pid}}

      :unavailable ->
        Logger.info("Using polling for workflow changes (native watcher unavailable on this OS)")
        schedule_poll()
        {:ok, state}
    end
  end

  defp start_native_watcher(workflow_path) do
    # FileSystem relies on inotifywait / fswatch which aren't available on Windows
    case :os.type() do
      {:win32, _} ->
        :unavailable

      _ ->
        watch_dir = Path.dirname(workflow_path)

        case FileSystem.start_link(dirs: [watch_dir]) do
          {:ok, pid} ->
            FileSystem.subscribe(pid)
            {:ok, pid}

          _ ->
            :unavailable
        end
    end
  end

  @impl true
  def handle_info({:file_event, _watcher_pid, {path, _events}}, state) do
    normalized_event_path = Path.expand(path)
    normalized_workflow_path = Path.expand(state.workflow_path)

    if paths_match?(normalized_event_path, normalized_workflow_path) do
      current_hash = file_hash(state.workflow_path)

      if current_hash != state.last_hash and current_hash != nil do
        Logger.info("WORKFLOW.md changed, reloading configuration")
        reload_workflow(state.workflow_path)
        {:noreply, %{state | last_hash: current_hash}}
      else
        {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  def handle_info({:file_event, _watcher_pid, :stop}, state) do
    Logger.warning("File watcher stopped, falling back to polling")
    schedule_poll()
    {:noreply, %{state | watcher_pid: nil}}
  end

  def handle_info(:poll_check, state) do
    current_hash = file_hash(state.workflow_path)

    state =
      if current_hash != state.last_hash and current_hash != nil do
        Logger.info("WORKFLOW.md changed, reloading configuration")
        reload_workflow(state.workflow_path)
        %{state | last_hash: current_hash}
      else
        state
      end

    schedule_poll()
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # --- Private ---

  defp schedule_poll, do: Process.send_after(self(), :poll_check, @poll_interval_ms)

  defp reload_workflow(path) do
    case Workflow.load(path) do
      {:ok, %{config: raw_config, prompt_template: prompt}} ->
        {:ok, config} = Config.from_workflow(raw_config)

        case Config.validate_dispatch(config) do
          :ok ->
            Orchestrator.reload_config(config, prompt)
            Logger.info("Configuration reloaded successfully")

          {:error, reason} ->
            Logger.error("Config validation failed on reload: #{inspect(reason)}")
        end

      {:error, reason} ->
        Logger.error("Failed to reload WORKFLOW.md: #{inspect(reason)}")
    end
  end

  defp file_hash(path) do
    case File.read(path) do
      {:ok, content} -> :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
      {:error, _} -> nil
    end
  end

  defp paths_match?(path1, path2) do
    case :os.type() do
      {:win32, _} -> String.downcase(path1) == String.downcase(path2)
      _ -> path1 == path2
    end
  end
end

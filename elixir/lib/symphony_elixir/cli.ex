defmodule SymphonyElixir.CLI do
  @moduledoc """
  Command-line interface for the Symphony service.

  Usage:
    symphony_elixir [--workflow PATH] [--port PORT]
  """

  require Logger

  alias SymphonyElixir.{Config, Workflow}

  @default_workflow_paths ["Workflow.local.md", "WORKFLOW.md", "Workflow.md"]

  @doc "Main escript entry point."
  @spec main([String.t()]) :: no_return()
  def main(args) do
    IO.puts("Symphony starting...")
    ensure_applications_started()
    IO.puts("Applications started. Args: #{inspect(args)}")

    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [
          workflow: :string,
          port: :integer,
          help: :boolean
        ],
        aliases: [w: :workflow, p: :port, h: :help]
      )

    if opts[:help] do
      print_usage()
      System.stop(0)
      Process.sleep(:infinity)
    end

    workflow_path = resolve_workflow_path(opts[:workflow])
    port = opts[:port]

    case startup(workflow_path, port) do
      {:ok, _} ->
        Logger.info("Symphony started. Workflow: #{workflow_path}")
        IO.puts("Symphony is running. Dashboard: http://localhost:#{port || "?"}/")
        IO.puts("Board: http://localhost:#{port || "?"}/board")
        IO.puts("Press Ctrl+C to stop.")

        # Keep the escript process alive
        Process.sleep(:infinity)

      {:error, reason} ->
        IO.puts(:stderr, "Failed to start: #{inspect(reason)}")
        System.stop(1)
        Process.sleep(:infinity)
    end
  end

  @doc "Start the Symphony service programmatically."
  @spec startup(String.t(), integer() | nil) :: {:ok, pid()} | {:error, term()}
  def startup(workflow_path, port \\ nil) do
    with {:ok, %{config: raw_config, prompt_template: prompt}} <- Workflow.load(workflow_path),
         {:ok, config} <- Config.from_workflow(raw_config),
         config = maybe_set_port(config, port),
         :ok <- Config.validate_dispatch(config) do
      children = build_children(config, prompt, workflow_path)

      opts = [strategy: :one_for_one, name: SymphonyElixir.RuntimeSupervisor]

      case Supervisor.start_link(children, opts) do
        {:ok, pid} ->
          # Seed built-in skills and pipelines after LocalBoard is started
          if Config.local_board?(config) do
            SymphonyElixir.SkillsSeed.seed()
            SymphonyElixir.PipelineSeed.seed()
            SymphonyElixir.HardeningSeed.seed()
            SymphonyElixir.FeaturePipelineSeed.seed()
          end

          {:ok, pid}

        error ->
          error
      end
    end
  end

  # --- Private ---

  defp ensure_applications_started do
    for app <- [:logger, :crypto, :ssl, :inets, :telemetry, :bandit] do
      Application.ensure_all_started(app)
    end
  end

  defp resolve_workflow_path(nil) do
    env_path = System.get_env("SYMPHONY_WORKFLOW_PATH")

    if env_path && env_path != "" do
      env_path
    else
      Enum.find(@default_workflow_paths, &File.exists?/1) ||
        hd(@default_workflow_paths)
    end
  end

  defp resolve_workflow_path(explicit), do: explicit

  defp maybe_set_port(%Config{} = config, nil), do: config

  defp maybe_set_port(%Config{} = config, port) when is_integer(port),
    do: %{config | server_port: port}

  defp build_children(config, prompt, workflow_path) do
    # Start the local board if tracker kind is "local"
    board_children =
      if Config.local_board?(config) do
        board_opts = [
          store_path: Path.join(Path.dirname(workflow_path), "local_board.json"),
          states: config.active_states ++ config.terminal_states,
          project_prefix:
            (config.tracker_project_slug || "SYM")
            |> String.split("-")
            |> hd()
            |> String.upcase()
        ]

        settings_opts = [
          store_path: Path.join(Path.dirname(workflow_path), "symphony_settings.json")
        ]

        [
          {SymphonyElixir.LocalBoard, board_opts},
          {SymphonyElixir.Settings, settings_opts}
        ]
      else
        []
      end

    pipeline_children =
      if Config.local_board?(config) do
        [{SymphonyElixir.PipelineRunner, []}]
      else
        []
      end

    kb_children =
      if Config.local_board?(config) do
        [{SymphonyElixir.Integrations.KBIndex, []}]
      else
        []
      end

    base =
      board_children ++
        [
          # B1: Task supervisor for worker tasks with concurrency limit
          {Task.Supervisor,
           name: SymphonyElixir.WorkerTaskSupervisor, max_children: config.max_concurrent_agents},
          {SymphonyElixir.Orchestrator, config: config, prompt_template: prompt},
          {SymphonyElixir.WorkflowWatcher, workflow_path: workflow_path}
        ] ++
        pipeline_children ++
        kb_children

    if config.server_port do
      plug_module =
        if Config.local_board?(config) do
          SymphonyElixir.Server.CombinedRouter
        else
          SymphonyElixir.Server.Router
        end

      http_child = {
        Bandit,
        plug: plug_module, port: config.server_port, ip: {127, 0, 0, 1}
      }

      base ++ [http_child]
    else
      base
    end
  end

  defp print_usage do
    IO.puts("""
    Symphony Elixir - Coding Agent Orchestrator

    Usage:
      symphony_elixir [options]

    Options:
      -w, --workflow PATH   Path to WORKFLOW.md (default: ./WORKFLOW.md)
      -p, --port PORT       HTTP dashboard port (enables dashboard)
      -h, --help            Show this help message

    Environment Variables:
      SYMPHONY_WORKFLOW_PATH   Default workflow file path
      SYMPHONY_PORT            Default HTTP port
      GITLAB_API_TOKEN         GitLab API token
    """)
  end
end

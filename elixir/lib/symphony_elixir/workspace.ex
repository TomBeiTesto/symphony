defmodule SymphonyElixir.Workspace do
  @moduledoc """
  Workspace management: creation, reuse, hooks, safety invariants.

  See SPEC Section 9.
  """

  require Logger

  alias SymphonyElixir.{Config, Issue, ShellUtils}

  @type hook_name :: :after_create | :before_run | :after_run | :before_remove
  @type create_result :: {:ok, %{path: String.t(), created_now: boolean()}} | {:error, term()}

  # --- Public API ---

  @doc """
  Ensure a workspace directory exists for the given issue.
  Runs `after_create` hook on newly created workspaces.
  """
  @spec ensure_workspace(Config.t(), Issue.t()) :: create_result()
  def ensure_workspace(%Config{} = config, %Issue{} = issue) do
    workspace_key = Issue.workspace_key(issue)
    workspace_path = workspace_path(config, workspace_key)

    with :ok <- validate_workspace_path(config, workspace_path) do
      already_exists = File.dir?(workspace_path)

      case File.mkdir_p(workspace_path) do
        :ok ->
          if already_exists do
            {:ok, %{path: workspace_path, created_now: false}}
          else
            case run_hook(config, :after_create, workspace_path) do
              :ok ->
                {:ok, %{path: workspace_path, created_now: true}}

              {:error, reason} ->
                # after_create failure is fatal to workspace creation
                Logger.error("after_create hook failed: #{inspect(reason)}")
                File.rm_rf(workspace_path)
                {:error, {:hook_failed, :after_create, reason}}
            end
          end

        {:error, reason} ->
          {:error, {:mkdir_failed, reason}}
      end
    end
  end

  @doc "Compute the workspace path for a given issue."
  @spec workspace_path(Config.t(), String.t()) :: String.t()
  def workspace_path(%Config{} = config, workspace_key) do
    Path.join(config.workspace_root, workspace_key)
    |> Path.expand()
  end

  @doc "Run a workspace lifecycle hook."
  @spec run_hook(Config.t(), hook_name(), String.t()) :: :ok | {:error, term()}
  def run_hook(%Config{} = config, hook_name, workspace_path) do
    script = get_hook_script(config, hook_name)

    if is_nil(script) or script == "" do
      :ok
    else
      timeout_ms = config.hooks.timeout_ms

      Logger.info("Running hook #{hook_name} in #{workspace_path}")

      case execute_hook(config, script, workspace_path, timeout_ms) do
        {:ok, _output} ->
          Logger.info("Hook #{hook_name} completed")
          :ok

        {:error, :timeout} ->
          Logger.error("Hook #{hook_name} timed out after #{timeout_ms}ms")
          {:error, :timeout}

        {:error, {:exit_code, code}} ->
          Logger.error("Hook #{hook_name} failed with exit code #{code}")
          {:error, {:exit_code, code}}

        {:error, reason} ->
          Logger.error("Hook #{hook_name} failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc "Remove a workspace directory, running `before_remove` hook first."
  @spec remove_workspace(Config.t(), String.t()) :: :ok | {:error, term()}
  def remove_workspace(%Config{} = config, workspace_key) do
    path = workspace_path(config, workspace_key)

    if File.dir?(path) do
      # before_remove failure is logged and ignored
      case run_hook(config, :before_remove, path) do
        :ok -> :ok
        {:error, reason} -> Logger.warning("before_remove hook failed: #{inspect(reason)}")
      end

      case File.rm_rf(path) do
        {:ok, _} -> :ok
        {:error, reason, _file} -> {:error, {:rm_failed, reason}}
      end
    else
      :ok
    end
  end

  @doc """
  Validate workspace path safety invariants per SPEC Section 9.5.
  """
  @spec validate_workspace_path(Config.t(), String.t()) :: :ok | {:error, term()}
  def validate_workspace_path(%Config{} = config, workspace_path) do
    root = normalize_path(config.workspace_root)
    path = normalize_path(workspace_path)

    basename = Path.basename(path)

    cond do
      not valid_workspace_key?(basename) ->
        {:error, :invalid_workspace_key}

      not path_is_under?(path, root) ->
        {:error, :workspace_outside_root}

      true ->
        :ok
    end
  end

  @doc "Check if a workspace key contains only allowed characters."
  @spec valid_workspace_key?(String.t()) :: boolean()
  def valid_workspace_key?(key) do
    Regex.match?(~r/^[A-Za-z0-9._-]+$/, key)
  end

  # --- Hook Execution ---

  defp execute_hook(config, script, cwd, timeout_ms) do
    {shell_cmd, shell_args} = hook_shell_command(config, script)

    port_opts = [
      :binary,
      :exit_status,
      :use_stdio,
      :stderr_to_stdout,
      {:cd, cwd},
      {:args, shell_args},
      {:line, 65_536}
    ]

    try do
      port = Port.open({:spawn_executable, shell_cmd}, port_opts)
      collect_hook_output(port, "", timeout_ms)
    rescue
      ErlangError ->
        {:error, {:shell_not_found, shell_cmd}}

      e ->
        {:error, {:spawn_failed, Exception.message(e)}}
    end
  end

  defp collect_hook_output(port, acc, timeout_ms) do
    receive do
      {^port, {:data, {:eol, line}}} ->
        collect_hook_output(port, acc <> line <> "\n", timeout_ms)

      {^port, {:data, {:noeol, chunk}}} ->
        collect_hook_output(port, acc <> chunk, timeout_ms)

      {^port, {:exit_status, 0}} ->
        {:ok, acc}

      {^port, {:exit_status, code}} ->
        {:error, {:exit_code, code}}
    after
      timeout_ms ->
        Port.close(port)
        {:error, :timeout}
    end
  end

  defp hook_shell_command(config, script) do
    shell = config.hooks.shell || ShellUtils.default_hook_shell()
    ShellUtils.shell_command(shell, script)
  end

  # --- Path Helpers ---

  defp normalize_path(path) do
    expanded = Path.expand(path)

    case :os.type() do
      {:win32, _} ->
        # Normalize to forward slashes and lowercase on Windows
        expanded |> String.replace("\\", "/") |> String.downcase()

      _ ->
        expanded
    end
  end

  defp path_is_under?(child, parent) do
    # Ensure parent ends with separator for prefix comparison
    parent_prefix = ensure_trailing_separator(parent)
    String.starts_with?(child, parent_prefix) or child == parent
  end

  defp ensure_trailing_separator(path) do
    if String.ends_with?(path, "/") or String.ends_with?(path, "\\") do
      path
    else
      path <> "/"
    end
  end

  # --- Report Discovery ---

  @doc """
  Find report markdown files in an issue's workspace.

  Searches the issue's project/product paths and the symphony workspace root
  for a `reports/` directory containing `.md` files.
  """
  @spec find_issue_reports(map()) :: [String.t()]
  def find_issue_reports(issue) do
    workspace_key = Map.get(issue, :identifier) || Map.get(issue, :id)

    workspace_root =
      case Process.get(:symphony_workspace_root) do
        nil -> Path.join(System.tmp_dir!(), "symphony_workspaces")
        root -> root
      end

    project_paths = resolve_issue_project_paths(issue)

    candidates =
      Enum.map(project_paths, fn p -> Path.join(p, "reports") end) ++
        [
          Path.join([workspace_root, workspace_key, "reports"]),
          Path.join(["~/code/symphony-workspaces", workspace_key, "reports"]),
          Path.join(["~/symphony_workspaces", workspace_key, "reports"])
        ]

    candidates
    |> Enum.map(&Path.expand/1)
    |> Enum.find(fn dir -> File.dir?(dir) end)
    |> case do
      nil -> []
      dir -> Path.wildcard(Path.join(dir, "*.md") |> String.replace("\\", "/"))
    end
  end

  defp resolve_issue_project_paths(issue) do
    project_path =
      case Map.get(issue, :project_id) do
        pid when is_binary(pid) and pid != "" ->
          case SymphonyElixir.LocalBoard.get_project(pid) do
            {:ok, %{path: path}} when is_binary(path) and path != "" -> path
            _ -> nil
          end

        _ ->
          nil
      end

    product_paths =
      case Map.get(issue, :product_id) do
        prod_id when is_binary(prod_id) and prod_id != "" ->
          case SymphonyElixir.LocalBoard.get_product(prod_id) do
            {:ok, product} ->
              (product.project_ids || [])
              |> Enum.flat_map(fn pid ->
                case SymphonyElixir.LocalBoard.get_project(pid) do
                  {:ok, %{path: path}} when is_binary(path) and path != "" -> [path]
                  _ -> []
                end
              end)

            _ ->
              []
          end

        _ ->
          []
      end

    Enum.reject([project_path | product_paths], &is_nil/1)
    |> Enum.uniq()
  end

  # --- Private Helpers ---

  defp get_hook_script(%Config{} = config, :after_create), do: config.hooks.after_create
  defp get_hook_script(%Config{} = config, :before_run), do: config.hooks.before_run
  defp get_hook_script(%Config{} = config, :after_run), do: config.hooks.after_run
  defp get_hook_script(%Config{} = config, :before_remove), do: config.hooks.before_remove
end

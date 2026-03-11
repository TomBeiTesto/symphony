defmodule SymphonyElixir.Config do
  @moduledoc """
  Typed configuration layer with defaults and `$VAR` resolution.

  See SPEC Section 6.
  """

  @default_active_states ["Todo", "In Progress"]
  @default_terminal_states [
    "Closed",
    "Cancelled",
    "Canceled",
    "Duplicate",
    "Done",
    "Review",
    "Archived"
  ]
  @default_poll_interval_ms 30_000
  @default_hook_timeout_ms 60_000
  @default_max_concurrent 10
  @default_max_turns 20
  @default_max_total_tokens 0
  @default_max_retry_backoff_ms 300_000
  @default_agent_command "agent-server"
  @default_turn_timeout_ms 3_600_000
  @default_read_timeout_ms 5_000
  @default_stall_timeout_ms 600_000

  @type t :: %__MODULE__{
          tracker_kind: String.t() | nil,
          tracker_endpoint: String.t(),
          tracker_api_key: String.t() | nil,
          tracker_project_slug: String.t() | nil,
          active_states: [String.t()],
          terminal_states: [String.t()],
          poll_interval_ms: pos_integer(),
          workspace_root: String.t(),
          hooks: %{
            after_create: String.t() | nil,
            before_run: String.t() | nil,
            after_run: String.t() | nil,
            before_remove: String.t() | nil,
            shell: String.t() | nil,
            timeout_ms: pos_integer()
          },
          max_concurrent_agents: pos_integer(),
          max_turns: pos_integer(),
          max_total_tokens: non_neg_integer(),
          max_retry_backoff_ms: pos_integer(),
          max_concurrent_agents_by_state: %{String.t() => pos_integer()},
          agent_command: String.t(),
          agent_shell: String.t() | nil,
          approval_policy: String.t() | nil,
          thread_sandbox: String.t() | nil,
          turn_sandbox_policy: map() | String.t() | nil,
          turn_timeout_ms: pos_integer(),
          read_timeout_ms: pos_integer(),
          stall_timeout_ms: integer(),
          server_port: integer() | nil
        }

  defstruct tracker_kind: nil,
            tracker_endpoint: nil,
            tracker_api_key: nil,
            tracker_project_slug: nil,
            active_states: @default_active_states,
            terminal_states: @default_terminal_states,
            poll_interval_ms: @default_poll_interval_ms,
            workspace_root: nil,
            hooks: %{
              after_create: nil,
              before_run: nil,
              after_run: nil,
              before_remove: nil,
              shell: nil,
              timeout_ms: @default_hook_timeout_ms
            },
            max_concurrent_agents: @default_max_concurrent,
            max_turns: @default_max_turns,
            max_total_tokens: @default_max_total_tokens,
            max_retry_backoff_ms: @default_max_retry_backoff_ms,
            max_concurrent_agents_by_state: %{},
            agent_command: @default_agent_command,
            agent_shell: nil,
            approval_policy: nil,
            thread_sandbox: nil,
            turn_sandbox_policy: nil,
            turn_timeout_ms: @default_turn_timeout_ms,
            read_timeout_ms: @default_read_timeout_ms,
            stall_timeout_ms: @default_stall_timeout_ms,
            server_port: nil

  @doc """
  Build a typed config from parsed workflow front-matter map.
  """
  @spec from_workflow(map()) :: {:ok, t()} | {:error, term()}
  def from_workflow(raw) when is_map(raw) do
    tracker = Map.get(raw, "tracker", %{})
    polling = Map.get(raw, "polling", %{})
    workspace = Map.get(raw, "workspace", %{})
    hooks_raw = Map.get(raw, "hooks", %{})
    agent = Map.get(raw, "agent", %{})
    # Support both "agent_process" (spec) and "codex" (legacy) keys
    agent_proc = Map.get(raw, "agent_process", Map.get(raw, "codex", %{}))
    server = Map.get(raw, "server", %{})

    api_key =
      resolve_env(Map.get(tracker, "api_key")) ||
        resolve_env_default_for_kind(Map.get(tracker, "kind"))

    config = %__MODULE__{
      tracker_kind: Map.get(tracker, "kind"),
      tracker_endpoint: Map.get(tracker, "endpoint", default_endpoint(tracker)),
      tracker_api_key: api_key,
      tracker_project_slug: Map.get(tracker, "project_slug"),
      active_states: parse_state_list(Map.get(tracker, "active_states"), @default_active_states),
      terminal_states:
        parse_state_list(Map.get(tracker, "terminal_states"), @default_terminal_states),
      poll_interval_ms: parse_int(Map.get(polling, "interval_ms"), @default_poll_interval_ms),
      workspace_root: resolve_workspace_root(Map.get(workspace, "root")),
      hooks: %{
        after_create: Map.get(hooks_raw, "after_create"),
        before_run: Map.get(hooks_raw, "before_run"),
        after_run: Map.get(hooks_raw, "after_run"),
        before_remove: Map.get(hooks_raw, "before_remove"),
        shell: Map.get(hooks_raw, "shell"),
        timeout_ms: parse_positive_int(Map.get(hooks_raw, "timeout_ms"), @default_hook_timeout_ms)
      },
      max_concurrent_agents:
        parse_int(Map.get(agent, "max_concurrent_agents"), @default_max_concurrent),
      max_turns: parse_int(Map.get(agent, "max_turns"), @default_max_turns),
      max_total_tokens:
        parse_non_neg_int(Map.get(agent, "max_total_tokens"), @default_max_total_tokens),
      max_retry_backoff_ms:
        parse_int(Map.get(agent, "max_retry_backoff_ms"), @default_max_retry_backoff_ms),
      max_concurrent_agents_by_state:
        parse_state_concurrency(Map.get(agent, "max_concurrent_agents_by_state")),
      agent_command: Map.get(agent_proc, "command", @default_agent_command),
      agent_shell: Map.get(agent_proc, "shell"),
      approval_policy: Map.get(agent_proc, "approval_policy"),
      thread_sandbox: Map.get(agent_proc, "thread_sandbox"),
      turn_sandbox_policy: Map.get(agent_proc, "turn_sandbox_policy"),
      turn_timeout_ms:
        parse_int(Map.get(agent_proc, "turn_timeout_ms"), @default_turn_timeout_ms),
      read_timeout_ms:
        parse_int(Map.get(agent_proc, "read_timeout_ms"), @default_read_timeout_ms),
      stall_timeout_ms:
        parse_non_neg_int(Map.get(agent_proc, "stall_timeout_ms"), @default_stall_timeout_ms),
      server_port: parse_optional_int(Map.get(server, "port"))
    }

    {:ok, config}
  end

  @doc "Validate config for dispatch readiness."
  @spec validate_dispatch(t()) :: :ok | {:error, atom()}
  def validate_dispatch(%__MODULE__{} = cfg) do
    cond do
      is_nil(cfg.tracker_kind) or cfg.tracker_kind == "" ->
        {:error, :missing_tracker_kind}

      cfg.tracker_kind not in ["gitlab", "local"] ->
        {:error, :unsupported_tracker_kind}

      cfg.tracker_kind == "gitlab" and
          (is_nil(cfg.tracker_api_key) or cfg.tracker_api_key == "") ->
        {:error, :missing_tracker_api_key}

      cfg.tracker_kind == "gitlab" and
          (is_nil(cfg.tracker_project_slug) or cfg.tracker_project_slug == "") ->
        {:error, :missing_tracker_project_slug}

      is_nil(cfg.agent_command) or cfg.agent_command == "" ->
        {:error, :missing_agent_command}

      true ->
        :ok
    end
  end

  @doc "Returns true if the tracker is the local board."
  @spec local_board?(t()) :: boolean()
  def local_board?(%__MODULE__{tracker_kind: "local"}), do: true
  def local_board?(%__MODULE__{}), do: false

  @doc "Return the normalized set of active states."
  @spec active_state_set(t()) :: MapSet.t()
  def active_state_set(%__MODULE__{active_states: states}) do
    states |> Enum.map(&SymphonyElixir.Issue.normalize_state/1) |> MapSet.new()
  end

  @doc "Return the normalized set of terminal states."
  @spec terminal_state_set(t()) :: MapSet.t()
  def terminal_state_set(%__MODULE__{terminal_states: states}) do
    states |> Enum.map(&SymphonyElixir.Issue.normalize_state/1) |> MapSet.new()
  end

  # --- Private helpers ---

  defp default_endpoint(%{"kind" => "gitlab"}), do: "https://gitlab.com/api/v4"
  defp default_endpoint(_), do: nil

  defp resolve_env(nil), do: nil
  defp resolve_env("$" <> var_name), do: resolve_env_var(var_name)
  defp resolve_env(value) when is_binary(value), do: value

  defp resolve_env_var(name) do
    case System.get_env(name) do
      nil -> nil
      "" -> nil
      val -> val
    end
  end

  defp resolve_env_default(env_name) do
    case System.get_env(env_name) do
      nil -> nil
      "" -> nil
      val -> val
    end
  end

  defp resolve_env_default_for_kind("gitlab"),
    do: resolve_env_default("GITLAB_API_TOKEN")

  defp resolve_env_default_for_kind(_kind),
    do: nil

  defp resolve_workspace_root(nil) do
    Path.join(System.tmp_dir!(), "symphony_workspaces")
  end

  defp resolve_workspace_root("$" <> var = _raw) do
    case resolve_env_var(var) do
      nil -> resolve_workspace_root(nil)
      path -> expand_path(path)
    end
  end

  defp resolve_workspace_root(path) when is_binary(path), do: expand_path(path)

  defp expand_path("~" <> rest) do
    (System.user_home!() <> rest)
    |> Path.expand()
  end

  defp expand_path(path) do
    Path.expand(path)
  end

  defp parse_state_list(nil, default), do: default

  defp parse_state_list(val, _default) when is_list(val) do
    Enum.map(val, &to_string/1)
  end

  defp parse_state_list(val, _default) when is_binary(val) do
    val |> String.split(",") |> Enum.map(&String.trim/1)
  end

  defp parse_state_list(_, default), do: default

  defp parse_int(nil, default), do: default
  defp parse_int(val, _default) when is_integer(val) and val > 0, do: val

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, ""} when n > 0 -> n
      _ -> default
    end
  end

  defp parse_int(_, default), do: default

  defp parse_non_neg_int(nil, default), do: default
  defp parse_non_neg_int(val, _default) when is_integer(val) and val >= 0, do: val

  defp parse_non_neg_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, ""} when n >= 0 -> n
      _ -> default
    end
  end

  defp parse_non_neg_int(_, default), do: default

  defp parse_positive_int(nil, default), do: default

  defp parse_positive_int(val, default) when is_integer(val),
    do: if(val > 0, do: val, else: default)

  defp parse_positive_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, ""} when n > 0 -> n
      _ -> default
    end
  end

  defp parse_positive_int(_, default), do: default

  defp parse_optional_int(nil), do: nil
  defp parse_optional_int(val) when is_integer(val), do: val

  defp parse_optional_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_optional_int(_), do: nil

  defp parse_state_concurrency(nil), do: %{}

  defp parse_state_concurrency(map) when is_map(map) do
    Map.new(
      for {k, v} <- map,
          is_binary(k),
          n = safe_positive_int(v),
          n != nil do
        {SymphonyElixir.Issue.normalize_state(k), n}
      end
    )
  end

  defp parse_state_concurrency(_), do: %{}

  defp safe_positive_int(v) when is_integer(v) and v > 0, do: v
  defp safe_positive_int(_), do: nil
end

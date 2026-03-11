defmodule SymphonyElixir.Settings do
  @moduledoc """
  Persistent user settings with JSON file storage.

  Stores configuration that can be changed at runtime via the
  Settings UI — git credentials, AI model provider, agent command,
  and other preferences.  Persists to a JSON file next to the
  board data so settings survive restarts.
  """

  use GenServer

  require Logger

  @default_store_path "symphony_settings.json"

  @defaults %{
    # --- Git provider ---
    "git_provider" => "gitlab",
    "git_token" => "",
    "git_host" => "https://gitlab.com",
    # --- AI / Agent ---
    "ai_provider" => "claude",
    "ai_model" => "claude-sonnet-4-20250514",
    "agent_provider" => "claude-code",
    "agent_command" => "",
    "agent_shell" => "",
    "agent_allowed_tools" => "WebSearch,WebFetch,Read,Write,Edit,Bash,Glob,Grep",
    # --- Board automation ---
    "auto_add_enabled" => "false",
    "max_todo_parallel" => "3",
    "segregate_by_project" => "false",
    # --- Tracker ---
    "tracker_kind" => "local",
    "tracker_endpoint" => "",
    "tracker_api_key" => "",
    "tracker_project_slug" => ""
  }

  @type settings_map :: %{String.t() => String.t() | nil}

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Return all settings as a flat map."
  @spec all() :: settings_map()
  def all do
    GenServer.call(__MODULE__, :all)
  end

  @doc "Get a single setting value (returns default if unset)."
  @spec get(String.t()) :: String.t() | nil
  def get(key) when is_binary(key) do
    GenServer.call(__MODULE__, {:get, key})
  end

  @doc "Bulk-update settings. Only known keys are accepted."
  @spec update(map()) :: :ok
  def update(attrs) when is_map(attrs) do
    GenServer.call(__MODULE__, {:update, attrs})
  end

  @doc "Reset all settings to defaults."
  @spec reset() :: :ok
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @doc "Return the list of known setting keys."
  @spec known_keys() :: [String.t()]
  def known_keys, do: Map.keys(@defaults)

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    store_path = Keyword.get(opts, :store_path, @default_store_path)
    state = %{settings: @defaults, store_path: store_path}
    state = load_from_disk(state)
    Logger.info("Settings loaded from #{store_path}")
    {:ok, state}
  end

  @impl true
  def handle_call(:all, _from, state) do
    {:reply, state.settings, state}
  end

  def handle_call({:get, key}, _from, state) do
    {:reply, Map.get(state.settings, key, Map.get(@defaults, key)), state}
  end

  def handle_call({:update, attrs}, _from, state) do
    merged =
      Enum.reduce(attrs, state.settings, fn {k, v}, acc ->
        if Map.has_key?(@defaults, to_string(k)) do
          Map.put(acc, to_string(k), v)
        else
          acc
        end
      end)

    state = %{state | settings: merged}
    persist(state)
    {:reply, :ok, state}
  end

  def handle_call(:reset, _from, state) do
    state = %{state | settings: @defaults}
    persist(state)
    {:reply, :ok, state}
  end

  # ---------------------------------------------------------------------------
  # Persistence
  # ---------------------------------------------------------------------------

  defp persist(%{settings: settings, store_path: path}) do
    json = Jason.encode!(settings, pretty: true)
    File.write!(path, json)
  rescue
    e ->
      Logger.error("Failed to persist settings: #{Exception.message(e)}")
  end

  defp load_from_disk(%{store_path: path} = state) do
    case File.read(path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, data} when is_map(data) ->
            # Merge persisted values over defaults (only known keys)
            merged =
              Enum.reduce(data, @defaults, fn {k, v}, acc ->
                if Map.has_key?(@defaults, k), do: Map.put(acc, k, v), else: acc
              end)

            %{state | settings: merged}

          _ ->
            Logger.warning("Corrupt settings file at #{path}, using defaults")
            state
        end

      {:error, :enoent} ->
        state

      {:error, reason} ->
        Logger.warning("Cannot read settings (#{inspect(reason)}), using defaults")
        state
    end
  end
end

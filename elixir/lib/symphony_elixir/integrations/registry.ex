defmodule SymphonyElixir.Integrations.Registry do
  @moduledoc """
  Central dispatcher for all integration types.

  Resolves an integration type string (e.g. "jira") to the corresponding module
  and delegates `execute/3` and `test_connection/2` calls.

  Global credentials are stored in Settings and merged with per-node action config
  at call time via `build_config/2`.
  """

  alias SymphonyElixir.Integrations.{Jira, GitlabCI, Confluence, KnowledgeBase}
  alias SymphonyElixir.Settings

  @modules %{
    "jira" => Jira,
    "gitlab_ci" => GitlabCI,
    "confluence" => Confluence,
    "knowledge_base" => KnowledgeBase
  }

  @credential_keys %{
    "jira" => ~w(jira_base_url jira_auth_token jira_project_key jira_issue_type),
    "gitlab_ci" =>
      ~w(gitlab_ci_base_url gitlab_ci_project_id gitlab_ci_trigger_token gitlab_ci_ref),
    "confluence" =>
      ~w(confluence_base_url confluence_auth_token confluence_space_key confluence_parent_page_id),
    "knowledge_base" => ~w(kb_type kb_vault_path kb_subfolder)
  }

  # Custom prefix overrides for types that don't follow the "type_" naming convention
  @credential_prefixes %{
    "knowledge_base" => "kb_"
  }

  @type_labels %{
    "jira" => "Jira",
    "gitlab_ci" => "GitLab CI",
    "confluence" => "Confluence",
    "knowledge_base" => "Knowledge Base"
  }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc "Execute an integration action. Config is merged from global credentials + action_config."
  @spec execute(String.t(), map(), map()) :: {:ok, map()} | {:error, term()}
  def execute(type, config, context) do
    case resolve(type) do
      {:ok, mod} -> mod.execute(config, context)
      {:error, _} = err -> err
    end
  end

  @doc "Test connectivity for an integration type using global credentials (optionally overridden)."
  @spec test_connection(String.t(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def test_connection(type, config_overrides \\ %{}) do
    case resolve(type) do
      {:ok, mod} ->
        config = build_config(type, config_overrides)
        mod.test_connection(config)

      {:error, _} = err ->
        err
    end
  end

  @doc "Build a full config map by merging global credentials from Settings with per-node overrides."
  @spec build_config(String.t(), map()) :: map()
  def build_config(type, action_config \\ %{}) do
    credentials = get_credentials(type)
    Map.merge(credentials, action_config)
  end

  @doc "Fetch global credentials for an integration type from Settings."
  @spec get_credentials(String.t()) :: map()
  def get_credentials(type) do
    keys = Map.get(@credential_keys, type, [])
    settings = Settings.all()

    # Strip the type prefix from keys to get the config field names
    # e.g. "jira_base_url" -> "base_url", "gitlab_ci_project_id" -> "project_id"
    # Special case: "kb_" prefix for knowledge_base (shorter than "knowledge_base_")
    prefix = Map.get(@credential_prefixes, type, type <> "_")

    Enum.reduce(keys, %{}, fn key, acc ->
      value = Map.get(settings, key, "")

      field_name =
        if String.starts_with?(key, prefix) do
          String.replace_prefix(key, prefix, "")
        else
          key
        end

      if value != "" do
        Map.put(acc, field_name, value)
      else
        acc
      end
    end)
  end

  @doc "List all available integration types."
  @spec available_types() :: [String.t()]
  def available_types, do: Map.keys(@modules)

  @doc "Human-readable label for an integration type."
  @spec type_label(String.t()) :: String.t()
  def type_label(type), do: Map.get(@type_labels, type, type)

  @doc "Check whether global credentials are configured for a given integration type."
  @spec configured?(String.t()) :: boolean()
  def configured?(type) do
    creds = get_credentials(type)
    # Each type has required fields — check at least the base connection fields exist
    case type do
      "jira" -> Map.has_key?(creds, "base_url") and Map.has_key?(creds, "auth_token")
      "gitlab_ci" -> Map.has_key?(creds, "base_url") and Map.has_key?(creds, "project_id")
      "confluence" -> Map.has_key?(creds, "base_url") and Map.has_key?(creds, "auth_token")
      "knowledge_base" -> true
      _ -> false
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp resolve(type) do
    case Map.fetch(@modules, type) do
      {:ok, mod} -> {:ok, mod}
      :error -> {:error, {:unknown_integration, type}}
    end
  end
end

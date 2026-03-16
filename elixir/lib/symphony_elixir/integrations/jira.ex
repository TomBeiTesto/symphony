defmodule SymphonyElixir.Integrations.Jira do
  @moduledoc """
  Jira integration for pipeline nodes.

  Creates/updates Jira issues and syncs status bidirectionally.
  Used by integration nodes of type "jira" in the pipeline designer.
  """

  require Logger

  @doc """
  Execute a Jira integration action based on node config.

  Config fields:
  - base_url: Jira instance URL (e.g., "https://myorg.atlassian.net")
  - project_key: Jira project key (e.g., "PROJ")
  - issue_type: Issue type name (e.g., "Task", "Story")
  - auth_token: API token for authentication
  - action: "create" | "update" | "transition" | "sync_status"
  - field_mapping: %{symphony_field => jira_field}
  """
  @spec execute(map(), map()) :: {:ok, map()} | {:error, term()}
  def execute(config, context) do
    action = Map.get(config, "action", "create")

    case action do
      "create" -> create_issue(config, context)
      "update" -> update_issue(config, context)
      "transition" -> transition_issue(config, context)
      "sync_status" -> sync_status(config, context)
      _ -> {:error, "Unknown Jira action: #{action}"}
    end
  end

  @doc "Test the Jira connection with given config."
  @spec test_connection(map()) :: {:ok, String.t()} | {:error, String.t()}
  def test_connection(config) do
    base_url = Map.get(config, "base_url", "")
    auth_token = Map.get(config, "auth_token", "")

    if base_url == "" or auth_token == "" do
      {:error, "Missing base_url or auth_token"}
    else
      url = "#{base_url}/rest/api/3/myself"

      case http_get(url, auth_token) do
        {:ok, %{status: 200, body: body}} ->
          name = Map.get(body, "displayName", "Unknown")
          {:ok, "Connected as #{name}"}

        {:ok, %{status: status}} ->
          {:error, "Jira returned status #{status}"}

        {:error, reason} ->
          {:error, "Connection failed: #{inspect(reason)}"}
      end
    end
  end

  defp create_issue(config, context) do
    base_url = config["base_url"]
    project_key = config["project_key"]
    issue_type = config["issue_type"] || "Task"
    auth_token = config["auth_token"]

    body = %{
      "fields" => %{
        "project" => %{"key" => project_key},
        "issuetype" => %{"name" => issue_type},
        "summary" => context["title"] || "Pipeline task",
        "description" => %{
          "type" => "doc",
          "version" => 1,
          "content" => [
            %{
              "type" => "paragraph",
              "content" => [%{"type" => "text", "text" => context["description"] || ""}]
            }
          ]
        }
      }
    }

    url = "#{base_url}/rest/api/3/issue"

    case http_post(url, auth_token, body) do
      {:ok, %{status: 201, body: resp}} ->
        {:ok, %{jira_key: resp["key"], jira_id: resp["id"]}}

      {:ok, %{status: status, body: resp}} ->
        {:error, "Jira create failed (#{status}): #{inspect(resp)}"}

      {:error, reason} ->
        {:error, "Jira request failed: #{inspect(reason)}"}
    end
  end

  defp update_issue(config, context) do
    base_url = config["base_url"]
    auth_token = config["auth_token"]
    jira_key = config["jira_key"] || context["jira_key"]

    if is_nil(jira_key) do
      {:error, "No Jira issue key provided"}
    else
      fields = Map.get(config, "fields", %{})
      url = "#{base_url}/rest/api/3/issue/#{jira_key}"

      case http_put(url, auth_token, %{"fields" => fields}) do
        {:ok, %{status: s}} when s in [200, 204] -> {:ok, %{updated: jira_key}}
        {:ok, %{status: status}} -> {:error, "Jira update failed (#{status})"}
        {:error, reason} -> {:error, inspect(reason)}
      end
    end
  end

  defp transition_issue(config, context) do
    base_url = config["base_url"]
    auth_token = config["auth_token"]
    jira_key = config["jira_key"] || context["jira_key"]
    transition_id = config["transition_id"]

    if is_nil(jira_key) or is_nil(transition_id) do
      {:error, "Missing jira_key or transition_id"}
    else
      url = "#{base_url}/rest/api/3/issue/#{jira_key}/transitions"
      body = %{"transition" => %{"id" => transition_id}}

      case http_post(url, auth_token, body) do
        {:ok, %{status: 204}} -> {:ok, %{transitioned: jira_key}}
        {:ok, %{status: status}} -> {:error, "Jira transition failed (#{status})"}
        {:error, reason} -> {:error, inspect(reason)}
      end
    end
  end

  defp sync_status(config, _context) do
    base_url = config["base_url"]
    auth_token = config["auth_token"]
    jira_key = config["jira_key"]

    if is_nil(jira_key) do
      {:error, "No Jira issue key"}
    else
      url = "#{base_url}/rest/api/3/issue/#{jira_key}"

      case http_get(url, auth_token) do
        {:ok, %{status: 200, body: body}} ->
          status = get_in(body, ["fields", "status", "name"])
          {:ok, %{jira_key: jira_key, status: status}}

        {:ok, %{status: status}} ->
          {:error, "Jira fetch failed (#{status})"}

        {:error, reason} ->
          {:error, inspect(reason)}
      end
    end
  end

  # HTTP helpers using Req
  defp http_get(url, token) do
    Req.get(url,
      headers: [
        {"authorization", "Basic #{token}"},
        {"content-type", "application/json"}
      ]
    )
  end

  defp http_post(url, token, body) do
    Req.post(url,
      headers: [
        {"authorization", "Basic #{token}"},
        {"content-type", "application/json"}
      ],
      json: body
    )
  end

  defp http_put(url, token, body) do
    Req.put(url,
      headers: [
        {"authorization", "Basic #{token}"},
        {"content-type", "application/json"}
      ],
      json: body
    )
  end
end

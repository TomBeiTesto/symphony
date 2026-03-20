defmodule SymphonyElixir.Integrations.Confluence do
  @moduledoc """
  Confluence integration for pipeline nodes.
  
  Creates/updates Confluence pages for knowledge base sync.
  Used by kb_sync and integration nodes in the pipeline designer.
  """

  require Logger

  @doc """
  Execute a Confluence integration action based on node config.
  
  Config fields:
  - base_url: Confluence instance URL
  - space_key: Confluence space key
  - parent_page_id: Parent page ID for new pages
  - auth_token: API token for authentication
  - action: "create_page" | "update_page" | "get_page"
  """
  @spec execute(map(), map()) :: {:ok, map()} | {:error, term()}
  def execute(config, context) do
    action = Map.get(config, "action", "create_page")

    case action do
      "create_page" -> create_page(config, context)
      "update_page" -> update_page(config, context)
      "get_page" -> get_page(config)
      _ -> {:error, "Unknown Confluence action: #{action}"}
    end
  end

  @doc "Test the Confluence connection."
  @spec test_connection(map()) :: {:ok, String.t()} | {:error, String.t()}
  def test_connection(config) do
    base_url = Map.get(config, "base_url", "")
    auth_token = Map.get(config, "auth_token", "")

    if base_url == "" or auth_token == "" do
      {:error, "Missing base_url or auth_token"}
    else
      url = "#{base_url}/wiki/rest/api/space?limit=1"

      case http_get(url, auth_token) do
        {:ok, %{status: 200}} -> {:ok, "Connected to Confluence"}
        {:ok, %{status: status}} -> {:error, "Confluence returned status #{status}"}
        {:error, reason} -> {:error, "Connection failed: #{inspect(reason)}"}
      end
    end
  end

  defp create_page(config, context) do
    base_url = config["base_url"]
    space_key = config["space_key"]
    parent_id = config["parent_page_id"]
    auth_token = config["auth_token"]

    title = context["title"] || "Pipeline KB Entry"
    content = context["content"] || ""

    body = %{
      "type" => "page",
      "title" => title,
      "space" => %{"key" => space_key},
      "body" => %{
        "storage" => %{
          "value" => "<p>#{content}</p>",
          "representation" => "storage"
        }
      }
    }

    body =
      if parent_id do
        Map.put(body, "ancestors", [%{"id" => parent_id}])
      else
        body
      end

    url = "#{base_url}/wiki/rest/api/content"

    case http_post(url, auth_token, body) do
      {:ok, %{status: 200, body: resp}} ->
        {:ok, %{page_id: resp["id"], title: resp["title"]}}

      {:ok, %{status: status, body: resp}} ->
        {:error, "Confluence create failed (#{status}): #{inspect(resp)}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp update_page(config, context) do
    base_url = config["base_url"]
    auth_token = config["auth_token"]
    page_id = config["page_id"]

    if is_nil(page_id) do
      {:error, "No page_id provided"}
    else
      # Get current version first
      url = "#{base_url}/wiki/rest/api/content/#{page_id}"

      case http_get(url, auth_token) do
        {:ok, %{status: 200, body: current}} ->
          version = get_in(current, ["version", "number"]) || 1

          body = %{
            "type" => "page",
            "title" => context["title"] || current["title"],
            "version" => %{"number" => version + 1},
            "body" => %{
              "storage" => %{
                "value" => "<p>#{context["content"] || ""}</p>",
                "representation" => "storage"
              }
            }
          }

          case http_put(url, auth_token, body) do
            {:ok, %{status: 200, body: resp}} ->
              {:ok, %{page_id: resp["id"], version: version + 1}}

            {:ok, %{status: status}} ->
              {:error, "Confluence update failed (#{status})"}

            {:error, reason} ->
              {:error, inspect(reason)}
          end

        {:ok, %{status: status}} ->
          {:error, "Failed to get page (#{status})"}

        {:error, reason} ->
          {:error, inspect(reason)}
      end
    end
  end

  defp get_page(config) do
    base_url = config["base_url"]
    auth_token = config["auth_token"]
    page_id = config["page_id"]

    if is_nil(page_id) do
      {:error, "No page_id provided"}
    else
      url = "#{base_url}/wiki/rest/api/content/#{page_id}?expand=body.storage"

      case http_get(url, auth_token) do
        {:ok, %{status: 200, body: resp}} ->
          {:ok,
           %{
             page_id: resp["id"],
             title: resp["title"],
             content: get_in(resp, ["body", "storage", "value"])
           }}

        {:ok, %{status: status}} ->
          {:error, "Confluence fetch failed (#{status})"}

        {:error, reason} ->
          {:error, inspect(reason)}
      end
    end
  end

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

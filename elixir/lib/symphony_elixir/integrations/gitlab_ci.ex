defmodule SymphonyElixir.Integrations.GitlabCI do
  @moduledoc """
  GitLab CI integration for pipeline quality gate nodes.

  Triggers GitLab CI pipelines and polls for results.
  Used by quality_gate and integration nodes in the pipeline designer.
  """

  require Logger

  @doc """
  Execute a GitLab CI action based on node config.

  Config fields:
  - base_url: GitLab instance URL (e.g., "https://gitlab.com")
  - project_id: GitLab project ID or URL-encoded path
  - trigger_token: Pipeline trigger token
  - ref: Branch/tag to run pipeline on (default: "main")
  - variables: %{key => value} pipeline variables
  - action: "trigger" | "poll" | "get_status"
  """
  @spec execute(map(), map()) :: {:ok, map()} | {:error, term()}
  def execute(config, context) do
    action = Map.get(config, "action", "trigger")

    case action do
      "trigger" -> trigger_pipeline(config, context)
      "poll" -> poll_pipeline(config)
      "get_status" -> poll_pipeline(config)
      _ -> {:error, "Unknown GitLab CI action: #{action}"}
    end
  end

  @doc "Test the GitLab connection."
  @spec test_connection(map()) :: {:ok, String.t()} | {:error, String.t()}
  def test_connection(config) do
    base_url = Map.get(config, "base_url", "")
    token = Map.get(config, "trigger_token", "")
    project_id = Map.get(config, "project_id", "")

    if base_url == "" or project_id == "" do
      {:error, "Missing base_url or project_id"}
    else
      url = "#{base_url}/api/v4/projects/#{URI.encode_www_form(project_id)}"

      case http_get(url, token) do
        {:ok, %{status: 200, body: body}} ->
          name = Map.get(body, "name", "Unknown")
          {:ok, "Connected to project: #{name}"}

        {:ok, %{status: status}} ->
          {:error, "GitLab returned status #{status}"}

        {:error, reason} ->
          {:error, "Connection failed: #{inspect(reason)}"}
      end
    end
  end

  defp trigger_pipeline(config, _context) do
    base_url = config["base_url"]
    project_id = config["project_id"]
    token = config["trigger_token"]
    ref = config["ref"] || "main"
    variables = config["variables"] || %{}

    url = "#{base_url}/api/v4/projects/#{URI.encode_www_form(project_id)}/trigger/pipeline"

    form_data =
      Map.merge(
        %{"token" => token, "ref" => ref},
        Enum.into(variables, %{}, fn {k, v} -> {"variables[#{k}]", v} end)
      )

    case Req.post(url, form: form_data) do
      {:ok, %{status: 201, body: body}} ->
        {:ok,
         %{
           pipeline_id: body["id"],
           web_url: body["web_url"],
           status: body["status"]
         }}

      {:ok, %{status: status, body: body}} ->
        {:error, "GitLab trigger failed (#{status}): #{inspect(body)}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp poll_pipeline(config) do
    base_url = config["base_url"]
    project_id = config["project_id"]
    token = config["trigger_token"]
    pipeline_id = config["pipeline_id"]

    if is_nil(pipeline_id) do
      {:error, "No pipeline_id to poll"}
    else
      url =
        "#{base_url}/api/v4/projects/#{URI.encode_www_form(project_id)}/pipelines/#{pipeline_id}"

      case http_get(url, token) do
        {:ok, %{status: 200, body: body}} ->
          status = body["status"]
          # GitLab statuses: created, waiting_for_resource, preparing, pending, running,
          # success, failed, canceled, skipped, manual, scheduled
          result = %{
            pipeline_id: pipeline_id,
            status: status,
            finished: status in ["success", "failed", "canceled", "skipped"],
            passed: status == "success",
            web_url: body["web_url"]
          }

          {:ok, result}

        {:ok, %{status: status}} ->
          {:error, "GitLab poll failed (#{status})"}

        {:error, reason} ->
          {:error, inspect(reason)}
      end
    end
  end

  defp http_get(url, token) do
    Req.get(url,
      headers: [
        {"private-token", token},
        {"content-type", "application/json"}
      ]
    )
  end
end

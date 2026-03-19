defmodule SymphonyElixir.GitLab.Client do
  @moduledoc """
  GitLab REST/GraphQL API client implementation.

  Maps GitLab issues to the Symphony `Issue` struct using the same
  behaviour as the tracker client.  GitLab issue *labels* are treated
  as workflow states (e.g. "Todo", "In Progress") so teams can model
  a full Kanban flow.  If no matching label is found the client falls
  back to the native GitLab state ("opened" → "Todo", "closed" → "Done").

  ## Configuration

      tracker:
        kind: gitlab
        endpoint: https://gitlab.com/api/v4    # or self-hosted
        api_key: $GITLAB_API_TOKEN
        project_slug: "12345"                  # numeric ID or URL-encoded path
  """

  @behaviour SymphonyElixir.Tracker.Behaviour

  alias SymphonyElixir.{Config, DateTimeUtils, Issue}

  @page_size 100
  @network_timeout 30_000

  # ---------------------------------------------------------------------------
  # Public API — Behaviour callbacks
  # ---------------------------------------------------------------------------

  @impl true
  @spec fetch_candidate_issues(Config.t()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_candidate_issues(%Config{} = config) do
    labels = Enum.join(config.active_states, ",")

    params = %{
      "labels" => labels,
      "state" => "opened",
      "per_page" => @page_size,
      "page" => 1
    }

    fetch_all_pages(config, params, [])
  end

  @impl true
  @spec fetch_issues_by_states(Config.t(), [String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issues_by_states(%Config{} = _config, []), do: {:ok, []}

  def fetch_issues_by_states(%Config{} = config, state_names) do
    labels = Enum.join(state_names, ",")

    params = %{
      "labels" => labels,
      "per_page" => @page_size,
      "page" => 1
    }

    fetch_all_pages(config, params, [])
  end

  @impl true
  @spec fetch_issue_states_by_ids(Config.t(), [String.t()]) ::
          {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issue_states_by_ids(%Config{} = _config, []), do: {:ok, []}

  def fetch_issue_states_by_ids(%Config{} = config, issue_ids) do
    # GitLab REST API supports filtering by iids[] for a project.
    # issue_ids in Symphony are strings; GitLab iids are integers extracted
    # from the identifier (e.g. "PROJ-42" → 42), but we also store the raw
    # GitLab iid as the Issue.id.  Try each as an iid query param.
    iid_params =
      issue_ids
      |> Enum.map(&extract_iid/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if iid_params == [] do
      {:ok, []}
    else
      params = %{
        "iids[]" => iid_params,
        "per_page" => @page_size,
        "page" => 1
      }

      fetch_all_pages(config, params, [])
    end
  end

  # ---------------------------------------------------------------------------
  # Pagination
  # ---------------------------------------------------------------------------

  defp fetch_all_pages(config, params, acc) do
    case do_rest_get(config, issues_path(config), params) do
      {:ok, %Req.Response{status: 200, body: body, headers: headers}} when is_list(body) ->
        issues = Enum.map(body, &normalize_issue(&1, config))
        all = acc ++ issues

        next_page = next_page_from_headers(headers)

        if next_page do
          fetch_all_pages(config, Map.put(params, "page", next_page), all)
        else
          {:ok, all}
        end

      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, list} when is_list(list) ->
            {:ok, acc ++ Enum.map(list, &normalize_issue(&1, config))}

          _ ->
            {:error, :gitlab_unexpected_payload}
        end

      {:ok, %Req.Response{status: status}} ->
        {:error, {:gitlab_api_status, status}}

      {:error, reason} ->
        {:error, {:gitlab_api_request, reason}}
    end
  end

  # ---------------------------------------------------------------------------
  # HTTP helpers
  # ---------------------------------------------------------------------------

  defp do_rest_get(config, path, params) do
    url = "#{config.tracker_endpoint}#{path}"

    headers = [
      {"private-token", config.tracker_api_key}
    ]

    Req.get(url, params: params, headers: headers, receive_timeout: @network_timeout)
  end

  defp issues_path(%Config{} = config) do
    project = config.tracker_project_slug || ""
    "/projects/#{URI.encode(project, &URI.char_unreserved?/1)}/issues"
  end


  # ---------------------------------------------------------------------------
  # Normalization — GitLab JSON → Issue struct
  # ---------------------------------------------------------------------------

  defp normalize_issue(node, config) when is_map(node) do
    all_states = config.active_states ++ config.terminal_states
    labels = Map.get(node, "labels", [])

    state = derive_state(labels, all_states, Map.get(node, "state", "opened"))

    %Issue{
      id: to_string(node["id"]),
      identifier: build_identifier(config, node),
      title: node["title"] || "",
      description: node["description"],
      priority: priority_from_labels(labels),
      state: state,
      branch_name: nil,
      url: node["web_url"],
      labels: Enum.map(labels, &String.downcase/1),
      blocked_by: [],
      created_at: DateTimeUtils.parse_datetime(node["created_at"]),
      updated_at: DateTimeUtils.parse_datetime(node["updated_at"])
    }
  end

  @doc false
  def derive_state(labels, known_states, native_state) do
    # First label that matches a known Symphony state wins.
    match =
      Enum.find(known_states, fn s ->
        Enum.any?(labels, &(String.downcase(&1) == String.downcase(s)))
      end)

    case match do
      nil -> if(native_state == "closed", do: "Done", else: "Todo")
      s -> s
    end
  end

  defp build_identifier(config, node) do
    prefix = config.tracker_project_slug || "GL"
    iid = node["iid"] || node["id"]
    "#{prefix}-#{iid}"
  end

  defp priority_from_labels(labels) do
    cond do
      Enum.any?(labels, &String.contains?(String.downcase(&1), "critical")) -> 1
      Enum.any?(labels, &String.contains?(String.downcase(&1), "urgent")) -> 1
      Enum.any?(labels, &String.contains?(String.downcase(&1), "high")) -> 2
      Enum.any?(labels, &String.contains?(String.downcase(&1), "medium")) -> 3
      Enum.any?(labels, &String.contains?(String.downcase(&1), "low")) -> 4
      true -> nil
    end
  end

  defp extract_iid(id_string) when is_binary(id_string) do
    # Accept raw numeric IDs ("42") or identifiers ("PROJ-42")
    case Integer.parse(id_string) do
      {n, ""} -> n
      _ -> extract_trailing_number(id_string)
    end
  end

  defp extract_trailing_number(str) do
    case Regex.run(~r/-(\d+)$/, str) do
      [_, num] ->
        case Integer.parse(num) do
          {n, ""} -> n
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp next_page_from_headers(headers) do
    # GitLab pagination uses the x-next-page response header.
    next =
      headers
      |> Enum.find_value(fn
        {"x-next-page", val} -> val
        _ -> nil
      end)

    case next do
      nil ->
        nil

      "" ->
        nil

      val when is_binary(val) ->
        case Integer.parse(val) do
          {n, ""} when n > 0 -> n
          _ -> nil
        end

      val when is_list(val) ->
        val |> List.first() |> next_page_value()
    end
  end

  defp next_page_value(nil), do: nil
  defp next_page_value(""), do: nil

  defp next_page_value(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, ""} when n > 0 -> n
      _ -> nil
    end
  end
end

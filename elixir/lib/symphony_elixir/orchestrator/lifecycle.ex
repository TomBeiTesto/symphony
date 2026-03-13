defmodule SymphonyElixir.Orchestrator.Lifecycle do
  @moduledoc """
  Worker result handling and issue lifecycle management.

  Handles success/failure outcomes, token exhaustion detection,
  follow-up extraction, agent run persistence, and done-state resolution.
  """

  require Logger

  alias SymphonyElixir.Orchestrator.{Retry, State}

  @doc "Handle a worker result (success or failure) and update state accordingly."
  def handle_worker_result(state, issue_id, result) do
    running_entry = Map.get(state.running, issue_id)
    identifier = running_entry_identifier(running_entry)

    state = preserve_completed_run(state, issue_id, running_entry, identifier)
    state = State.remove_running(state, issue_id)

    case result do
      {:ok, _} ->
        handle_worker_success(state, issue_id, identifier, running_entry, result)

      {:error, reason} ->
        handle_worker_failure(state, issue_id, identifier, reason)
    end
  end

  @doc "Handle a successful worker completion."
  def handle_worker_success(state, issue_id, identifier, running_entry, result) do
    Logger.info("Worker completed issue=#{identifier} result=#{inspect(result)}")

    if state.config.tracker_kind == "local" and running_entry do
      persist_agent_run(issue_id, running_entry)
    end

    if state.config.tracker_kind == "local" do
      # Check if this was a planning phase run
      case SymphonyElixir.LocalBoard.get_issue(issue_id) do
        {:ok, issue} when issue.plan_status == "planning" ->
          # Save the result as the plan and move to plan_review
          plan_text = running_entry[:result_text] || ""

          SymphonyElixir.LocalBoard.update_issue(issue_id, %{
            "plan_status" => "plan_review",
            "plan_text" => plan_text
          })

          SymphonyElixir.LocalBoard.move_issue(issue_id, "Todo")
          Logger.info("Plan delivered for issue=#{identifier}, awaiting review")

        {:ok, issue} ->
          # Check if this is a feature-check issue and update feature status
          maybe_update_feature_status(issue, running_entry)
          # Check if this is a generate-definition issue and update product
          maybe_update_product_definition(issue, running_entry)
          SymphonyElixir.LocalBoard.move_issue(issue_id, resolve_done_state(issue_id))

        _ ->
          SymphonyElixir.LocalBoard.move_issue(issue_id, resolve_done_state(issue_id))
      end
    end

    %{state | completed: MapSet.put(state.completed, issue_id)}
  end

  @doc "Handle a worker failure, scheduling retries or handling token exhaustion."
  def handle_worker_failure(state, issue_id, identifier, reason) do
    Logger.error("Worker failed issue=#{identifier} error=#{inspect(reason)}")

    if token_exhaustion_error?(reason) do
      handle_token_exhaustion(state, issue_id, identifier, reason)
    else
      if state.config.tracker_kind == "local" do
        SymphonyElixir.LocalBoard.move_issue(issue_id, "Todo")
      end

      attempt =
        case Map.get(state.retry_attempts, issue_id) do
          %{attempt: a} -> a + 1
          _ -> 1
        end

      Retry.schedule_failure_retry(
        state,
        state.config,
        issue_id,
        identifier,
        attempt,
        inspect(reason)
      )
    end
  end

  @doc "Handle token/quota exhaustion by moving issues to Backlog and disabling polling."
  def handle_token_exhaustion(state, issue_id, identifier, reason) do
    Logger.warning(
      "Token exhaustion detected for #{identifier}: #{inspect(reason)}. " <>
        "Deactivating auto-polling and moving all in-progress issues to Backlog."
    )

    # Move this failed issue and all other running issues to Backlog
    if state.config.tracker_kind == "local" do
      SymphonyElixir.LocalBoard.move_issue(issue_id, "Backlog")

      for {other_id, entry} <- state.running, other_id != issue_id do
        case SymphonyElixir.LocalBoard.move_issue(other_id, "Backlog") do
          :ok ->
            Logger.info("Moved issue #{entry.identifier} to Backlog (token exhaustion)")

          {:error, move_reason} ->
            Logger.warning(
              "Failed to move #{entry.identifier} to Backlog: #{inspect(move_reason)}"
            )
        end
      end
    end

    %{state | token_budget_exceeded: true}
  end

  @doc "Detect if an error indicates the LLM token quota/budget is exhausted."
  def token_exhaustion_error?(reason) do
    msg = inspect(reason) |> String.downcase()

    Enum.any?(
      [
        "rate limit",
        "rate_limit",
        "ratelimit",
        "quota",
        "token limit",
        "budget exceeded",
        "too many requests",
        "429",
        "resource_exhausted",
        "tokens_exceeded",
        "billing",
        "usage limit",
        "plan limit"
      ],
      &String.contains?(msg, &1)
    )
  end

  @doc "Resolve whether an issue should go to Done or Review based on follow-ups."
  def resolve_done_state(issue_id) do
    case SymphonyElixir.LocalBoard.get_issue(issue_id) do
      {:ok, issue} ->
        follow_ups = (issue[:agent_run] && issue[:agent_run]["follow_ups"]) || []
        if Enum.any?(follow_ups, &(&1["status"] == "proposed")), do: "Review", else: "Done"

      _ ->
        "Done"
    end
  end

  # Update feature status from a feature-check agent result.
  defp maybe_update_feature_status(issue, running_entry) do
    labels = issue.labels || []
    is_feature_check = "feature-check" in labels

    if is_feature_check do
      prod_id = extract_label_value(labels, "product:")
      feature_id = extract_label_value(labels, "feature:")
      project_id = issue.project_id

      if prod_id && feature_id && project_id do
        result_text = running_entry[:result_text] || ""

        case extract_status_verdict(result_text) do
          {:ok, status} ->
            SymphonyElixir.LocalBoard.set_feature_status(
              prod_id,
              feature_id,
              project_id,
              status,
              "agent_check"
            )

            Logger.info(
              "Feature check updated: product=#{prod_id} feature=#{feature_id} " <>
                "project=#{project_id} status=#{status}"
            )

          :error ->
            Logger.warning(
              "Feature check completed but no status-verdict found in result " <>
                "for product=#{prod_id} feature=#{feature_id} project=#{project_id}"
            )
        end
      end
    end
  end

  # Update product definition from a generate-definition agent result.
  defp maybe_update_product_definition(issue, running_entry) do
    labels = issue.labels || []

    if "generate-definition" in labels do
      prod_id = extract_label_value(labels, "product:")

      if prod_id do
        result_text = running_entry[:result_text] || ""

        case extract_product_definition(result_text) do
          {:ok, attrs} ->
            SymphonyElixir.LocalBoard.update_product(prod_id, attrs)

            Logger.info(
              "Product definition updated: product=#{prod_id} name=#{Map.get(attrs, "name", "unchanged")}"
            )

          :error ->
            Logger.warning(
              "Generate-definition completed but no product-definition block found for product=#{prod_id}"
            )
        end
      end
    end
  end

  @doc "Extract a product-definition block from agent result text."
  def extract_product_definition(result_text) when is_binary(result_text) do
    case Regex.run(~r/```product-definition\s*\n([\s\S]*?)```/, result_text) do
      [_, json_str] ->
        case Jason.decode(String.trim(json_str)) do
          {:ok, %{"name" => name, "description" => desc}}
          when is_binary(name) and is_binary(desc) ->
            attrs = %{}
            attrs = if String.trim(name) != "", do: Map.put(attrs, "name", String.trim(name)), else: attrs

            attrs =
              if String.trim(desc) != "",
                do: Map.put(attrs, "description", String.trim(desc)),
                else: attrs

            if map_size(attrs) > 0, do: {:ok, attrs}, else: :error

          _ ->
            :error
        end

      nil ->
        :error
    end
  end

  def extract_product_definition(_), do: :error

  @doc "Extract a status verdict block from agent result text."
  def extract_status_verdict(result_text) when is_binary(result_text) do
    case Regex.run(~r/```status-verdict\s*\n([\s\S]*?)```/, result_text) do
      [_, json_str] ->
        case Jason.decode(String.trim(json_str)) do
          {:ok, %{"status" => status}} when status in ~w(done in_progress missing n_a planned) ->
            {:ok, status}

          _ ->
            :error
        end

      nil ->
        :error
    end
  end

  def extract_status_verdict(_), do: :error

  defp extract_label_value(labels, prefix) do
    Enum.find_value(labels, fn label ->
      if String.starts_with?(label, prefix) do
        String.replace_prefix(label, prefix, "")
      end
    end)
  end

  @doc "Extract follow-up items from agent result text."
  def extract_follow_ups(result_text) when is_binary(result_text) do
    case Regex.run(~r/```follow-ups\s*\n([\s\S]*?)```/, result_text) do
      [_, json_str] ->
        case Jason.decode(json_str) do
          {:ok, list} when is_list(list) ->
            Enum.map(list, fn item ->
              %{
                "id" => "fu_" <> Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false),
                "title" => item["title"] || "Untitled follow-up",
                "description" => item["description"],
                "category" => item["category"],
                "depends_on" => item["depends_on"] || [],
                "project_ids" => item["project_ids"] || [],
                "statuses" => item["statuses"] || %{},
                "labels" => item["labels"] || [],
                "priority" => item["priority"] || 3,
                "status" => "proposed"
              }
            end)

          _ ->
            []
        end

      nil ->
        []
    end
  end

  def extract_follow_ups(_), do: []

  @doc "Persist the agent run data (event log, tokens, follow-ups) to the local board."
  def persist_agent_run(issue_id, running_entry) do
    event_log = Enum.map(running_entry[:event_log] || [], &event_to_json/1)
    tokens = normalize_tokens(running_entry[:tokens])

    follow_ups =
      case SymphonyElixir.LocalBoard.get_issue(issue_id) do
        {:ok, issue} when issue.propose_followups != false ->
          extract_follow_ups(running_entry[:result_text])

        _ ->
          []
      end

    run_data = %{
      "event_log" => event_log,
      "result_text" => running_entry[:result_text],
      "tokens" => tokens,
      "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "follow_ups" => follow_ups
    }

    try do
      SymphonyElixir.LocalBoard.save_agent_run(issue_id, run_data)
    catch
      kind, reason ->
        Logger.warning("Failed to persist agent run: #{kind} #{inspect(reason)}")
    end
  end

  @doc "Load follow-ups for an issue from the local board."
  def load_follow_ups(nil), do: []

  def load_follow_ups(running_entry) do
    issue_id = running_entry[:issue_id]

    if issue_id do
      case SymphonyElixir.LocalBoard.get_issue(issue_id) do
        {:ok, issue} ->
          (issue[:agent_run] && issue[:agent_run]["follow_ups"]) || []

        _ ->
          []
      end
    else
      []
    end
  end

  # --- Private Helpers ---

  defp running_entry_identifier(nil), do: "unknown"
  defp running_entry_identifier(entry), do: entry[:identifier] || "unknown"

  defp preserve_completed_run(state, _issue_id, nil, identifier) do
    Logger.warning("No running entry to preserve for #{identifier}")
    state
  end

  defp preserve_completed_run(state, issue_id, running_entry, identifier) do
    event_count = length(running_entry[:event_log] || [])
    tokens = running_entry[:tokens]

    Logger.info(
      "Preserving completed run for #{identifier}: #{event_count} events, tokens=#{inspect(tokens)}"
    )

    %{state | completed_runs: Map.put(state.completed_runs, issue_id, running_entry)}
  end

  defp event_to_json(ev) do
    %{
      "event" => to_string(ev[:event] || "unknown"),
      "timestamp" => to_string(ev[:timestamp] || ""),
      "message" => ev[:message],
      "tool" => ev[:tool],
      "detail" => ev[:detail],
      "line" => ev[:line]
    }
  end

  @doc "Normalize token counts to a string-keyed map."
  def normalize_tokens(nil),
    do: %{"input_tokens" => 0, "output_tokens" => 0, "total_tokens" => 0}

  def normalize_tokens(t) do
    %{
      "input_tokens" => t[:input_tokens] || 0,
      "output_tokens" => t[:output_tokens] || 0,
      "total_tokens" => t[:total_tokens] || 0
    }
  end
end

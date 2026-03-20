defmodule SymphonyElixir.Orchestrator.Maintenance do
  @moduledoc """
  Automated maintenance tasks for the orchestrator.

  Handles auto-archiving of completed issues and auto-promoting
  backlog issues to the todo queue.
  """

  require Logger

  alias SymphonyElixir.{DateTimeUtils, ParseUtils}

  @archive_after_days 1

  @doc "Auto-archive Done issues older than the configured threshold."
  @spec auto_archive_done_issues() :: :ok
  def auto_archive_done_issues do
    case SymphonyElixir.LocalBoard.list_issues_by_states(["Done"]) do
      issues when is_list(issues) ->
        cutoff = DateTime.utc_now() |> DateTime.add(-@archive_after_days * 86_400, :second)

        Enum.each(issues, fn issue ->
          completed_at = get_completed_at(issue)

          if completed_at && DateTime.compare(completed_at, cutoff) == :lt do
            Logger.info("Auto-archiving #{issue.identifier} (completed #{completed_at})")
            SymphonyElixir.LocalBoard.move_issue(issue.id, "Archived")
          end
        end)

      _ ->
        :ok
    end
  end

  @doc "Auto-promote backlog issues to Todo when slots are available."
  @spec auto_promote_backlog_to_todo() :: :ok
  def auto_promote_backlog_to_todo do
    if SymphonyElixir.Settings.get("auto_add_enabled") == "true" do
      max = parse_max_todo(SymphonyElixir.Settings.get("max_todo_parallel"))

      active_issues = SymphonyElixir.LocalBoard.list_issues_by_states(["Todo", "In Progress"])
      backlog_issues = SymphonyElixir.LocalBoard.list_issues_by_states(["Backlog"])

      # Group by project_id (nil = unassigned); count Todo + In Progress together
      todo_by_project = Enum.group_by(active_issues, & &1.project_id)
      backlog_by_project = Enum.group_by(backlog_issues, & &1.project_id)

      Enum.each(backlog_by_project, fn {project_id, candidates} ->
        current_count = length(Map.get(todo_by_project, project_id, []))
        slots = max - current_count

        if slots > 0 do
          candidates
          |> Enum.sort_by(& &1.priority)
          |> Enum.take(slots)
          |> Enum.each(fn issue ->
            Logger.info("Auto-promoting #{issue.identifier} from Backlog to Todo")
            SymphonyElixir.LocalBoard.move_issue(issue.id, "Todo")
          end)
        end
      end)
    end
  end

  defp parse_max_todo(val) when is_binary(val) do
    ParseUtils.parse_int(val, 3) |> max(1) |> min(3)
  end

  defp parse_max_todo(_), do: 3

  defp get_completed_at(issue) do
    # Try agent_run completed_at, then fall back to updated_at
    dt_str =
      (issue[:agent_run] && issue[:agent_run]["completed_at"]) ||
        issue[:updated_at] || issue.updated_at

    case dt_str do
      %DateTime{} = dt -> dt
      str when is_binary(str) -> DateTimeUtils.parse_datetime(str)
      _ -> nil
    end
  end
end

defmodule SymphonyElixir.Orchestrator.Dispatch do
  @moduledoc """
  Dispatch logic: candidate selection, sorting, and eligibility checking.

  See SPEC Section 8.2-8.3.
  """

  alias SymphonyElixir.{Config, Issue}
  alias SymphonyElixir.Orchestrator.State

  @doc """
  Filter and sort candidate issues for dispatch.
  Returns a list of dispatch-eligible issues sorted by priority.
  """
  @spec select_dispatchable(Config.t(), State.t(), [Issue.t()]) :: [Issue.t()]
  def select_dispatchable(%Config{} = config, %State{} = state, candidates) do
    active_set = Config.active_state_set(config)
    terminal_set = Config.terminal_state_set(config)

    candidates
    |> Enum.filter(&eligible?(&1, config, state, active_set, terminal_set))
    |> sort_by_priority()
  end

  @doc "Check if a single issue is eligible for dispatch."
  @spec eligible?(Issue.t(), Config.t(), State.t(), MapSet.t(), MapSet.t()) :: boolean()
  def eligible?(%Issue{} = issue, %Config{} = config, %State{} = state, active_set, terminal_set) do
    Issue.valid_for_dispatch?(issue) and
      in_active_state?(issue, active_set) and
      not in_terminal_state?(issue, terminal_set) and
      not State.running?(state, issue.id) and
      not State.claimed?(state, issue.id) and
      not MapSet.member?(state.completed, issue.id) and
      global_slots_available?(state, config) and
      per_state_slots_available?(state, config, issue.state) and
      not blocked_in_todo?(issue, terminal_set) and
      not awaiting_plan_review?(issue)
  end

  @doc "Sort issues by dispatch priority per SPEC Section 8.2."
  @spec sort_by_priority([Issue.t()]) :: [Issue.t()]
  def sort_by_priority(issues) do
    Enum.sort_by(issues, fn issue ->
      {
        priority_sort_key(issue.priority),
        issue.created_at || ~U[2099-12-31 23:59:59Z],
        issue.identifier || ""
      }
    end)
  end

  # --- Private helpers ---

  defp in_active_state?(%Issue{state: state}, active_set) do
    normalized = Issue.normalize_state(state)
    MapSet.member?(active_set, normalized)
  end

  defp in_terminal_state?(%Issue{state: state}, terminal_set) do
    normalized = Issue.normalize_state(state)
    MapSet.member?(terminal_set, normalized)
  end

  defp global_slots_available?(%State{} = state, %Config{} = config) do
    State.available_slots(state, config.max_concurrent_agents) > 0
  end

  defp per_state_slots_available?(%State{} = state, %Config{} = config, issue_state) do
    normalized = Issue.normalize_state(issue_state)

    case Map.get(config.max_concurrent_agents_by_state, normalized) do
      nil ->
        true

      limit when is_integer(limit) and limit > 0 ->
        current = State.running_count_by_state(state, normalized)
        current < limit

      _ ->
        true
    end
  end

  defp blocked_in_todo?(%Issue{} = issue, terminal_set) do
    normalized_state = Issue.normalize_state(issue.state)

    if normalized_state == "todo" do
      Issue.has_non_terminal_blockers?(issue, terminal_set)
    else
      false
    end
  end

  defp awaiting_plan_review?(%Issue{plan_status: "plan_review"}), do: true
  defp awaiting_plan_review?(_), do: false

  defp priority_sort_key(nil), do: 999
  defp priority_sort_key(p) when is_integer(p) and p >= 1 and p <= 4, do: p
  defp priority_sort_key(_), do: 999
end

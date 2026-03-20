defmodule SymphonyElixir.LocalBoard.Issues do
  @moduledoc """
  Issue-related operations for the local board.

  All functions receive and return the board state struct, making them
  pure (aside from persistence side-effects delegated to `Persistence`).
  """

  alias SymphonyElixir.Issue
  alias SymphonyElixir.LocalBoard.Persistence

  import SymphonyElixir.LocalBoard.Helpers

  # --- handle_call delegates ---

  def list_issues(board) do
    issues = board.issues |> Map.values() |> sort_issues()
    {:reply, issues, board}
  end

  def list_issues_by_states(board, state_names) do
    normalized = MapSet.new(state_names, &String.downcase/1)

    issues =
      board.issues
      |> Map.values()
      |> Enum.filter(fn i -> MapSet.member?(normalized, String.downcase(i.state)) end)
      |> sort_issues()

    {:reply, issues, board}
  end

  def get_issue(board, id) do
    case Map.get(board.issues, id) do
      nil -> {:reply, {:error, :not_found}, board}
      issue -> {:reply, {:ok, issue}, board}
    end
  end

  def get_issues_by_ids(board, ids) do
    issues =
      ids
      |> Enum.map(&Map.get(board.issues, &1))
      |> Enum.reject(&is_nil/1)

    {:reply, issues, board}
  end

  def create_issue(board, attrs) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    id = generate_id()
    identifier = "#{board.project_prefix}-#{board.next_number}"

    issue = %{
      id: id,
      identifier: identifier,
      title: Map.get(attrs, "title", "Untitled"),
      description: Map.get(attrs, "description"),
      priority: parse_priority(Map.get(attrs, "priority", 0)),
      state: Map.get(attrs, "state", hd(board.states)),
      branch_name: Map.get(attrs, "branch_name"),
      url: nil,
      labels: parse_labels(Map.get(attrs, "labels", [])),
      project_id: Map.get(attrs, "project_id"),
      product_id: Map.get(attrs, "product_id"),
      parent_issue_id: Map.get(attrs, "parent_issue_id"),
      propose_followups: Map.get(attrs, "propose_followups", true) != false,
      skill_ids: parse_labels(Map.get(attrs, "skill_ids", [])),
      skill_group_ids: parse_labels(Map.get(attrs, "skill_group_ids", [])),
      plan_status: Map.get(attrs, "plan_status"),
      plan_text: Map.get(attrs, "plan_text"),
      rerun_hint: nil,
      created_at: now,
      updated_at: now
    }

    board = %{
      board
      | issues: Map.put(board.issues, id, issue),
        next_number: board.next_number + 1
    }

    Persistence.persist(board)

    {:reply, {:ok, issue}, board}
  end

  def update_issue(board, id, attrs) do
    case Map.get(board.issues, id) do
      nil ->
        {:reply, {:error, :not_found}, board}

      existing ->
        now = DateTime.utc_now() |> DateTime.to_iso8601()

        updated =
          existing
          |> maybe_update(:title, attrs)
          |> maybe_update(:description, attrs)
          |> maybe_update(:priority, attrs, &parse_priority/1)
          |> maybe_update(:state, attrs)
          |> maybe_update(:branch_name, attrs)
          |> maybe_update(:labels, attrs, &parse_labels/1)
          |> maybe_update(:project_id, attrs)
          |> maybe_update(:product_id, attrs)
          |> maybe_update(:propose_followups, attrs, &parse_boolean/1)
          |> maybe_update(:skill_ids, attrs, &parse_labels/1)
          |> maybe_update(:skill_group_ids, attrs, &parse_labels/1)
          |> maybe_update(:plan_status, attrs)
          |> maybe_update(:plan_text, attrs)
          |> maybe_update(:rerun_hint, attrs)
          |> maybe_update(:kb_synced_at, attrs)
          |> Map.put(:updated_at, now)

        board = %{board | issues: Map.put(board.issues, id, updated)}
        Persistence.persist(board)

        {:reply, {:ok, updated}, board}
    end
  end

  def move_issue(board, id, new_state) do
    case Map.get(board.issues, id) do
      nil ->
        {:reply, {:error, :not_found}, board}

      existing ->
        now = DateTime.utc_now() |> DateTime.to_iso8601()
        updated = %{existing | state: new_state, updated_at: now}
        board = %{board | issues: Map.put(board.issues, id, updated)}
        Persistence.persist(board)

        {:reply, {:ok, updated}, board}
    end
  end

  def delete_issue(board, id) do
    if Map.has_key?(board.issues, id) do
      board = %{board | issues: Map.delete(board.issues, id)}
      Persistence.persist(board)
      {:reply, :ok, board}
    else
      {:reply, {:error, :not_found}, board}
    end
  end

  def save_agent_run(board, issue_id, run_data) do
    case Map.get(board.issues, issue_id) do
      nil ->
        {:reply, {:error, :not_found}, board}

      issue ->
        updated = Map.put(issue, :agent_run, run_data)
        board = %{board | issues: Map.put(board.issues, issue_id, updated)}
        Persistence.persist(board)
        {:reply, :ok, board}
    end
  end

  def list_states(board) do
    {:reply, board.states, board}
  end

  def get_board_snapshot(board) do
    columns =
      Enum.map(board.states, fn state ->
        issues =
          board.issues
          |> Map.values()
          |> Enum.filter(fn i -> i.state == state end)
          |> sort_issues()

        %{state: state, issues: issues}
      end)

    snapshot = %{
      states: board.states,
      columns: columns,
      total_issues: map_size(board.issues),
      project_prefix: board.project_prefix,
      projects: Map.values(board.projects)
    }

    {:reply, snapshot, board}
  end

  # --- Conversion to Issue struct (for behaviour compatibility) ---

  @doc "Convert an internal issue record to an `Issue` struct."
  def to_issue_struct(record) do
    %Issue{
      id: record.id,
      identifier: record.identifier,
      title: record.title,
      description: record.description,
      priority: record.priority,
      state: record.state,
      branch_name: record.branch_name,
      url: record.url,
      labels: record.labels || [],
      blocked_by: [],
      project_id: record[:project_id],
      product_id: record[:product_id],
      parent_issue_id: record[:parent_issue_id],
      propose_followups: Map.get(record, :propose_followups, true) != false,
      skill_ids: Map.get(record, :skill_ids, []),
      skill_group_ids: Map.get(record, :skill_group_ids, []),
      plan_status: record[:plan_status],
      plan_text: record[:plan_text],
      rerun_hint: record[:rerun_hint],
      created_at: SymphonyElixir.DateTimeUtils.parse_datetime(record.created_at),
      updated_at: SymphonyElixir.DateTimeUtils.parse_datetime(record.updated_at)
    }
  end
end

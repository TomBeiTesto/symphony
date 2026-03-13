defmodule SymphonyElixir.LocalBoard.Skills do
  @moduledoc """
  Skill and skill-group operations for the local board.

  Handles CRUD for skills and skill groups, skill duplication,
  and resolving skills for issues and templates.
  All functions receive and return the board state struct.
  """

  alias SymphonyElixir.LocalBoard.Persistence

  import SymphonyElixir.LocalBoard.Helpers

  # --- Skill handle_call delegates ---

  def list_skills(board) do
    skills = board.skills |> Map.values() |> Enum.sort_by(& &1.name)
    {:reply, skills, board}
  end

  def get_skill(board, id) do
    case Map.get(board.skills, id) do
      nil -> {:reply, {:error, :not_found}, board}
      skill -> {:reply, {:ok, skill}, board}
    end
  end

  def get_skills_by_ids(board, ids) do
    skills =
      ids
      |> Enum.map(&Map.get(board.skills, &1))
      |> Enum.reject(&is_nil/1)

    {:reply, skills, board}
  end

  def create_skill(board, attrs) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    id = generate_id()

    skill = %{
      id: id,
      name: Map.get(attrs, "name", "Untitled Skill"),
      description: Map.get(attrs, "description"),
      content: Map.get(attrs, "content", ""),
      category: Map.get(attrs, "category", "custom"),
      tags: parse_labels(Map.get(attrs, "tags", [])),
      built_in: Map.get(attrs, "built_in", false) == true,
      created_at: now,
      updated_at: now
    }

    board = %{board | skills: Map.put(board.skills, id, skill)}
    Persistence.persist(board)
    {:reply, {:ok, skill}, board}
  end

  def update_skill(board, id, attrs) do
    case Map.get(board.skills, id) do
      nil ->
        {:reply, {:error, :not_found}, board}

      existing ->
        now = DateTime.utc_now() |> DateTime.to_iso8601()

        updated =
          existing
          |> maybe_update(:name, attrs)
          |> maybe_update(:description, attrs)
          |> maybe_update(:content, attrs)
          |> maybe_update(:category, attrs)
          |> maybe_update(:tags, attrs, &parse_labels/1)
          |> Map.put(:updated_at, now)

        board = %{board | skills: Map.put(board.skills, id, updated)}
        Persistence.persist(board)
        {:reply, {:ok, updated}, board}
    end
  end

  def delete_skill(board, id) do
    case Map.get(board.skills, id) do
      nil ->
        {:reply, {:error, :not_found}, board}

      %{built_in: true} ->
        {:reply, {:error, :built_in}, board}

      _ ->
        # Remove skill from all skill groups and issues
        skill_groups =
          Map.new(board.skill_groups, fn {gid, group} ->
            {gid, %{group | skill_ids: List.delete(group.skill_ids, id)}}
          end)

        issues =
          Map.new(board.issues, fn {iid, issue} ->
            updated_skill_ids = List.delete(Map.get(issue, :skill_ids, []), id)
            {iid, Map.put(issue, :skill_ids, updated_skill_ids)}
          end)

        board = %{
          board
          | skills: Map.delete(board.skills, id),
            skill_groups: skill_groups,
            issues: issues
        }

        Persistence.persist(board)
        {:reply, :ok, board}
    end
  end

  def duplicate_skill(board, id) do
    case Map.get(board.skills, id) do
      nil ->
        {:reply, {:error, :not_found}, board}

      original ->
        now = DateTime.utc_now() |> DateTime.to_iso8601()
        new_id = generate_id()

        copy = %{
          original
          | id: new_id,
            name: original.name <> " (copy)",
            built_in: false,
            created_at: now,
            updated_at: now
        }

        board = %{board | skills: Map.put(board.skills, new_id, copy)}
        Persistence.persist(board)
        {:reply, {:ok, copy}, board}
    end
  end

  # --- Skill Groups handle_call delegates ---

  def list_skill_groups(board) do
    groups = board.skill_groups |> Map.values() |> Enum.sort_by(& &1.name)
    {:reply, groups, board}
  end

  def get_skill_group(board, id) do
    case Map.get(board.skill_groups, id) do
      nil -> {:reply, {:error, :not_found}, board}
      group -> {:reply, {:ok, group}, board}
    end
  end

  def create_skill_group(board, attrs) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    id = generate_id()

    group = %{
      id: id,
      name: Map.get(attrs, "name", "Untitled Group"),
      description: Map.get(attrs, "description"),
      skill_ids: Map.get(attrs, "skill_ids", []),
      created_at: now,
      updated_at: now
    }

    board = %{board | skill_groups: Map.put(board.skill_groups, id, group)}
    Persistence.persist(board)
    {:reply, {:ok, group}, board}
  end

  def update_skill_group(board, id, attrs) do
    case Map.get(board.skill_groups, id) do
      nil ->
        {:reply, {:error, :not_found}, board}

      existing ->
        now = DateTime.utc_now() |> DateTime.to_iso8601()

        updated =
          existing
          |> maybe_update(:name, attrs)
          |> maybe_update(:description, attrs)
          |> maybe_update(:skill_ids, attrs)
          |> Map.put(:updated_at, now)

        board = %{board | skill_groups: Map.put(board.skill_groups, id, updated)}
        Persistence.persist(board)
        {:reply, {:ok, updated}, board}
    end
  end

  def delete_skill_group(board, id) do
    if Map.has_key?(board.skill_groups, id) do
      # Remove group from all issues
      issues =
        Map.new(board.issues, fn {iid, issue} ->
          updated_group_ids = List.delete(Map.get(issue, :skill_group_ids, []), id)
          {iid, Map.put(issue, :skill_group_ids, updated_group_ids)}
        end)

      board = %{
        board
        | skill_groups: Map.delete(board.skill_groups, id),
          issues: issues
      }

      Persistence.persist(board)
      {:reply, :ok, board}
    else
      {:reply, {:error, :not_found}, board}
    end
  end

  def resolve_issue_skills(board, issue) do
    direct_ids = Map.get(issue, :skill_ids, [])
    group_ids = Map.get(issue, :skill_group_ids, [])

    group_skill_ids =
      group_ids
      |> Enum.flat_map(fn gid ->
        case Map.get(board.skill_groups, gid) do
          nil -> []
          group -> group.skill_ids
        end
      end)

    all_ids = Enum.uniq(direct_ids ++ group_skill_ids)

    skills =
      all_ids
      |> Enum.map(&Map.get(board.skills, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(fn s -> {s.category, s.name} end)

    {:reply, skills, board}
  end
end

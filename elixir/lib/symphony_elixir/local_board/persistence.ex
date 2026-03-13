defmodule SymphonyElixir.LocalBoard.Persistence do
  @moduledoc """
  JSON file persistence for the local board.

  Handles saving board state to disk, loading it back, and all
  JSON serialization/deserialization for every record type.
  """

  require Logger

  alias SymphonyElixir.LocalBoard

  @doc "Persist the full board state to its JSON file."
  def persist(%LocalBoard{} = board) do
    data = %{
      "issues" => Map.values(board.issues) |> Enum.map(&issue_to_json/1),
      "projects" => Map.values(board.projects) |> Enum.map(&project_to_json/1),
      "products" => Map.values(board.products) |> Enum.map(&product_to_json/1),
      "skills" => Map.values(board.skills) |> Enum.map(&skill_to_json/1),
      "skill_groups" => Map.values(board.skill_groups) |> Enum.map(&skill_group_to_json/1),
      "states" => board.states,
      "next_number" => board.next_number,
      "project_prefix" => board.project_prefix
    }

    json = Jason.encode!(data, pretty: true)
    File.write!(board.store_path, json)
  end

  @doc "Load board state from its JSON file on disk."
  def load_from_disk(%LocalBoard{} = board) do
    case File.read(board.store_path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, data} ->
            issues_list = Map.get(data, "issues", [])

            issues =
              Map.new(issues_list, fn raw ->
                issue = json_to_issue(raw)
                {issue.id, issue}
              end)

            max_number =
              issues_list
              |> Enum.map(fn raw ->
                id_str = Map.get(raw, "identifier", "X-0")

                case String.split(id_str, "-") |> List.last() |> Integer.parse() do
                  {n, ""} -> n
                  _ -> 0
                end
              end)
              |> Enum.max(fn -> 0 end)

            projects_list = Map.get(data, "projects", [])

            projects =
              Map.new(projects_list, fn raw ->
                project = json_to_project(raw)
                {project.id, project}
              end)

            # Support legacy "compositions" key for backward compatibility
            products_list = Map.get(data, "products", Map.get(data, "compositions", []))

            products =
              Map.new(products_list, fn raw ->
                prod = json_to_product(raw)
                {prod.id, prod}
              end)

            skills_list = Map.get(data, "skills", [])

            skills =
              Map.new(skills_list, fn raw ->
                skill = json_to_skill(raw)
                {skill.id, skill}
              end)

            skill_groups_list = Map.get(data, "skill_groups", [])

            skill_groups =
              Map.new(skill_groups_list, fn raw ->
                group = json_to_skill_group(raw)
                {group.id, group}
              end)

            %{
              board
              | issues: issues,
                projects: projects,
                products: products,
                skills: skills,
                skill_groups: skill_groups,
                states: merge_states(Map.get(data, "states", board.states), board.states),
                next_number: max(Map.get(data, "next_number", max_number + 1), max_number + 1),
                project_prefix: Map.get(data, "project_prefix", board.project_prefix)
            }

          {:error, _} ->
            Logger.warning("Corrupt board file at #{board.store_path}, starting fresh")
            board
        end

      {:error, :enoent} ->
        board

      {:error, reason} ->
        Logger.warning("Failed to read #{board.store_path}: #{inspect(reason)}, starting fresh")
        board
    end
  end

  # --- JSON serialization ---

  def issue_to_json(issue) do
    base = %{
      "id" => issue.id,
      "identifier" => issue.identifier,
      "title" => issue.title,
      "description" => issue.description,
      "priority" => issue.priority,
      "state" => issue.state,
      "branch_name" => issue.branch_name,
      "url" => issue.url,
      "labels" => issue.labels,
      "project_id" => issue[:project_id],
      "product_id" => issue[:product_id],
      "parent_issue_id" => issue[:parent_issue_id],
      "propose_followups" => Map.get(issue, :propose_followups, true),
      "skill_ids" => Map.get(issue, :skill_ids, []),
      "skill_group_ids" => Map.get(issue, :skill_group_ids, []),
      "plan_status" => issue[:plan_status],
      "plan_text" => issue[:plan_text],
      "created_at" => issue.created_at,
      "updated_at" => issue.updated_at
    }

    case issue[:agent_run] do
      nil -> base
      run -> Map.put(base, "agent_run", run)
    end
  end

  def json_to_issue(raw) do
    base = %{
      id: raw["id"],
      identifier: raw["identifier"],
      title: raw["title"],
      description: raw["description"],
      priority: raw["priority"] || 0,
      state: raw["state"] || "Backlog",
      branch_name: raw["branch_name"],
      url: raw["url"],
      labels: raw["labels"] || [],
      project_id: raw["project_id"],
      product_id: raw["product_id"],
      parent_issue_id: raw["parent_issue_id"],
      propose_followups: Map.get(raw, "propose_followups", true) != false,
      skill_ids: raw["skill_ids"] || [],
      skill_group_ids: raw["skill_group_ids"] || [],
      plan_status: raw["plan_status"],
      plan_text: raw["plan_text"],
      created_at: raw["created_at"],
      updated_at: raw["updated_at"]
    }

    case raw["agent_run"] do
      nil -> base
      run -> Map.put(base, :agent_run, run)
    end
  end

  def project_to_json(project) do
    %{
      "id" => project.id,
      "name" => project.name,
      "slug" => project.slug,
      "path" => project.path,
      "repo_url" => project.repo_url,
      "description" => project.description,
      "tags" => Map.get(project, :tags, []),
      "created_at" => project.created_at,
      "updated_at" => project.updated_at
    }
  end

  def json_to_project(raw) do
    %{
      id: raw["id"],
      name: raw["name"],
      slug: raw["slug"],
      path: raw["path"],
      repo_url: raw["repo_url"],
      description: raw["description"],
      tags: raw["tags"] || [],
      created_at: raw["created_at"],
      updated_at: raw["updated_at"]
    }
  end

  def product_to_json(prod) do
    %{
      "id" => prod.id,
      "name" => prod.name,
      "description" => prod.description,
      "project_ids" => prod.project_ids,
      "features" =>
        Enum.map(prod.features, fn f ->
          %{
            "id" => f.id,
            "name" => f.name,
            "description" => f.description,
            "category" => f[:category],
            "depends_on" => Map.get(f, :depends_on, []),
            "statuses" => f.statuses,
            "status_history" =>
              Enum.map(Map.get(f, :status_history, []), fn h ->
                %{
                  "project_id" => h.project_id,
                  "status" => h.status,
                  "changed_at" => h.changed_at,
                  "source" => h.source
                }
              end)
          }
        end),
      "created_at" => prod.created_at,
      "updated_at" => prod.updated_at
    }
  end

  def json_to_product(raw) do
    %{
      id: raw["id"],
      name: raw["name"],
      description: raw["description"],
      project_ids: raw["project_ids"] || [],
      features:
        Enum.map(raw["features"] || [], fn f ->
          %{
            id: f["id"],
            name: f["name"],
            description: f["description"],
            category: f["category"],
            depends_on: f["depends_on"] || [],
            statuses: f["statuses"] || %{},
            status_history:
              Enum.map(f["status_history"] || [], fn h ->
                %{
                  project_id: h["project_id"],
                  status: h["status"],
                  changed_at: h["changed_at"],
                  source: h["source"]
                }
              end)
          }
        end),
      created_at: raw["created_at"],
      updated_at: raw["updated_at"]
    }
  end

  def skill_to_json(skill) do
    %{
      "id" => skill.id,
      "name" => skill.name,
      "description" => skill.description,
      "content" => skill.content,
      "category" => skill.category,
      "tags" => skill.tags,
      "built_in" => skill.built_in,
      "created_at" => skill.created_at,
      "updated_at" => skill.updated_at
    }
  end

  def json_to_skill(raw) do
    %{
      id: raw["id"],
      name: raw["name"],
      description: raw["description"],
      content: raw["content"] || "",
      category: raw["category"] || "custom",
      tags: raw["tags"] || [],
      built_in: raw["built_in"] == true,
      created_at: raw["created_at"],
      updated_at: raw["updated_at"]
    }
  end

  def skill_group_to_json(group) do
    %{
      "id" => group.id,
      "name" => group.name,
      "description" => group.description,
      "skill_ids" => group.skill_ids,
      "created_at" => group.created_at,
      "updated_at" => group.updated_at
    }
  end

  def json_to_skill_group(raw) do
    %{
      id: raw["id"],
      name: raw["name"],
      description: raw["description"],
      skill_ids: raw["skill_ids"] || [],
      created_at: raw["created_at"],
      updated_at: raw["updated_at"]
    }
  end

  # Ensure any new default states are inserted in the correct position.
  # Persisted states take priority; missing defaults are spliced in
  # just before the state that follows them in the defaults list.
  defp merge_states(persisted, defaults) do
    missing = defaults -- persisted

    Enum.reduce(missing, persisted, fn state, acc ->
      idx = Enum.find_index(defaults, &(&1 == state))
      # Find the next default state that already exists in acc
      insert_before =
        defaults
        |> Enum.drop(idx + 1)
        |> Enum.find(&(&1 in acc))

      case insert_before do
        nil -> acc ++ [state]
        anchor -> List.insert_at(acc, Enum.find_index(acc, &(&1 == anchor)), state)
      end
    end)
  end
end

defmodule SymphonyElixir.LocalBoard.Persistence do
  @moduledoc """
  JSON file persistence for the local board.

  Handles saving board state to disk, loading it back, and all
  JSON serialization/deserialization for every record type.
  """

  require Logger

  alias SymphonyElixir.LocalBoard

  @max_backups 10

  @doc "Persist the full board state to its JSON file. Creates a rotating backup first."
  def persist(%LocalBoard{} = board) do
    # Rotate backup before overwriting
    rotate_backup(board.store_path)

    data = %{
      "issues" => Map.values(board.issues) |> Enum.map(&issue_to_json/1),
      "projects" => Map.values(board.projects) |> Enum.map(&project_to_json/1),
      "products" => Map.values(board.products) |> Enum.map(&product_to_json/1),
      "skills" => Map.values(board.skills) |> Enum.map(&skill_to_json/1),
      "skill_groups" => Map.values(board.skill_groups) |> Enum.map(&skill_group_to_json/1),
      "pipelines" => Map.values(board.pipelines) |> Enum.map(&pipeline_to_json/1),
      "pipeline_runs" => Map.values(board.pipeline_runs) |> Enum.map(&pipeline_run_to_json/1),
      "states" => board.states,
      "next_number" => board.next_number,
      "project_prefix" => board.project_prefix
    }

    json = Jason.encode!(data, pretty: true)
    File.write!(board.store_path, json)
  end

  @doc "List available backup files (newest first)."
  def list_backups(store_path) do
    backup_dir = backup_dir(store_path)

    case File.ls(backup_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.sort(:desc)
        |> Enum.map(fn f ->
          path = Path.join(backup_dir, f)
          stat = File.stat!(path)
          %{filename: f, path: path, size: stat.size, modified: stat.mtime}
        end)

      {:error, _} ->
        []
    end
  end

  @doc "Restore board state from a specific backup file."
  def restore_backup(%LocalBoard{} = board, backup_filename) do
    backup_path = Path.join(backup_dir(board.store_path), backup_filename)

    case File.read(backup_path) do
      {:ok, contents} ->
        # Write backup contents as the current board file
        File.write!(board.store_path, contents)
        # Reload the board from disk
        {:ok, load_from_disk(board)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp backup_dir(store_path) do
    dir = Path.join(Path.dirname(store_path), "backups")
    File.mkdir_p!(dir)
    dir
  end

  defp rotate_backup(store_path) do
    if File.exists?(store_path) do
      dir = backup_dir(store_path)
      timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d_%H%M%S")
      base = Path.basename(store_path, ".json")
      backup_name = "#{base}_#{timestamp}.json"
      backup_path = Path.join(dir, backup_name)

      with {:ok, contents} <- File.read(store_path),
           :ok <- File.write(backup_path, contents) do
        prune_old_backups(dir, base)
      else
        {:error, reason} ->
          Logger.warning("Failed to create backup: #{inspect(reason)}")
      end
    end
  end

  defp prune_old_backups(dir, base) do
    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.starts_with?(&1, base))
        |> Enum.sort(:desc)
        |> Enum.drop(@max_backups)
        |> Enum.each(fn f ->
          case File.rm(Path.join(dir, f)) do
            :ok -> :ok
            {:error, reason} -> Logger.warning("Failed to prune backup #{f}: #{inspect(reason)}")
          end
        end)

      {:error, _} ->
        :ok
    end
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

            pipelines_list = Map.get(data, "pipelines", [])

            pipelines =
              Map.new(pipelines_list, fn raw ->
                pipeline = json_to_pipeline(raw)
                {pipeline.id, pipeline}
              end)

            pipeline_runs_list = Map.get(data, "pipeline_runs", [])

            pipeline_runs =
              Map.new(pipeline_runs_list, fn raw ->
                run = json_to_pipeline_run(raw)
                {run.id, run}
              end)

            %{
              board
              | issues: issues,
                projects: projects,
                products: products,
                skills: skills,
                skill_groups: skill_groups,
                pipelines: pipelines,
                pipeline_runs: pipeline_runs,
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
      "rerun_hint" => issue[:rerun_hint],
      "created_at" => issue.created_at,
      "updated_at" => issue.updated_at,
      "kb_synced_at" => issue[:kb_synced_at]
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
      rerun_hint: raw["rerun_hint"],
      created_at: raw["created_at"],
      updated_at: raw["updated_at"],
      kb_synced_at: raw["kb_synced_at"]
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

  # --- Pipeline serialization ---

  def pipeline_to_json(pipeline) do
    %{
      "id" => pipeline.id,
      "name" => pipeline.name,
      "description" => pipeline.description,
      "product_id" => pipeline[:product_id],
      "nodes" =>
        Enum.map(pipeline.nodes, fn n ->
          %{
            "id" => n.id,
            "type" => n.type,
            "issue_id" => n[:issue_id],
            "label" => n.label,
            "config" => n[:config] || %{},
            "position" => %{"x" => n.position.x, "y" => n.position.y},
            "loop_max_retries" => n[:loop_max_retries],
            "loop_condition" => n[:loop_condition]
          }
        end),
      "edges" =>
        Enum.map(pipeline.edges, fn e ->
          %{
            "id" => e.id,
            "source_node_id" => e.source_node_id,
            "target_node_id" => e.target_node_id,
            "source_port" => e[:source_port] || "output",
            "label" => e[:label]
          }
        end),
      "settings" => %{
        "max_retries" => (pipeline.settings || %{})[:max_retries] || %{},
        "notifications" => (pipeline.settings || %{})[:notifications] != false,
        "integrations" => (pipeline.settings || %{})[:integrations] || %{}
      },
      "created_at" => pipeline.created_at,
      "updated_at" => pipeline.updated_at
    }
  end

  def json_to_pipeline(raw) do
    %{
      id: raw["id"],
      name: raw["name"],
      description: raw["description"],
      product_id: raw["product_id"],
      nodes:
        Enum.map(raw["nodes"] || [], fn n ->
          pos = n["position"] || %{}

          %{
            id: n["id"],
            type: n["type"] || "issue",
            issue_id: n["issue_id"],
            label: n["label"] || "",
            config: n["config"] || %{},
            position: %{x: (pos["x"] || 0) * 1.0, y: (pos["y"] || 0) * 1.0},
            loop_max_retries: n["loop_max_retries"],
            loop_condition: n["loop_condition"]
          }
        end),
      edges:
        Enum.map(raw["edges"] || [], fn e ->
          %{
            id: e["id"],
            source_node_id: e["source_node_id"],
            target_node_id: e["target_node_id"],
            source_port: e["source_port"] || "output",
            label: e["label"]
          }
        end),
      settings: %{
        max_retries: (raw["settings"] || %{})["max_retries"] || %{},
        notifications: (raw["settings"] || %{})["notifications"] != false,
        integrations: (raw["settings"] || %{})["integrations"] || %{}
      },
      created_at: raw["created_at"],
      updated_at: raw["updated_at"]
    }
  end

  def pipeline_run_to_json(run) do
    %{
      "id" => run.id,
      "pipeline_id" => run.pipeline_id,
      "product_id" => run[:product_id],
      "project_id" => run[:project_id],
      "input_description" => run[:input_description],
      "status" => run.status,
      "node_states" => run.node_states,
      "node_attempts" => run.node_attempts,
      "node_issue_ids" => run.node_issue_ids || %{},
      "node_outputs" => run.node_outputs || %{},
      "gate_decisions" =>
        Enum.map(run.gate_decisions, fn d ->
          %{
            "node_id" => d.node_id,
            "action" => d.action,
            "feedback" => d[:feedback],
            "findings_decisions" => d[:findings_decisions],
            "decided_at" => d.decided_at
          }
        end),
      "started_at" => run.started_at,
      "completed_at" => run.completed_at
    }
  end

  def json_to_pipeline_run(raw) do
    %{
      id: raw["id"],
      pipeline_id: raw["pipeline_id"],
      product_id: raw["product_id"],
      project_id: raw["project_id"],
      input_description: raw["input_description"],
      status: raw["status"] || "running",
      node_states: raw["node_states"] || %{},
      node_attempts: raw["node_attempts"] || %{},
      node_issue_ids: raw["node_issue_ids"] || %{},
      node_outputs: raw["node_outputs"] || %{},
      gate_decisions:
        Enum.map(raw["gate_decisions"] || [], fn d ->
          %{
            node_id: d["node_id"],
            action: d["action"],
            feedback: d["feedback"],
            findings_decisions: d["findings_decisions"],
            decided_at: d["decided_at"]
          }
        end),
      started_at: raw["started_at"],
      completed_at: raw["completed_at"]
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

defmodule SymphonyElixir.Server.BoardRouter do
  @moduledoc """
  HTTP router for the local Kanban board.

  Provides:
  - `GET /` — Kanban board UI (or `/board` via CombinedRouter)
  - `GET /api/issues` — list all issues
  - `POST /api/issues` — create issue
  - `PATCH /api/issues/:id` — update issue
  - `PATCH /api/issues/:id/move` — move issue to new state
  - `DELETE /api/issues/:id` — delete issue
  - `GET /api/states` — list available states
  - `GET /api/snapshot` — full board snapshot (columns + issues)
  - `GET /api/projects` — list all projects
  - `POST /api/projects` — create project
  - `PATCH /api/projects/:id` — update project
  - `DELETE /api/projects/:id` — delete project
  - `POST /api/projects/:id/clone` — clone project repository
  - `GET /api/templates` — list code review templates

  When served behind `CombinedRouter`, all paths are prefixed with `/board`.
  """

  use Plug.Router

  alias SymphonyElixir.{LocalBoard, Settings}

  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)
  plug(:dispatch)

  # --- Board UI ---

  get "/" do
    html = SymphonyElixir.Server.ProductHubUI.render()

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  # Legacy routes — redirect to Hub
  get "/kanban" do
    conn |> put_resp_header("location", "/board") |> send_resp(302, "")
  end

  get "/projects" do
    conn |> put_resp_header("location", "/board") |> send_resp(302, "")
  end

  get "/skills" do
    html = SymphonyElixir.Server.SkillsUI.render()

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  get "/settings" do
    html = SymphonyElixir.Server.SettingsUI.render()

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  get "/products" do
    # Redirect to hub — products view is now the default
    conn
    |> put_resp_header("location", "/board")
    |> send_resp(302, "")
  end

  get "/task-lineage" do
    html = SymphonyElixir.Server.TechTreeUI.render()

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  get "/issues/:id" do
    case LocalBoard.get_issue(id) do
      {:ok, issue} ->
        html = SymphonyElixir.Server.IssueDetailUI.render(issue)

        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, html)

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(404, "<h1>Issue not found</h1>")
    end
  end

  # --- JSON API ---

  get "/api/snapshot" do
    snapshot = LocalBoard.get_board_snapshot()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(snapshot))
  end

  get "/api/states" do
    states = LocalBoard.list_states()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{states: states}))
  end

  get "/api/issues" do
    issues = LocalBoard.list_issues()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{issues: issues}))
  end

  get "/api/issues/:id" do
    case LocalBoard.get_issue(id) do
      {:ok, issue} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(issue))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  get "/api/issues/:id/activity" do
    case LocalBoard.get_issue(id) do
      {:ok, issue} ->
        # Try to get orchestrator running state for this issue
        orchestrator_detail =
          try do
            case SymphonyElixir.Orchestrator.get_issue_detail(issue.identifier) do
              {:ok, detail} -> detail
              _ -> nil
            end
          catch
            :exit, _ -> nil
          end

        # Fall back to persisted agent_run data if orchestrator has no info
        orchestrator_detail =
          if is_nil(orchestrator_detail) and is_map(issue[:agent_run]) do
            run = issue[:agent_run]

            %{
              status: "completed",
              event_log: run["event_log"] || [],
              result_text: run["result_text"],
              follow_ups: run["follow_ups"] || [],
              running: %{
                tokens:
                  run["tokens"] ||
                    %{
                      "input_tokens" => 0,
                      "output_tokens" => 0,
                      "total_tokens" => 0
                    }
              }
            }
          else
            orchestrator_detail
          end

        body =
          try do
            Jason.encode!(%{
              issue: Map.drop(issue, [:agent_run]),
              orchestrator: orchestrator_detail
            })
          rescue
            _ -> Jason.encode!(%{issue: Map.drop(issue, [:agent_run]), orchestrator: nil})
          end

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, body)

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  # --- Plan Review API ---

  post "/api/issues/:id/approve-plan" do
    try do
      case SymphonyElixir.Orchestrator.approve_plan(id) do
        :ok ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(%{ok: true}))

        {:error, reason} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(422, Jason.encode!(%{error: to_string(reason)}))
      end
    catch
      :exit, _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(503, Jason.encode!(%{error: "orchestrator_unavailable"}))
    end
  end

  post "/api/issues/:id/reject-plan" do
    {:ok, body, conn} = Plug.Conn.read_body(conn)

    feedback =
      case Jason.decode(body) do
        {:ok, %{"feedback" => fb}} when is_binary(fb) and fb != "" -> fb
        _ -> nil
      end

    try do
      case SymphonyElixir.Orchestrator.reject_plan(id, feedback) do
        :ok ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(%{ok: true}))

        {:error, reason} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(422, Jason.encode!(%{error: to_string(reason)}))
      end
    catch
      :exit, _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(503, Jason.encode!(%{error: "orchestrator_unavailable"}))
    end
  end

  post "/api/issues/:id/rerun" do
    hint =
      case conn.body_params do
        %{"hint" => h} when is_binary(h) and h != "" -> h
        _ -> nil
      end

    try do
      case SymphonyElixir.Orchestrator.rerun_issue(id, hint) do
        :ok ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(%{ok: true}))

        {:error, reason} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(422, Jason.encode!(%{error: to_string(reason)}))
      end
    catch
      :exit, _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(503, Jason.encode!(%{error: "orchestrator_unavailable"}))
    end
  end

  # --- Follow-ups API ---

  post "/api/issues/:id/follow-ups/:fu_id/accept" do
    with {:ok, issue} <- LocalBoard.get_issue(id),
         {:ok, follow_up, agent_run} <- find_follow_up(issue, fu_id),
         true <- follow_up["status"] == "proposed" do
      # Check if this is a product feature-generation issue
      prod_id = extract_product_id(issue)
      is_feature_issue = is_feature_generation_issue(issue)

      result =
        if prod_id && is_feature_issue do
          feature_attrs = %{
            "name" => follow_up["title"],
            "description" => follow_up["description"],
            "category" => follow_up["category"],
            "depends_on" => follow_up["depends_on"] || [],
            "project_ids" => follow_up["project_ids"] || [],
            "statuses" => follow_up["statuses"] || %{}
          }

          # Check for existing feature with same name (dedup)
          case LocalBoard.get_product(prod_id) do
            {:ok, existing_prod} ->
              existing_feature =
                Enum.find(existing_prod.features, fn f ->
                  String.downcase(String.trim(f.name)) ==
                    String.downcase(String.trim(feature_attrs["name"] || ""))
                end)

              if existing_feature do
                # Merge new statuses into existing feature
                new_statuses = feature_attrs["statuses"] || %{}

                Enum.each(new_statuses, fn {project_id, status} ->
                  LocalBoard.set_feature_status(
                    prod_id,
                    existing_feature.id,
                    project_id,
                    status,
                    "agent_merge"
                  )
                end)

                {:ok, updated_prod} = LocalBoard.get_product(prod_id)
                merged = Enum.find(updated_prod.features, &(&1.id == existing_feature.id))
                %{ok: true, feature: merged, product_id: prod_id, merged: true}
              else
                # New feature — add it
                case LocalBoard.add_product_feature(prod_id, feature_attrs) do
                  {:ok, prod} ->
                    new_feature = List.last(prod.features)
                    %{ok: true, feature: new_feature, product_id: prod_id}

                  {:error, _} ->
                    create_follow_up_issue(issue, follow_up, id)
                end
              end

            {:error, _} ->
              create_follow_up_issue(issue, follow_up, id)
          end
        else
          create_follow_up_issue(issue, follow_up, id)
        end

      # Update follow-up status with created entity info
      updated_run =
        update_follow_up_status(agent_run, fu_id, "accepted", result)

      LocalBoard.save_agent_run(id, updated_run)
      maybe_move_to_done(id, updated_run)

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(result))
    else
      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "invalid_state"}))
    end
  end

  post "/api/issues/:id/follow-ups/:fu_id/reject" do
    with {:ok, issue} <- LocalBoard.get_issue(id),
         {:ok, follow_up, agent_run} <- find_follow_up(issue, fu_id),
         true <- follow_up["status"] == "proposed" do
      updated_run = update_follow_up_status(agent_run, fu_id, "rejected", nil)
      LocalBoard.save_agent_run(id, updated_run)
      maybe_move_to_done(id, updated_run)

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(%{ok: true}))
    else
      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "invalid_state"}))
    end
  end

  patch "/api/issues/:id/follow-ups/:fu_id" do
    with {:ok, issue} <- LocalBoard.get_issue(id),
         {:ok, _follow_up, agent_run} <- find_follow_up(issue, fu_id) do
      attrs = conn.body_params
      editable_keys = ["title", "description", "labels", "priority", "category", "project_ids"]

      updated_run = update_follow_up_fields(agent_run, fu_id, attrs, editable_keys)
      LocalBoard.save_agent_run(id, updated_run)

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(%{ok: true}))
    else
      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  post "/api/issues" do
    case LocalBoard.create_issue(conn.body_params) do
      {:ok, issue} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(201, Jason.encode!(issue))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "create_failed", detail: inspect(reason)}))
    end
  end

  patch "/api/issues/:id/move" do
    new_state = conn.body_params["state"]

    if is_nil(new_state) or new_state == "" do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(400, Jason.encode!(%{error: "state is required"}))
    else
      case LocalBoard.move_issue(id, new_state) do
        {:ok, issue} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(issue))

        {:error, :not_found} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(404, Jason.encode!(%{error: "not_found"}))
      end
    end
  end

  patch "/api/issues/:id" do
    case LocalBoard.update_issue(id, conn.body_params) do
      {:ok, issue} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(issue))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  delete "/api/issues/:id" do
    case LocalBoard.delete_issue(id) do
      :ok ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{deleted: true}))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  # --- Projects API ---

  get "/api/projects" do
    projects = LocalBoard.list_projects()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{projects: projects}))
  end

  get "/api/projects/:id" do
    case LocalBoard.get_project(id) do
      {:ok, project} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(project))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  post "/api/projects" do
    case LocalBoard.create_project(conn.body_params) do
      {:ok, project} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(201, Jason.encode!(project))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "create_failed", detail: inspect(reason)}))
    end
  end

  patch "/api/projects/:id" do
    case LocalBoard.update_project(id, conn.body_params) do
      {:ok, project} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(project))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  delete "/api/projects/:id" do
    case LocalBoard.delete_project(id) do
      :ok ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{deleted: true}))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  post "/api/projects/:id/clone" do
    case LocalBoard.clone_project_repo(id) do
      {:ok, path} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{cloned: true, path: path}))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))

      {:error, :no_repo_url} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "no_repo_url"}))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, Jason.encode!(%{error: "clone_failed", detail: inspect(reason)}))
    end
  end

  # --- Project Scanning ---

  post "/api/projects/scan" do
    root_path = Map.get(conn.body_params, "root_path", "")

    opts = [
      git_pull: conn.body_params["git_pull"] == true,
      recursive: conn.body_params["recursive"] == true,
      ai_summarize: conn.body_params["ai_summarize"] == true
    ]

    case SymphonyElixir.ProjectScanner.scan(root_path, opts) do
      {:ok, candidates} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{candidates: candidates}))

      {:error, :not_a_directory} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "not_a_directory", path: root_path}))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, Jason.encode!(%{error: "scan_failed", detail: inspect(reason)}))
    end
  end

  post "/api/browse-folder" do
    case open_native_folder_dialog() do
      {:ok, path} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{path: path}))

      :cancelled ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{path: nil}))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, Jason.encode!(%{error: "browse_failed", detail: inspect(reason)}))
    end
  end

  post "/api/projects/import" do
    candidates = Map.get(conn.body_params, "projects", [])

    results =
      Enum.map(candidates, fn attrs ->
        case LocalBoard.create_project(attrs) do
          {:ok, project} -> {:ok, project}
          {:error, _reason} -> :skip
        end
      end)

    created = for {:ok, p} <- results, do: p

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(201, Jason.encode!(%{imported: length(created), projects: created}))
  end

  # --- Products API ---

  get "/api/products" do
    products = LocalBoard.list_products()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{products: products}))
  end

  get "/api/products/:id" do
    case LocalBoard.get_product(id) do
      {:ok, prod} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(prod))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  post "/api/products" do
    case LocalBoard.create_product(conn.body_params) do
      {:ok, prod} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(201, Jason.encode!(prod))

      {:error, :duplicate_name} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          409,
          Jason.encode!(%{
            error: "duplicate_name",
            message: "A product with that name already exists"
          })
        )

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "create_failed", detail: inspect(reason)}))
    end
  end

  patch "/api/products/:id" do
    case LocalBoard.update_product(id, conn.body_params) do
      {:ok, prod} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(prod))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  delete "/api/products/:id" do
    case LocalBoard.delete_product(id) do
      :ok ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{deleted: true}))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  post "/api/products/:id/features" do
    case LocalBoard.add_product_feature(id, conn.body_params) do
      {:ok, prod} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(201, Jason.encode!(prod))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))

      {:error, :duplicate_name} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          409,
          Jason.encode!(%{
            error: "duplicate_name",
            message: "A feature with that name already exists in this product"
          })
        )
    end
  end

  patch "/api/products/:id/features/bulk-category" do
    feature_ids = conn.body_params["feature_ids"] || []
    category = conn.body_params["category"]

    case LocalBoard.get_product(id) do
      {:ok, _prod} ->
        Enum.each(feature_ids, fn fid ->
          LocalBoard.update_product_feature(id, fid, %{"category" => category})
        end)

        {:ok, updated} = LocalBoard.get_product(id)

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(updated))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  patch "/api/products/:prod_id/features/:feature_id" do
    case LocalBoard.update_product_feature(prod_id, feature_id, conn.body_params) do
      {:ok, prod} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(prod))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  delete "/api/products/:prod_id/features/:feature_id" do
    case LocalBoard.delete_product_feature(prod_id, feature_id) do
      {:ok, prod} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(prod))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  patch "/api/products/:prod_id/features/:feature_id/status" do
    project_id = conn.body_params["project_id"]
    status = conn.body_params["status"]

    if is_nil(project_id) or is_nil(status) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(400, Jason.encode!(%{error: "project_id and status are required"}))
    else
      source = conn.body_params["source"] || "manual"

      case LocalBoard.set_feature_status(prod_id, feature_id, project_id, status, source) do
        {:ok, prod} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(prod))

        {:error, :not_found} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(404, Jason.encode!(%{error: "not_found"}))

        {:error, :invalid_status} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            400,
            Jason.encode!(%{
              error: "invalid_status",
              message: "Status must be one of: missing, planned, in_progress, done, n_a"
            })
          )
      end
    end
  end

  post "/api/products/:id/analyze-gaps" do
    case LocalBoard.get_product(id) do
      {:ok, prod} ->
        projects = resolve_product_projects(prod)
        project_list = format_project_list(projects)
        feature_matrix = format_feature_matrix(prod, projects)

        description = """
        ## Gap Analysis — #{prod.name}

        Analyze the codebases of this product's projects and identify gaps — features that are missing,
        incomplete, or incorrectly tracked in the current feature matrix.
        #{if prod.description, do: "\n**Product:** #{prod.description}\n", else: ""}
        **Projects in this product:**
        #{project_list}

        **Current feature matrix:**
        #{feature_matrix}

        ### Instructions
        For each project, explore the codebase and compare against the feature matrix above.

        Look for:
        1. **Missing features** — capabilities that should exist but aren't tracked yet
        2. **Status mismatches** — features marked as "done" that are actually incomplete, or "missing" features that are already implemented
        3. **Missing project coverage** — features that should apply to a project but don't include it

        For each gap found, propose a follow-up with:
        - **Title**: Short description of the gap (e.g. "Add rate limiting to API Gateway", "Fix: Auth is implemented in User Service")
        - **Description**: What the gap is, evidence from the codebase, and what needs to happen
        - **Labels**: `["gap-analysis"]`

        For status corrections, also include:
        - **project_ids**: Array of project IDs affected
        - **statuses**: Object mapping project_id → corrected status

        Be thorough but only report real gaps — verify against the actual codebase.
        """

        {:ok, issue} =
          LocalBoard.create_issue(%{
            "title" => "Gap analysis for #{prod.name}",
            "description" => description,
            "labels" => ["product-review", "gap-analysis", "product:#{id}"],
            "priority" => 2,
            "state" => "Todo",
            "product_id" => id
          })

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          201,
          Jason.encode!(%{
            issue: issue,
            message:
              "Issue #{issue.identifier} created. The agent will analyze codebases and identify gaps."
          })
        )

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  post "/api/products/:id/create-gap-issues" do
    case LocalBoard.get_product(id) do
      {:ok, prod} ->
        # Create issues from gap analysis
        gap_items = conn.body_params["gaps"] || []

        created =
          Enum.map(gap_items, fn gap ->
            project_id = gap["project_id"]
            feature_name = gap["feature_name"]
            reason = gap["reason"] || "Missing feature"

            attrs = %{
              "title" => "#{feature_name}",
              "description" =>
                "## Gap Analysis — #{prod.name}\n\n**Feature:** #{feature_name}\n**Reason:** #{reason}\n\nIdentified by cross-project product review.",
              "labels" => ["gap-analysis"],
              "priority" => 2,
              "state" => "Backlog",
              "project_id" => project_id
            }

            {:ok, issue} = LocalBoard.create_issue(attrs)
            issue
          end)

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(201, Jason.encode!(%{created: created}))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  # --- Agent-dispatched product endpoints ---
  # These create issues on the board that the orchestrator picks up and
  # dispatches to agents. The agent does the actual AI work.

  post "/api/products/:id/generate-features" do
    case LocalBoard.get_product(id) do
      {:ok, prod} ->
        user_prompt = conn.body_params["prompt"] || ""

        if user_prompt == "" do
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(400, Jason.encode!(%{error: "prompt is required"}))
        else
          projects = resolve_product_projects(prod)
          project_list = format_project_list(projects)
          existing = format_existing_features(prod)

          description = """
          ## Generate Features — #{prod.name}

          Analyze this product and identify the features needed across its projects.
          #{if prod.description, do: "\n**Product:** #{prod.description}\n", else: ""}
          **Projects in this product:**
          #{project_list}

          #{if existing != "", do: "**Already defined features (do NOT repeat):**\n#{existing}\n", else: ""}
          **User's request:** #{user_prompt}

          ### Instructions
          For each project, look at its codebase (if workspace available) or infer from the project name and description.
          Identify features that exist or are needed across the projects in this product.
          A feature is a capability or concern that may need implementation in one or more projects (e.g. "API Key Management", "Error Handling", "User Documentation").

          **IMPORTANT**: Not every feature applies to every project. Only include projects that genuinely participate in or need a given feature. If you find evidence that a feature is already implemented in a project, mark its status as "done". If it's partially there, use "in_progress". If the project needs it but doesn't have it yet, use "missing". If a feature doesn't apply to a project at all, do NOT include that project.

          Propose each feature as a follow-up with:
          - **Title**: The feature name (short, descriptive — e.g. "API Key Management")
          - **Description**: What this feature covers and evidence of its current state
          - **Labels**: `["product-feature"]`
          - **project_ids**: Array of project IDs that participate in this feature (only relevant projects!)
          - **statuses**: Object mapping project_id → status ("done", "in_progress", "missing") reflecting the actual current state

          Valid status values: "done" (implemented), "in_progress" (partially implemented), "planned" (planned but not started), "missing" (needed but absent), "n_a" (not applicable).

          These will be added to the product feature matrix for tracking across projects.
          Do NOT propose implementation tasks — propose high-level features.
          """

          skill_ids = conn.body_params["skill_ids"] || []
          skill_group_ids = conn.body_params["skill_group_ids"] || []

          {:ok, issue} =
            LocalBoard.create_issue(%{
              "title" => "Generate features for #{prod.name}",
              "description" => description,
              "labels" => ["product-review", "generate-features", "product:#{id}"],
              "priority" => 2,
              "state" => "Todo",
              "product_id" => id,
              "skill_ids" => skill_ids,
              "skill_group_ids" => skill_group_ids
            })

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            201,
            Jason.encode!(%{
              issue: issue,
              message:
                "Issue #{issue.identifier} created. The agent will pick it up and propose features as follow-ups."
            })
          )
        end

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  post "/api/products/:prod_id/features/:feature_id/check" do
    with {:ok, prod} <- LocalBoard.get_product(prod_id),
         feature when not is_nil(feature) <-
           Enum.find(prod.features, &(&1.id == feature_id)) do
      all_projects = resolve_product_projects(prod)
      project_map = Map.new(all_projects, fn p -> {p.id, p} end)

      # Only check projects that participate in this feature
      feature_project_ids = Map.keys(feature.statuses)

      issues_created =
        feature_project_ids
        |> Enum.map(fn pid -> Map.get(project_map, pid) end)
        |> Enum.reject(&is_nil/1)
        |> Enum.reject(fn p ->
          status = Map.get(feature.statuses, p.id, "missing")
          status in ["done", "n_a"]
        end)
        |> Enum.map(fn p ->
          description = """
          ## Feature Check — #{feature.name}

          **Product:** #{prod.name}
          **Project:** #{p.name}
          #{if p.description, do: "**Project description:** #{p.description}", else: ""}
          #{if p.repo_url, do: "**Repository:** #{p.repo_url}", else: ""}
          #{if feature.description, do: "\n**Feature description:** #{feature.description}", else: ""}

          ### Instructions
          Check whether the feature "#{feature.name}" is implemented in this project.
          Search the codebase for relevant code, APIs, configurations, or documentation.

          Report your findings and propose follow-up issues for anything missing or incomplete.
          Each follow-up should be a concrete, actionable task.

          **IMPORTANT**: At the end of your response, include a status verdict block:
          ```status-verdict
          {"status": "done|in_progress|missing|n_a", "reason": "brief explanation"}
          ```
          - "done" — feature is fully implemented
          - "in_progress" — feature is partially implemented
          - "missing" — feature is not implemented but needed
          - "n_a" — feature does not apply to this project
          """

          {:ok, issue} =
            LocalBoard.create_issue(%{
              "title" => "Check: #{feature.name} in #{p.name}",
              "description" => description,
              "labels" => [
                "product-review",
                "feature-check",
                "product:#{prod_id}",
                "feature:#{feature_id}"
              ],
              "priority" => 2,
              "state" => "Todo",
              "project_id" => p.id
            })

          issue
        end)

      # Mark checked projects as "in_progress" in the matrix
      Enum.each(issues_created, fn issue ->
        if issue.project_id do
          LocalBoard.set_feature_status(
            prod_id,
            feature_id,
            issue.project_id,
            "in_progress",
            "agent_check"
          )
        end
      end)

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        201,
        Jason.encode!(%{
          issues: issues_created,
          message:
            "Created #{length(issues_created)} check issue(s). Agents will verify the feature in each project."
        })
      )
    else
      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))

      nil ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "feature_not_found"}))
    end
  end

  post "/api/products/:id/analyze-existing-features" do
    case LocalBoard.get_product(id) do
      {:ok, prod} ->
        projects = resolve_product_projects(prod)

        project_list = format_project_list(projects)
        existing = format_existing_features(prod)

        description = """
        ## Analyze Existing Features — #{prod.name}

        Scan the codebases of all projects in this product and identify features that are ALREADY implemented.
        #{if prod.description, do: "\n**Product:** #{prod.description}\n", else: ""}
        **Projects in this product:**
        #{project_list}

        #{if existing != "", do: "**Already tracked features (update status if found, do NOT duplicate):**\n#{existing}\n", else: ""}

        ### Instructions
        For each project, explore the codebase thoroughly. Look at:
        - Source code structure, modules, and packages
        - API endpoints and routes
        - Configuration files
        - Tests (they reveal implemented functionality)
        - Documentation and README files

        Identify features and capabilities that are already implemented across the projects.
        A feature is a high-level capability (e.g. "Authentication", "Rate Limiting", "Error Handling", "Logging", "API Versioning").

        **IMPORTANT**: Not every feature applies to every project. Only include projects where a feature is relevant. If you find evidence a feature is implemented in a project, set its status to "done". If it's partially implemented, use "in_progress". If the project needs it but it's missing, use "missing". Do NOT include projects where a feature doesn't apply at all.

        Propose each discovered feature as a follow-up with:
        - **Title**: The feature name (short, descriptive)
        - **Description**: What this feature covers, evidence of implementation (file paths, module names)
        - **Labels**: `["product-feature"]`
        - **project_ids**: Array of project IDs where this feature is relevant (only participating projects!)
        - **statuses**: Object mapping project_id → status ("done", "in_progress", "missing") based on evidence found

        Valid status values: "done" (implemented), "in_progress" (partially implemented), "planned" (planned but not started), "missing" (needed but absent), "n_a" (not applicable).

        These will be added to the product feature matrix.
        Only propose features you have evidence for — do NOT speculate about features that might exist.
        """

        {:ok, issue} =
          LocalBoard.create_issue(%{
            "title" => "Analyze existing features in #{prod.name}",
            "description" => description,
            "labels" => ["product-review", "analyze-existing", "product:#{id}"],
            "priority" => 2,
            "state" => "Todo",
            "product_id" => id
          })

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          201,
          Jason.encode!(%{
            issue: issue,
            message:
              "Issue #{issue.identifier} created. The agent will scan the codebases and discover implemented features."
          })
        )

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  post "/api/products/:id/code-review" do
    case LocalBoard.get_product(id) do
      {:ok, prod} ->
        focus = conn.body_params["focus"] || ""
        projects = resolve_product_projects(prod)

        project_list = format_project_list(projects)

        description = """
        ## Code Review — #{prod.name}

        Perform a comprehensive code review across all projects in this product.
        #{if prod.description, do: "\n**Product:** #{prod.description}\n", else: ""}
        **Projects to review:**
        #{project_list}

        #{if focus != "", do: "**Focus areas:** #{focus}\n", else: ""}

        ### Instructions
        Review the codebase of each project. For each project, examine:
        - **Code quality**: naming conventions, readability, complexity, duplication
        - **Architecture**: separation of concerns, dependency management, modularity
        - **Security**: input validation, authentication, authorization, secrets management
        - **Error handling**: graceful failures, logging, error propagation
        - **Testing**: test coverage, test quality, missing edge cases
        - **Performance**: potential bottlenecks, N+1 queries, memory issues
        - **Dependencies**: outdated deps, security vulnerabilities, unnecessary deps
        - **Documentation**: missing docs, outdated docs, API documentation

        For each finding, propose a follow-up issue with:
        - **Title**: Clear, actionable title (e.g. "Fix SQL injection in user search endpoint")
        - **Description**: What the issue is, where it is (file paths), why it matters, and how to fix it
        - **Labels**: One of `["code-review-critical"]`, `["code-review-major"]`, or `["code-review-minor"]` based on severity

        Prioritize critical issues (security, data loss) over minor style issues.
        Be specific — include file paths and line references where possible.
        """

        skill_ids = conn.body_params["skill_ids"] || []
        skill_group_ids = conn.body_params["skill_group_ids"] || []

        {:ok, issue} =
          LocalBoard.create_issue(%{
            "title" => "Code review: #{prod.name}",
            "description" => description,
            "labels" => ["product-review", "code-review", "product:#{id}"],
            "priority" => 1,
            "state" => "Todo",
            "product_id" => id,
            "skill_ids" => skill_ids,
            "skill_group_ids" => skill_group_ids
          })

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          201,
          Jason.encode!(%{
            issue: issue,
            message:
              "Issue #{issue.identifier} created. The agent will review all project codebases and report findings."
          })
        )

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  post "/api/products/:id/generate-definition" do
    case LocalBoard.get_product(id) do
      {:ok, prod} ->
        user_context = conn.body_params["context"] || ""
        projects = resolve_product_projects(prod)
        project_list = format_project_list(projects)
        existing = format_existing_features(prod)

        description = """
        ## Generate Product Definition — #{prod.name}

        Analyze the projects in this product and generate a comprehensive product definition and description.

        **Current product name:** #{prod.name}
        #{if prod.description && prod.description != "", do: "**Current description:** #{prod.description}\n", else: ""}
        **Projects in this product:**
        #{project_list}

        #{if existing != "", do: "**Currently tracked features:**\n#{existing}\n", else: ""}
        #{if user_context != "", do: "**Additional context from user:** #{user_context}\n", else: ""}

        ### Instructions
        Analyze each project's codebase, documentation, and structure to understand what this product does.
        Then write a clear, comprehensive product definition including:

        1. **Product Name** — Suggest a better name if the current one is vague, or confirm it's good
        2. **Description** — A 2-4 sentence description of what this product is, what it does, and who it's for
        3. **Scope** — What this product covers and what it explicitly does NOT cover
        4. **Key capabilities** — The main things this product enables

        Format your response with clear sections. At the end, include a definition block:
        ```product-definition
        {"name": "Suggested Product Name", "description": "The generated product description text."}
        ```

        Be specific and evidence-based — reference what you found in the codebases.
        """

        skill_ids = conn.body_params["skill_ids"] || []
        skill_group_ids = conn.body_params["skill_group_ids"] || []

        {:ok, issue} =
          LocalBoard.create_issue(%{
            "title" => "Generate definition for #{prod.name}",
            "description" => description,
            "labels" => ["product-review", "generate-definition", "product:#{id}"],
            "priority" => 2,
            "state" => "Todo",
            "product_id" => id,
            "skill_ids" => skill_ids,
            "skill_group_ids" => skill_group_ids
          })

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          201,
          Jason.encode!(%{
            issue: issue,
            message:
              "Issue #{issue.identifier} created. The agent will analyze codebases and propose a product definition."
          })
        )

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  post "/api/products/:id/tasks" do
    case LocalBoard.get_product(id) do
      {:ok, prod} ->
        title = conn.body_params["title"] || ""
        user_prompt = conn.body_params["prompt"] || ""

        if title == "" or user_prompt == "" do
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(400, Jason.encode!(%{error: "title and prompt are required"}))
        else
          projects = resolve_product_projects(prod)
          project_list = format_project_list(projects)

          description = """
          ## #{title} — #{prod.name}

          #{if prod.description, do: "**Product:** #{prod.description}\n", else: ""}
          **Projects in this product:**
          #{project_list}

          ### Task
          #{user_prompt}

          ### Instructions
          You have access to the codebases of all projects listed above.
          Complete the task described above. Be thorough and evidence-based.
          If you find issues or have recommendations, propose them as follow-up issues.
          """

          priority = conn.body_params["priority"] || 2
          skill_ids = conn.body_params["skill_ids"] || []
          skill_group_ids = conn.body_params["skill_group_ids"] || []

          {:ok, issue} =
            LocalBoard.create_issue(%{
              "title" => "#{title}: #{prod.name}",
              "description" => description,
              "labels" => ["product-review", "product-task", "product:#{id}"],
              "priority" => priority,
              "state" => "Todo",
              "product_id" => id,
              "skill_ids" => skill_ids,
              "skill_group_ids" => skill_group_ids
            })

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            201,
            Jason.encode!(%{
              issue: issue,
              message:
                "Issue #{issue.identifier} created. The agent will pick it up and work on it."
            })
          )
        end

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  # --- Product Activity API ---

  get "/api/products/:id/activity" do
    case LocalBoard.get_product(id) do
      {:ok, prod} ->
        all_issues = LocalBoard.list_issues()
        project_ids = MapSet.new(prod.project_ids)

        matching =
          all_issues
          |> Enum.filter(fn issue ->
            # Match by product_id field
            # Match by product:<id> label
            # Match by project membership
            Map.get(issue, :product_id) == id ||
              Enum.any?(Map.get(issue, :labels, []), &(&1 == "product:#{id}")) ||
              (is_binary(issue.project_id) and MapSet.member?(project_ids, issue.project_id))
          end)
          |> Enum.sort_by(fn i -> i.updated_at || "" end, :desc)
          |> Enum.take(50)

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{issues: matching}))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  # --- Skills API ---

  get "/api/skills" do
    skills = LocalBoard.list_skills()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{skills: skills}))
  end

  get "/api/skills/:id" do
    case LocalBoard.get_skill(id) do
      {:ok, skill} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(skill))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  post "/api/skills" do
    case LocalBoard.create_skill(conn.body_params) do
      {:ok, skill} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(201, Jason.encode!(skill))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "create_failed", detail: inspect(reason)}))
    end
  end

  patch "/api/skills/:id" do
    case LocalBoard.update_skill(id, conn.body_params) do
      {:ok, skill} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(skill))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  delete "/api/skills/:id" do
    case LocalBoard.delete_skill(id) do
      :ok ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{deleted: true}))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))

      {:error, :built_in} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          400,
          Jason.encode!(%{
            error: "cannot_delete_built_in",
            message:
              "Built-in skills cannot be deleted. Duplicate it to create a customizable copy."
          })
        )
    end
  end

  post "/api/skills/:id/duplicate" do
    case LocalBoard.duplicate_skill(id) do
      {:ok, skill} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(201, Jason.encode!(skill))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  # --- Skill Groups API ---

  get "/api/skill-groups" do
    groups = LocalBoard.list_skill_groups()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{skill_groups: groups}))
  end

  get "/api/skill-groups/:id" do
    case LocalBoard.get_skill_group(id) do
      {:ok, group} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(group))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  post "/api/skill-groups" do
    case LocalBoard.create_skill_group(conn.body_params) do
      {:ok, group} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(201, Jason.encode!(group))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "create_failed", detail: inspect(reason)}))
    end
  end

  patch "/api/skill-groups/:id" do
    case LocalBoard.update_skill_group(id, conn.body_params) do
      {:ok, group} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(group))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  delete "/api/skill-groups/:id" do
    case LocalBoard.delete_skill_group(id) do
      :ok ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{deleted: true}))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  # --- Issue Skill Assignment API ---

  post "/api/issues/:id/skills" do
    case LocalBoard.get_issue(id) do
      {:ok, _issue} ->
        attrs = %{
          "skill_ids" => conn.body_params["skill_ids"] || [],
          "skill_group_ids" => conn.body_params["skill_group_ids"] || []
        }

        case LocalBoard.update_issue(id, attrs) do
          {:ok, updated} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(200, Jason.encode!(updated))

          {:error, reason} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(400, Jason.encode!(%{error: "update_failed", detail: inspect(reason)}))
        end

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  # --- Report File API ---

  get "/api/issues/:id/report" do
    with {:ok, issue} <- LocalBoard.get_issue(id),
         {:ok, workspace} <- resolve_issue_workspace(issue),
         {:ok, rel_path} <- extract_report_path(issue, conn.query_params["path"]),
         safe_path when is_binary(safe_path) <- safe_resolve(workspace, rel_path),
         {:ok, content} <- File.read(safe_path) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(%{path: rel_path, content: content}))
    else
      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))

      {:error, :no_workspace} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "no_workspace"}))

      {:error, :no_report} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "no_report"}))

      {:error, :path_traversal} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "invalid_path"}))

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "file_not_found"}))
    end
  end

  # --- Templates API ---

  post "/api/ai/draft-issue" do
    hint = Map.get(conn.body_params, "hint", "") |> String.trim()

    if hint == "" do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(400, Jason.encode!(%{error: "hint_required"}))
    else
      skills = LocalBoard.list_skills()

      skill_names =
        skills
        |> Enum.map(fn s -> Map.get(s, :name) || s["name"] end)
        |> Enum.reject(&is_nil/1)

      product_id = Map.get(conn.body_params, "product_id")

      product_context =
        case product_id do
          nil ->
            ""

          "" ->
            ""

          pid ->
            case LocalBoard.get_product(pid) do
              {:ok, prod} -> "\nProduct: #{prod.name}. #{prod.description || ""}"
              _ -> ""
            end
        end

      kb_context = build_kb_context_for_draft(product_id)

      project_context =
        case Map.get(conn.body_params, "project_id") do
          nil ->
            ""

          "" ->
            ""

          proj_id ->
            case LocalBoard.get_project(proj_id) do
              {:ok, proj} -> "\nProject: #{proj.name}. #{Map.get(proj, :description, "") || ""}"
              _ -> ""
            end
        end

      prompt = """
      You are a project management assistant. Given a brief hint, generate a well-structured issue.
      Respond with ONLY valid JSON, no markdown fences, no explanation. Use this exact schema:
      {"title":"...","description":"...","priority":3,"labels":["..."],"skill_names":["..."]}

      Rules:
      - title: concise, actionable (under 80 chars)
      - description: 2-4 paragraphs in markdown with acceptance criteria
      - priority: 1=Urgent, 2=High, 3=Medium, 4=Low
      - labels: 1-3 relevant labels (lowercase, hyphenated). Use these special labels when appropriate:
        * "extract-logic" — when the task is about extracting, documenting, or cataloging business rules/logic from a codebase
        * "research" — when the task is about researching a topic, technology, or approach
      - skill_names: pick 0-3 from available skills that match the task

      Available skills: #{Enum.join(skill_names, ", ")}#{product_context}#{project_context}#{kb_context}

      User hint: #{hint}
      """

      case agent_draft(prompt) do
        {:ok, json_str} ->
          # Strip markdown fences if present
          clean =
            json_str
            |> String.replace(~r/```json\s*/, "")
            |> String.replace(~r/```\s*/, "")
            |> String.trim()

          case Jason.decode(clean) do
            {:ok, draft} ->
              resolved_skill_ids =
                (draft["skill_names"] || [])
                |> Enum.map(fn name ->
                  Enum.find(skills, fn s ->
                    (Map.get(s, :name) || s["name"]) == name
                  end)
                end)
                |> Enum.reject(&is_nil/1)
                |> Enum.map(fn s -> Map.get(s, :id) || s["id"] end)

              result = Map.put(draft, "skill_ids", resolved_skill_ids)

              conn
              |> put_resp_content_type("application/json")
              |> send_resp(200, Jason.encode!(result))

            {:error, _} ->
              conn
              |> put_resp_content_type("application/json")
              |> send_resp(
                200,
                Jason.encode!(%{
                  title: hint,
                  description: clean,
                  priority: 3,
                  labels: [],
                  skill_ids: []
                })
              )
          end

        {:error, reason} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(500, Jason.encode!(%{error: "ai_failed", detail: inspect(reason)}))
      end
    end
  end

  post "/api/ai/draft-product" do
    hint = Map.get(conn.body_params, "hint", "") |> String.trim()

    if hint == "" do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(400, Jason.encode!(%{error: "hint_required"}))
    else
      prompt = """
      You are a product management assistant. Given a brief hint, generate a well-structured product definition.
      Respond with ONLY valid JSON, no markdown fences, no explanation. Use this exact schema:
      {"name":"...","description":"...","labels":["..."]}

      Rules:
      - name: concise product name (under 60 chars)
      - description: 2-3 paragraphs describing the product scope and goals in markdown
      - labels: 1-3 relevant labels (lowercase, hyphenated)

      User hint: #{hint}
      """

      case agent_draft(prompt) do
        {:ok, json_str} ->
          clean =
            json_str
            |> String.replace(~r/```json\s*/, "")
            |> String.replace(~r/```\s*/, "")
            |> String.trim()

          case Jason.decode(clean) do
            {:ok, draft} ->
              conn
              |> put_resp_content_type("application/json")
              |> send_resp(200, Jason.encode!(draft))

            {:error, _} ->
              conn
              |> put_resp_content_type("application/json")
              |> send_resp(200, Jason.encode!(%{name: hint, description: clean, labels: []}))
          end

        {:error, reason} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(500, Jason.encode!(%{error: "ai_failed", detail: inspect(reason)}))
      end
    end
  end

  post "/api/ai/draft-project" do
    hint = Map.get(conn.body_params, "hint", "") |> String.trim()

    if hint == "" do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(400, Jason.encode!(%{error: "hint_required"}))
    else
      prompt = """
      You are a project management assistant. Given a brief hint, generate a well-structured project definition.
      Respond with ONLY valid JSON, no markdown fences, no explanation. Use this exact schema:
      {"name":"...","description":"...","tags":["..."],"priority":3}

      Rules:
      - name: concise project name (under 60 chars)
      - description: 2-3 paragraphs describing the project purpose and scope in markdown
      - tags: 1-3 relevant tags (lowercase, hyphenated)
      - priority: 0=No priority, 1=Urgent, 2=High, 3=Medium, 4=Low

      User hint: #{hint}
      """

      case agent_draft(prompt) do
        {:ok, json_str} ->
          clean =
            json_str
            |> String.replace(~r/```json\s*/, "")
            |> String.replace(~r/```\s*/, "")
            |> String.trim()

          case Jason.decode(clean) do
            {:ok, draft} ->
              conn
              |> put_resp_content_type("application/json")
              |> send_resp(200, Jason.encode!(draft))

            {:error, _} ->
              conn
              |> put_resp_content_type("application/json")
              |> send_resp(
                200,
                Jason.encode!(%{name: hint, description: clean, tags: [], priority: 3})
              )
          end

        {:error, reason} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(500, Jason.encode!(%{error: "ai_failed", detail: inspect(reason)}))
      end
    end
  end

  # --- Settings API ---

  get "/api/settings" do
    settings = Settings.all()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(settings))
  end

  patch "/api/settings" do
    :ok = Settings.update(conn.body_params)
    settings = Settings.all()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(settings))
  end

  post "/api/settings/reset" do
    :ok = Settings.reset()
    settings = Settings.all()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(settings))
  end

  @board_settings_keys ["auto_add_enabled", "max_todo_parallel", "segregate_by_project"]

  get "/api/settings/auto-add" do
    payload =
      Map.new(@board_settings_keys, fn k -> {k, Settings.get(k)} end)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(payload))
  end

  patch "/api/settings/auto-add" do
    params = conn.body_params

    attrs =
      Enum.reduce(@board_settings_keys, %{}, fn k, acc ->
        if Map.has_key?(params, k), do: Map.put(acc, k, params[k]), else: acc
      end)

    :ok = Settings.update(attrs)

    payload =
      Map.new(@board_settings_keys, fn k -> {k, Settings.get(k)} end)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(payload))
  end

  # --- Follow-up helpers ---

  defp find_follow_up(issue, fu_id) do
    case issue[:agent_run] do
      run when is_map(run) ->
        follow_ups = run["follow_ups"] || []

        case Enum.find(follow_ups, &(&1["id"] == fu_id)) do
          nil -> {:error, :not_found}
          fu -> {:ok, fu, run}
        end

      _ ->
        {:error, :not_found}
    end
  end

  defp update_follow_up_status(agent_run, fu_id, status, result) do
    follow_ups =
      Enum.map(agent_run["follow_ups"] || [], fn fu ->
        if fu["id"] == fu_id do
          updated = Map.put(fu, "status", status)

          cond do
            # Follow-up created a new issue
            match?(%{issue: %{id: _, identifier: _}}, result) ->
              updated
              |> Map.put("created_issue_id", result.issue.id)
              |> Map.put("created_issue_identifier", result.issue.identifier)

            # Follow-up created/merged a product feature
            match?(%{feature: _, product_id: _}, result) ->
              feature = result[:feature]

              updated
              |> Map.put("created_feature_id", feature[:id] || feature.id)
              |> Map.put("created_feature_name", feature[:name] || feature.name)
              |> Map.put("created_product_id", result.product_id)
              |> Map.put("merged", result[:merged] || false)

            true ->
              updated
          end
        else
          fu
        end
      end)

    Map.put(agent_run, "follow_ups", follow_ups)
  end

  defp update_follow_up_fields(agent_run, fu_id, attrs, allowed_keys) do
    follow_ups =
      Enum.map(agent_run["follow_ups"] || [], fn fu ->
        if fu["id"] == fu_id do
          Enum.reduce(allowed_keys, fu, fn key, acc ->
            if Map.has_key?(attrs, key), do: Map.put(acc, key, attrs[key]), else: acc
          end)
        else
          fu
        end
      end)

    Map.put(agent_run, "follow_ups", follow_ups)
  end

  defp maybe_move_to_done(issue_id, updated_run) do
    follow_ups = updated_run["follow_ups"] || []
    all_resolved = Enum.all?(follow_ups, &(&1["status"] in ["accepted", "rejected"]))

    if all_resolved do
      LocalBoard.move_issue(issue_id, "Done")
    end
  end

  # Extract product ID from issue labels (e.g. "product:abc123")
  defp extract_product_id(issue) do
    labels = Map.get(issue, :labels, [])

    Enum.find_value(labels, fn label ->
      case String.split(label, "product:", parts: 2) do
        ["", prod_id] when prod_id != "" -> prod_id
        _ -> nil
      end
    end)
  end

  # Create a standard follow-up issue (non-product path)
  defp create_follow_up_issue(issue, follow_up, parent_id) do
    new_attrs = %{
      "title" => follow_up["title"],
      "description" =>
        "Follow-up from #{issue.identifier}: #{issue.title}\n\n#{follow_up["description"] || ""}",
      "labels" => follow_up["labels"] || [],
      "priority" => follow_up["priority"] || 3,
      "state" => "Backlog",
      "project_id" => issue.project_id,
      "parent_issue_id" => parent_id
    }

    {:ok, new_issue} = LocalBoard.create_issue(new_attrs)
    %{ok: true, issue: new_issue}
  end

  # --- Report helpers ---

  defp resolve_issue_workspace(%{project_id: pid}) when is_binary(pid) and pid != "" do
    case LocalBoard.get_project(pid) do
      {:ok, %{path: path}} when is_binary(path) and path != "" ->
        if File.dir?(path), do: {:ok, path}, else: {:error, :no_workspace}

      _ ->
        {:error, :no_workspace}
    end
  end

  defp resolve_issue_workspace(_), do: {:error, :no_workspace}

  defp extract_report_path(_issue, path) when is_binary(path) and path != "" do
    {:ok, path}
  end

  defp extract_report_path(issue, _) do
    result_text =
      case issue do
        %{agent_run: %{"result_text" => t}} when is_binary(t) -> t
        _ -> nil
      end

    if result_text do
      # Match file paths like `reports/SYM-3.md` or reports/SYM-3.md
      case Regex.run(~r/`([^`]+\.md)`|(\S+\.md)/, result_text) do
        [_, path] when is_binary(path) and path != "" -> {:ok, path}
        [_, "", path] -> {:ok, path}
        _ -> {:error, :no_report}
      end
    else
      {:error, :no_report}
    end
  end

  # Resolve a relative path inside workspace, rejecting traversal attempts
  defp safe_resolve(workspace, rel_path) do
    # Normalize separators and reject obvious traversal
    normalized = String.replace(rel_path, "\\", "/")

    if String.contains?(normalized, "..") do
      {:error, :path_traversal}
    else
      full = Path.join(workspace, normalized) |> Path.expand()
      workspace_expanded = Path.expand(workspace)

      if String.starts_with?(full, workspace_expanded) do
        full
      else
        {:error, :path_traversal}
      end
    end
  end

  # --- Product helpers ---

  defp resolve_product_projects(prod) do
    Enum.map(prod.project_ids, fn pid ->
      case LocalBoard.get_project(pid) do
        {:ok, p} -> p
        _ -> %{id: pid, name: pid, description: nil, repo_url: nil}
      end
    end)
  end

  defp format_project_list(projects) do
    projects
    |> Enum.map(fn p ->
      "- **#{p.name}** (id: `#{p.id}`)" <>
        if(p.description, do: ": #{p.description}", else: "") <>
        if(p.repo_url, do: " [repo: #{p.repo_url}]", else: "") <>
        if(Map.get(p, :path), do: " [path: #{p.path}]", else: "")
    end)
    |> Enum.join("\n")
  end

  @feature_generation_labels ~w(analyze-existing gap-analysis generate-features feature-check)

  defp is_feature_generation_issue(issue) do
    labels = Map.get(issue, :labels, [])
    Enum.any?(labels, fn l -> l in @feature_generation_labels end)
  end

  defp format_existing_features(prod) do
    prod.features
    |> Enum.map(fn f -> "- #{f.name}: #{f.description || ""}" end)
    |> Enum.join("\n")
  end

  defp format_feature_matrix(prod, projects) do
    project_map = Map.new(projects, fn p -> {p.id, p} end)

    if prod.features == [] do
      "(no features tracked yet)"
    else
      prod.features
      |> Enum.map(fn f ->
        status_parts =
          f.statuses
          |> Enum.map(fn {pid, status} ->
            pname = Map.get(project_map, pid, %{name: pid}).name
            "#{pname}=#{status}"
          end)
          |> Enum.join(", ")

        "- **#{f.name}** [#{status_parts}]#{if f.description, do: " — #{f.description}", else: ""}"
      end)
      |> Enum.join("\n")
    end
  end

  # --- Agent Draft Helper (uses claude -p like AgentSummarizer) ---

  @agent_draft_timeout_ms 60_000

  defp agent_draft(prompt) do
    bash = SymphonyElixir.ShellUtils.find_bash_path()
    unless bash, do: throw({:error, :bash_not_found})

    prompt_file =
      Path.join(System.tmp_dir!(), "symphony_draft_#{:rand.uniform(999_999)}.txt")

    try do
      File.write!(prompt_file, prompt)
      claude_cmd = (System.find_executable("claude") && "claude") || "claude"

      escaped =
        prompt_file
        |> String.replace("\\", "/")
        |> then(&"\"#{&1}\"")

      shell_command = "cat #{escaped} | #{claude_cmd} -p --output-format json 2>/dev/null"

      env = [
        {~c"CLAUDECODE", false},
        {~c"CLAUDE_CODE_ENTRYPOINT", false}
      ]

      port =
        Port.open({:spawn_executable, bash}, [
          :binary,
          :exit_status,
          :use_stdio,
          :stderr_to_stdout,
          {:args, ["-lc", shell_command]},
          {:env, env},
          {:line, 1_048_576}
        ])

      case collect_agent_output(port, "", @agent_draft_timeout_ms) do
        {:ok, output} ->
          # claude -p --output-format json wraps in {"type":"result","result":"..."}
          case Jason.decode(output) do
            {:ok, %{"result" => text}} ->
              {:ok, text}

            {:ok, %{"content" => content}} when is_list(content) ->
              text =
                content
                |> Enum.filter(&(&1["type"] == "text"))
                |> Enum.map_join("\n", & &1["text"])

              {:ok, text}

            _ ->
              {:ok, String.trim(output)}
          end

        {:error, _} = err ->
          err
      end
    after
      File.rm(prompt_file)
    end
  rescue
    e -> {:error, {:agent_error, Exception.message(e)}}
  catch
    {:error, _} = err -> err
  end

  defp collect_agent_output(port, acc, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_collect_agent(port, acc, deadline)
  end

  defp do_collect_agent(port, acc, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, {:eol, line}}} ->
        do_collect_agent(port, acc <> line <> "\n", deadline)

      {^port, {:data, {:noeol, chunk}}} ->
        do_collect_agent(port, acc <> chunk, deadline)

      {^port, {:exit_status, 0}} ->
        {:ok, acc}

      {^port, {:exit_status, code}} ->
        {:error, {:exit_code, code, acc}}
    after
      remaining ->
        try do
          Port.close(port)
        catch
          _, _ -> :ok
        end

        {:error, :timeout}
    end
  end

  defp open_native_folder_dialog do
    case :os.type() do
      {:win32, _} -> open_folder_dialog_windows()
      {:unix, :darwin} -> open_folder_dialog_macos()
      {:unix, _} -> open_folder_dialog_linux()
    end
  end

  defp open_folder_dialog_windows do
    script_path =
      Path.join(System.tmp_dir!(), "symphony_browse_#{:rand.uniform(999_999)}.ps1")

    ps_script = ~S"""
    Add-Type -AssemblyName System.Windows.Forms
    $topForm = New-Object System.Windows.Forms.Form
    $topForm.TopMost = $true
    $topForm.MinimizeBox = $false
    $topForm.MaximizeBox = $false
    $topForm.Width = 0
    $topForm.Height = 0
    $topForm.FormBorderStyle = 'None'
    $topForm.StartPosition = 'Manual'
    $topForm.Location = New-Object System.Drawing.Point(-9999, -9999)
    $topForm.Show()
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Select a directory'
    $dialog.ShowNewFolderButton = $false
    $result = $dialog.ShowDialog($topForm)
    $topForm.Close()
    if ($result -eq 'OK') { $dialog.SelectedPath } else { '__CANCELLED__' }
    """

    File.write!(script_path, ps_script)

    try do
      case System.cmd(
             "powershell",
             ["-NoProfile", "-STA", "-ExecutionPolicy", "Bypass", "-File", script_path],
             stderr_to_stdout: true
           ) do
        {output, 0} ->
          path = String.trim(output)
          if path == "__CANCELLED__", do: :cancelled, else: {:ok, path}

        {output, _} ->
          {:error, output}
      end
    after
      File.rm(script_path)
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp open_folder_dialog_macos do
    args = [
      "-e",
      ~S|tell application "System Events" to activate|,
      "-e",
      ~S|POSIX path of (choose folder with prompt "Select a directory to scan for projects")|
    ]

    case System.cmd("osascript", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {_, 1} -> :cancelled
      {output, _} -> {:error, output}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp open_folder_dialog_linux do
    # Try zenity first, fall back to kdialog
    cond do
      System.find_executable("zenity") ->
        case System.cmd("zenity", ["--file-selection", "--directory", "--title=Select directory"],
               stderr_to_stdout: true,
               timeout: 120_000
             ) do
          {output, 0} -> {:ok, String.trim(output)}
          {_, 1} -> :cancelled
          {output, _} -> {:error, output}
        end

      System.find_executable("kdialog") ->
        case System.cmd("kdialog", ["--getexistingdirectory", "."],
               stderr_to_stdout: true,
               timeout: 120_000
             ) do
          {output, 0} -> {:ok, String.trim(output)}
          {_, 1} -> :cancelled
          {output, _} -> {:error, output}
        end

      true ->
        {:error, "No dialog tool found (install zenity or kdialog)"}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  # --- Pipeline HTML Pages ---

  get "/pipeline" do
    html = SymphonyElixir.Server.PipelineUI.render_list()

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  get "/pipeline/:id" do
    case LocalBoard.get_pipeline(id) do
      {:ok, pipeline} ->
        html = SymphonyElixir.Server.PipelineUI.render_designer(pipeline)

        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, html)

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(404, "<h1>Pipeline not found</h1>")
    end
  end

  # --- Pipeline JSON API ---

  get "/api/pipelines" do
    pipelines = LocalBoard.list_pipelines()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{pipelines: pipelines}))
  end

  post "/api/pipelines" do
    {:ok, pipeline} = LocalBoard.create_pipeline(conn.body_params)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(201, Jason.encode!(pipeline))
  end

  get "/api/pipelines/:id" do
    case LocalBoard.get_pipeline(id) do
      {:ok, pipeline} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(pipeline))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  patch "/api/pipelines/:id" do
    case LocalBoard.update_pipeline(id, conn.body_params) do
      {:ok, pipeline} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(pipeline))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  delete "/api/pipelines/:id" do
    case LocalBoard.delete_pipeline(id) do
      :ok ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{ok: true}))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  # --- Pipeline Run API ---

  post "/api/pipelines/:id/run" do
    case LocalBoard.create_pipeline_run(id) do
      {:ok, run} ->
        # Start the pipeline runner
        SymphonyElixir.PipelineRunner.start_run(id, run.id)

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(201, Jason.encode!(run))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  get "/api/pipelines/:id/runs" do
    runs = LocalBoard.list_pipeline_runs(id)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{runs: runs}))
  end

  get "/api/pipelines/:pipeline_id/runs/:run_id" do
    case LocalBoard.get_pipeline_run(pipeline_id, run_id) do
      {:ok, run} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(run))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  post "/api/pipelines/:pipeline_id/runs/:run_id/pause" do
    case LocalBoard.update_pipeline_run_status(run_id, "paused") do
      {:ok, run} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(run))

      {:error, _} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  post "/api/pipelines/:pipeline_id/runs/:run_id/resume" do
    case LocalBoard.update_pipeline_run_status(run_id, "running") do
      {:ok, run} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(run))

      {:error, _} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  post "/api/pipelines/:pipeline_id/runs/:run_id/cancel" do
    case LocalBoard.update_pipeline_run_status(run_id, "cancelled") do
      {:ok, run} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(run))

      {:error, _} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  post "/api/pipelines/:pipeline_id/runs/:run_id/gate/:node_id" do
    action = Map.get(conn.body_params, "action", "approve")
    feedback = Map.get(conn.body_params, "feedback")

    case LocalBoard.record_gate_decision(run_id, node_id, action, feedback) do
      {:ok, run} ->
        # Notify the pipeline runner about the gate decision
        SymphonyElixir.PipelineRunner.gate_decided(run_id, node_id, action)

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(run))

      {:error, _} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end

  get "/api/pipeline-runs/active" do
    runs = LocalBoard.list_all_active_runs()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{runs: runs}))
  end

  # --- Backup & Restore ---

  get "/api/backups" do
    backups = LocalBoard.list_backups()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{backups: backups}))
  end

  post "/api/backups/restore" do
    filename = conn.body_params["filename"]

    case LocalBoard.restore_backup(filename) do
      {:ok, _board} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{ok: true, message: "Restored from #{filename}"}))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "restore_failed", reason: inspect(reason)}))
    end
  end

  # --- Knowledge Base / Vault ---

  post "/api/vault/test" do
    kb_type = conn.body_params["kb_type"] || "local"
    vault_path = conn.body_params["vault_path"] || ""

    config = %{"kb_type" => kb_type, "vault_path" => vault_path}

    case SymphonyElixir.Integrations.KnowledgeBase.test_connection(config) do
      {:ok, message} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{ok: true, message: message}))

      {:error, message} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{ok: false, message: message}))
    end
  end

  post "/api/vault/send" do
    issue_id = conn.body_params["issue_id"]
    kb_type = Settings.get("kb_type") || "local"
    vault_path = Settings.get("kb_vault_path") || ""
    subfolder = Settings.get("kb_subfolder") || "symphony"

    if vault_path == "" and kb_type not in ["local", "confluence"] do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(400, Jason.encode!(%{error: "Knowledge base vault not configured"}))
    else
      case LocalBoard.get_issue(issue_id) do
        {:ok, issue} ->
          product_name = resolve_product_name(issue)

          config = %{
            "kb_type" => kb_type,
            "vault_path" => vault_path,
            "subfolder" => subfolder,
            "action" => "write_note"
          }

          # Try to find workspace reports
          report_files = find_issue_reports(issue)

          notes_written =
            if report_files != [] do
              Enum.flat_map(report_files, fn report_path ->
                title = Path.basename(report_path, ".md")
                content = File.read!(report_path)

                context = %{
                  "title" => title,
                  "content" => content,
                  "tags" => ["symphony" | issue.labels || []],
                  "source_issue" => issue.identifier,
                  "product_name" => product_name
                }

                case SymphonyElixir.Integrations.KnowledgeBase.execute(config, context) do
                  {:ok, %{path: path}} -> [path]
                  _ -> []
                end
              end)
            else
              # No reports — write issue description as a note
              title = issue.title || "Untitled"
              content = issue.description || issue.title || ""

              context = %{
                "title" => title,
                "content" => content,
                "tags" => ["symphony" | issue.labels || []],
                "source_issue" => issue.identifier,
                "product_name" => product_name
              }

              case SymphonyElixir.Integrations.KnowledgeBase.execute(config, context) do
                {:ok, %{path: path}} -> [path]
                _ -> []
              end
            end

          source = if report_files != [], do: "reports", else: "description"

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            200,
            Jason.encode!(%{ok: true, notes_written: notes_written, source: source})
          )

        {:error, :not_found} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(404, Jason.encode!(%{error: "Issue not found"}))
      end
    end
  end

  get "/api/vault/search" do
    query = conn.query_params["q"] || ""
    kb_type = Settings.get("kb_type") || "local"
    vault_path = Settings.get("kb_vault_path") || ""
    subfolder = Settings.get("kb_subfolder") || "symphony"

    config = %{
      "kb_type" => kb_type,
      "vault_path" => vault_path,
      "subfolder" => subfolder,
      "action" => "search"
    }

    context = %{"query" => query}

    case SymphonyElixir.Integrations.KnowledgeBase.execute(config, context) do
      {:ok, %{results: results}} ->
        serialized =
          Enum.map(results, fn r ->
            %{"path" => r.path, "title" => r.title, "snippet" => r.snippet}
          end)

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{results: serialized}))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, Jason.encode!(%{error: inspect(reason)}))
    end
  end

  get "/api/vault/note" do
    note_path = conn.query_params["path"] || ""
    kb_type = Settings.get("kb_type") || "local"
    vault_path = Settings.get("kb_vault_path") || ""

    config = %{"kb_type" => kb_type, "vault_path" => vault_path, "action" => "read_note"}
    context = %{"note_path" => note_path}

    case SymphonyElixir.Integrations.KnowledgeBase.execute(config, context) do
      {:ok, result} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          200,
          Jason.encode!(%{frontmatter: result.frontmatter, content: result.content})
        )

      {:error, :path_traversal} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(403, Jason.encode!(%{error: "path_traversal"}))

      {:error, :file_not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, Jason.encode!(%{error: inspect(reason)}))
    end
  end

  delete "/api/vault/note" do
    note_path = conn.body_params["path"] || ""
    kb_type = Settings.get("kb_type") || "local"
    vault_path = Settings.get("kb_vault_path") || ""

    config = %{"kb_type" => kb_type, "vault_path" => vault_path, "action" => "delete_note"}
    context = %{"note_path" => note_path}

    case SymphonyElixir.Integrations.KnowledgeBase.execute(config, context) do
      {:ok, _result} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{ok: true}))

      {:error, :path_traversal} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(403, Jason.encode!(%{error: "path_traversal"}))

      {:error, :file_not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, Jason.encode!(%{error: inspect(reason)}))
    end
  end

  defp resolve_product_name(issue) do
    if issue.product_id do
      case LocalBoard.get_product(issue.product_id) do
        {:ok, product} -> product.name || "unknown"
        _ -> nil
      end
    else
      nil
    end
  end

  defp find_issue_reports(issue) do
    workspace_key = issue.identifier || issue.id

    # Build candidates: configured workspace root + common fallback locations
    workspace_root =
      case Process.get(:symphony_workspace_root) do
        nil ->
          # Try to read from the default tmp-based workspace root
          Path.join(System.tmp_dir!(), "symphony_workspaces")

        root ->
          root
      end

    # The agent's actual workspace may be the project/product path (not the
    # symphony workspace dir) — resolve those paths too.
    project_paths = resolve_issue_project_paths(issue)

    candidates =
      Enum.map(project_paths, fn p -> Path.join(p, "reports") end) ++
        [
          Path.join([workspace_root, workspace_key, "reports"]),
          Path.join(["~/code/symphony-workspaces", workspace_key, "reports"]),
          Path.join(["~/symphony_workspaces", workspace_key, "reports"])
        ]

    candidates
    |> Enum.map(&Path.expand/1)
    |> Enum.find(fn dir -> File.dir?(dir) end)
    |> case do
      nil -> []
      dir -> Path.wildcard(Path.join(dir, "*.md") |> String.replace("\\", "/"))
    end
  end

  # Resolve the project/product workspace paths an agent would have used.
  defp resolve_issue_project_paths(issue) do
    project_path =
      case issue.project_id do
        pid when is_binary(pid) and pid != "" ->
          case LocalBoard.get_project(pid) do
            {:ok, %{path: path}} when is_binary(path) and path != "" -> path
            _ -> nil
          end

        _ ->
          nil
      end

    product_paths =
      case issue.product_id do
        prod_id when is_binary(prod_id) and prod_id != "" ->
          case LocalBoard.get_product(prod_id) do
            {:ok, product} ->
              (product.project_ids || [])
              |> Enum.flat_map(fn pid ->
                case LocalBoard.get_project(pid) do
                  {:ok, %{path: path}} when is_binary(path) and path != "" -> [path]
                  _ -> []
                end
              end)

            _ ->
              []
          end

        _ ->
          []
      end

    Enum.reject([project_path | product_paths], &is_nil/1)
    |> Enum.uniq()
  end

  # Build a condensed KB context string for AI draft prompts.
  # Reads KB notes for the product and extracts headings + rule IDs to keep it concise.
  defp build_kb_context_for_draft(nil), do: ""
  defp build_kb_context_for_draft(""), do: ""

  defp build_kb_context_for_draft(product_id) do
    kb_type = Settings.get("kb_type") || "local"
    vault_path = Settings.get("kb_vault_path") || ""
    subfolder = Settings.get("kb_subfolder") || "symphony"

    config = %{
      "kb_type" => kb_type,
      "vault_path" => vault_path,
      "subfolder" => subfolder,
      "action" => "search"
    }

    # Resolve product name for subfolder
    product_name =
      case LocalBoard.get_product(product_id) do
        {:ok, prod} -> prod.name
        _ -> nil
      end

    if product_name == nil do
      ""
    else
      # Search for all notes under product subfolder
      context = %{"query" => "", "product_name" => product_name}

      case SymphonyElixir.Integrations.KnowledgeBase.execute(config, context) do
        {:ok, %{results: results}} when results != [] ->
          # Read each note and extract a summary (headings + rule IDs)
          summaries =
            results
            |> Enum.take(10)
            |> Enum.map(fn result ->
              full_config = Map.put(config, "action", "read_note")
              note_context = %{"note_path" => result.path}

              case SymphonyElixir.Integrations.KnowledgeBase.execute(full_config, note_context) do
                {:ok, %{content: content}} ->
                  summary = extract_kb_summary(content, result.title)
                  "### #{result.title}\n#{summary}"

                _ ->
                  nil
              end
            end)
            |> Enum.reject(&is_nil/1)

          if summaries == [] do
            ""
          else
            "\n\nKnowledge Base (documented business rules for this product):\n" <>
              Enum.join(summaries, "\n\n")
          end

        _ ->
          ""
      end
    end
  end

  # Extract headings and rule/constraint IDs from KB note content for a concise summary.
  defp extract_kb_summary(content, _title) do
    lines = String.split(content, "\n")

    relevant =
      lines
      |> Enum.filter(fn line ->
        trimmed = String.trim(line)

        String.starts_with?(trimmed, "#") or
          Regex.match?(~r/^(BR|CV|HC|EC|WF)-\d+/, trimmed) or
          Regex.match?(~r/^\*\*(BR|CV|HC|EC|WF)-\d+/, trimmed) or
          Regex.match?(~r/^- \*\*(BR|CV|HC|EC|WF)-\d+/, trimmed) or
          Regex.match?(~r/^\|\s*(BR|CV|HC|EC|WF)-\d+/, trimmed)
      end)
      |> Enum.take(40)

    if relevant == [] do
      # Fallback: first 10 non-empty lines
      lines
      |> Enum.reject(fn l -> String.trim(l) == "" end)
      |> Enum.reject(fn l -> String.starts_with?(String.trim(l), "---") end)
      |> Enum.take(10)
      |> Enum.join("\n")
    else
      Enum.join(relevant, "\n")
    end
  end

  match _ do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "not_found"}))
  end
end

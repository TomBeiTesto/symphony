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
    html = SymphonyElixir.Server.BoardUI.render()

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  get "/projects" do
    html = SymphonyElixir.Server.ProjectsUI.render()

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

  get "/review" do
    html = SymphonyElixir.Server.ReviewUI.render()

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
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

  post "/api/issues/:id/follow-ups/:fu_id/accept" do
    with {:ok, issue} <- LocalBoard.get_issue(id),
         {:ok, follow_up, agent_run} <- find_follow_up(issue, fu_id),
         true <- follow_up["status"] == "proposed" do
      # Check if this is a product feature-generation issue
      prod_id = extract_product_id(issue)

      result =
        if prod_id do
          # Add as a product feature instead of creating an issue
          feature_attrs = %{
            "name" => follow_up["title"],
            "description" => follow_up["description"]
          }

          case LocalBoard.add_product_feature(prod_id, feature_attrs) do
            {:ok, prod} ->
              # Find the newly added feature (last one)
              new_feature = List.last(prod.features)
              %{ok: true, feature: new_feature, product_id: prod_id}

            {:error, _} ->
              # Fallback: create as issue if product not found
              create_follow_up_issue(issue, follow_up, id)
          end
        else
          create_follow_up_issue(issue, follow_up, id)
        end

      # Update follow-up status
      updated_run =
        update_follow_up_status(agent_run, fu_id, "accepted", result[:issue])

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

  post "/api/issues" do
    case LocalBoard.create_issue(conn.body_params) do
      {:ok, issue} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(201, Jason.encode!(issue))
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
      recursive: conn.body_params["recursive"] == true
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

  post "/api/projects/import" do
    candidates = Map.get(conn.body_params, "projects", [])

    created =
      Enum.map(candidates, fn attrs ->
        case LocalBoard.create_project(attrs) do
          {:ok, project} -> project
        end
      end)

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
      case LocalBoard.set_feature_status(prod_id, feature_id, project_id, status) do
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
  end

  post "/api/products/:id/analyze-gaps" do
    case LocalBoard.get_product(id) do
      {:ok, prod} ->
        # Resolve project names for context
        projects =
          Enum.map(prod.project_ids, fn pid ->
            case LocalBoard.get_project(pid) do
              {:ok, p} -> p
              _ -> %{id: pid, name: pid, description: nil}
            end
          end)

        gaps = analyze_product_gaps(prod, projects)

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{gaps: gaps}))

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

          project_list =
            projects
            |> Enum.map(fn p ->
              "- #{p.name}" <>
                if(p.description, do: ": #{p.description}", else: "") <>
                if(p.repo_url, do: " [repo: #{p.repo_url}]", else: "")
            end)
            |> Enum.join("\n")

          existing =
            prod.features
            |> Enum.map(fn f -> "- #{f.name}: #{f.description || ""}" end)
            |> Enum.join("\n")

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
          Identify cross-cutting features that span the projects in this product.
          A feature is a capability or concern that may need implementation in one or more projects (e.g. "API Key Management", "Error Handling", "User Documentation").

          Propose each feature as a follow-up with:
          - **Title**: The feature name (short, descriptive — e.g. "API Key Management")
          - **Description**: What this feature covers, which projects it applies to, and why it's needed
          - **Labels**: `["product-feature"]`

          These will be added to the product feature matrix for tracking across projects.
          Do NOT propose implementation tasks — propose high-level features.
          """

          {:ok, issue} =
            LocalBoard.create_issue(%{
              "title" => "Generate features for #{prod.name}",
              "description" => description,
              "labels" => ["product-review", "generate-features", "product:#{id}"],
              "priority" => 2,
              "state" => "Todo"
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
      projects = resolve_product_projects(prod)

      # Create one check issue per project that isn't already done or n/a
      issues_created =
        projects
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
          """

          {:ok, issue} =
            LocalBoard.create_issue(%{
              "title" => "Check: #{feature.name} in #{p.name}",
              "description" => description,
              "labels" => ["product-review", "feature-check"],
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
            "in_progress"
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

  get "/api/templates" do
    templates = LocalBoard.list_templates()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{templates: templates}))
  end

  get "/api/templates/:id" do
    case LocalBoard.get_template(id) do
      {:ok, template} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(template))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not_found"}))
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

  defp update_follow_up_status(agent_run, fu_id, status, new_issue_or_nil) do
    follow_ups =
      Enum.map(agent_run["follow_ups"] || [], fn fu ->
        if fu["id"] == fu_id do
          updated = Map.put(fu, "status", status)

          case new_issue_or_nil do
            %{id: iid, identifier: ident} ->
              updated
              |> Map.put("created_issue_id", iid)
              |> Map.put("created_issue_identifier", ident)

            _ ->
              updated
          end
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

  # --- Gap analysis helper ---

  defp analyze_product_gaps(prod, projects) do
    project_map = Map.new(projects, fn p -> {p.id, p} end)

    Enum.flat_map(prod.features, fn feature ->
      Enum.flat_map(prod.project_ids, fn pid ->
        status = Map.get(feature.statuses, pid, "missing")
        project = Map.get(project_map, pid, %{name: pid})

        if status in ["missing", "planned"] do
          [
            %{
              feature_id: feature.id,
              feature_name: feature.name,
              project_id: pid,
              project_name: project.name,
              status: status,
              reason: "Feature '#{feature.name}' is #{status} in project '#{project.name}'"
            }
          ]
        else
          []
        end
      end)
    end)
  end

  match _ do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "not_found"}))
  end
end

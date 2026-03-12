defmodule SymphonyElixir.Server.BoardRouterTest do
  use ExUnit.Case, async: false
  import Plug.Test

  alias SymphonyElixir.LocalBoard
  alias SymphonyElixir.Settings
  alias SymphonyElixir.Server.BoardRouter

  @store_path "test_board_router_#{System.unique_integer([:positive])}.json"
  @settings_path "test_board_router_settings_#{System.unique_integer([:positive])}.json"

  setup do
    start_supervised!(
      {LocalBoard,
       store_path: @store_path, states: ["Todo", "In Progress", "Done"], project_prefix: "BRD"}
    )

    start_supervised!({Settings, store_path: @settings_path})

    on_exit(fn ->
      File.rm(@store_path)
      File.rm(@settings_path)
    end)

    :ok
  end

  defp call(method, path, body \\ nil) do
    conn =
      if body do
        conn(method, path, Jason.encode!(body))
        |> Plug.Conn.put_req_header("content-type", "application/json")
      else
        conn(method, path)
      end

    BoardRouter.call(conn, BoardRouter.init([]))
  end

  describe "GET /" do
    test "returns HTML board page" do
      conn = call(:get, "/")
      assert conn.status == 200
      assert conn.resp_body =~ "Symphony Board"
      assert conn.resp_body =~ "<main class=\"board\""
    end
  end

  describe "GET /api/snapshot" do
    test "returns board snapshot JSON" do
      conn = call(:get, "/api/snapshot")
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert is_list(body["columns"])
      assert is_list(body["states"])
      assert is_integer(body["total_issues"])
    end
  end

  describe "GET /api/states" do
    test "returns state list" do
      conn = call(:get, "/api/states")
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert "Todo" in body["states"]
      assert "Done" in body["states"]
    end
  end

  describe "POST /api/issues" do
    test "creates a new issue" do
      conn = call(:post, "/api/issues", %{"title" => "New task", "state" => "Todo"})
      assert conn.status == 201
      body = Jason.decode!(conn.resp_body)
      assert body["title"] == "New task"
      assert body["state"] == "Todo"
      assert body["identifier"] =~ ~r/^BRD-\d+$/
    end
  end

  describe "GET /api/issues" do
    test "lists all issues" do
      LocalBoard.create_issue(%{"title" => "A"})
      LocalBoard.create_issue(%{"title" => "B"})

      conn = call(:get, "/api/issues")
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert length(body["issues"]) == 2
    end
  end

  describe "GET /api/issues/:id" do
    test "returns issue by id" do
      {:ok, issue} = LocalBoard.create_issue(%{"title" => "Find me"})

      conn = call(:get, "/api/issues/#{issue.id}")
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["title"] == "Find me"
    end

    test "returns 404 for missing issue" do
      conn = call(:get, "/api/issues/nonexistent")
      assert conn.status == 404
    end
  end

  describe "PATCH /api/issues/:id" do
    test "updates issue fields" do
      {:ok, issue} = LocalBoard.create_issue(%{"title" => "Original"})

      conn =
        call(:patch, "/api/issues/#{issue.id}", %{
          "title" => "Updated",
          "description" => "New desc"
        })

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["title"] == "Updated"
      assert body["description"] == "New desc"
    end

    test "returns 404 for missing issue" do
      conn = call(:patch, "/api/issues/bogus", %{"title" => "x"})
      assert conn.status == 404
    end
  end

  describe "PATCH /api/issues/:id/move" do
    test "moves issue to new state" do
      {:ok, issue} = LocalBoard.create_issue(%{"title" => "Move me", "state" => "Todo"})

      conn = call(:patch, "/api/issues/#{issue.id}/move", %{"state" => "In Progress"})
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["state"] == "In Progress"
    end

    test "returns 400 when state is missing" do
      {:ok, issue} = LocalBoard.create_issue(%{"title" => "X"})
      conn = call(:patch, "/api/issues/#{issue.id}/move", %{})
      assert conn.status == 400
    end

    test "returns 404 for missing issue" do
      conn = call(:patch, "/api/issues/bogus/move", %{"state" => "Done"})
      assert conn.status == 404
    end
  end

  describe "DELETE /api/issues/:id" do
    test "deletes an issue" do
      {:ok, issue} = LocalBoard.create_issue(%{"title" => "Delete me"})

      conn = call(:delete, "/api/issues/#{issue.id}")
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["deleted"] == true

      # Verify gone
      conn2 = call(:get, "/api/issues/#{issue.id}")
      assert conn2.status == 404
    end

    test "returns 404 for missing issue" do
      conn = call(:delete, "/api/issues/bogus")
      assert conn.status == 404
    end
  end

  describe "unknown routes" do
    test "returns 404" do
      conn = call(:get, "/api/nonexistent")
      assert conn.status == 404
    end
  end

  # --- Project Endpoints ---

  describe "GET /api/projects" do
    test "returns empty projects list" do
      conn = call(:get, "/api/projects")
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["projects"] == []
    end

    test "returns created projects" do
      LocalBoard.create_project(%{"name" => "Test Proj"})
      conn = call(:get, "/api/projects")
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert length(body["projects"]) == 1
      assert hd(body["projects"])["name"] == "Test Proj"
    end
  end

  describe "POST /api/projects" do
    test "creates a new project" do
      conn =
        call(:post, "/api/projects", %{
          "name" => "New Project",
          "repo_url" => "https://github.com/test/repo.git"
        })

      assert conn.status == 201
      body = Jason.decode!(conn.resp_body)
      assert body["name"] == "New Project"
      assert body["repo_url"] == "https://github.com/test/repo.git"
      assert body["slug"] == "new-project"
    end
  end

  describe "GET /api/projects/:id" do
    test "returns project by id" do
      {:ok, project} = LocalBoard.create_project(%{"name" => "Find Me"})
      conn = call(:get, "/api/projects/#{project.id}")
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["name"] == "Find Me"
    end

    test "returns 404 for missing project" do
      conn = call(:get, "/api/projects/nonexistent")
      assert conn.status == 404
    end
  end

  describe "PATCH /api/projects/:id" do
    test "updates project fields" do
      {:ok, project} = LocalBoard.create_project(%{"name" => "Old"})
      conn = call(:patch, "/api/projects/#{project.id}", %{"name" => "New"})
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["name"] == "New"
    end

    test "returns 404 for missing project" do
      conn = call(:patch, "/api/projects/bogus", %{"name" => "x"})
      assert conn.status == 404
    end
  end

  describe "DELETE /api/projects/:id" do
    test "deletes a project" do
      {:ok, project} = LocalBoard.create_project(%{"name" => "Remove"})
      conn = call(:delete, "/api/projects/#{project.id}")
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["deleted"] == true
    end

    test "cascade deletes project issues" do
      {:ok, project} = LocalBoard.create_project(%{"name" => "Cascade"})
      {:ok, _} = LocalBoard.create_issue(%{"title" => "Proj Issue", "project_id" => project.id})
      {:ok, _} = LocalBoard.create_issue(%{"title" => "Standalone"})

      conn = call(:delete, "/api/projects/#{project.id}")
      assert conn.status == 200

      # Only standalone issue remains
      issues_conn = call(:get, "/api/issues")
      body = Jason.decode!(issues_conn.resp_body)
      assert length(body["issues"]) == 1
      assert hd(body["issues"])["title"] == "Standalone"
    end

    test "returns 404 for missing project" do
      conn = call(:delete, "/api/projects/bogus")
      assert conn.status == 404
    end
  end

  describe "POST /api/projects/:id/clone" do
    test "returns 400 when project has no repo_url" do
      {:ok, project} = LocalBoard.create_project(%{"name" => "No Repo"})
      conn = call(:post, "/api/projects/#{project.id}/clone")
      assert conn.status == 400
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "no_repo_url"
    end

    test "returns 404 for missing project" do
      conn = call(:post, "/api/projects/nonexistent/clone")
      assert conn.status == 404
    end
  end

  # --- Template Endpoints ---

  describe "GET /api/templates" do
    test "returns built-in templates" do
      conn = call(:get, "/api/templates")
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      templates = body["templates"]
      assert is_list(templates)
      assert length(templates) >= 5
      ids = Enum.map(templates, & &1["id"])
      assert "code-review" in ids
      assert "bug-report" in ids
    end
  end

  describe "GET /api/templates/:id" do
    test "returns specific template" do
      conn = call(:get, "/api/templates/code-review")
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["name"] == "Code Review"
    end

    test "returns 404 for unknown template" do
      conn = call(:get, "/api/templates/nonexistent")
      assert conn.status == 404
    end
  end

  # --- Snapshot includes projects ---

  describe "GET /api/snapshot with projects" do
    test "includes projects in snapshot" do
      LocalBoard.create_project(%{"name" => "Snap Proj"})
      conn = call(:get, "/api/snapshot")
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert is_list(body["projects"])
      assert length(body["projects"]) == 1
    end
  end

  # --- Settings page & API ---

  describe "GET /settings" do
    test "returns HTML settings page" do
      conn = call(:get, "/settings")
      assert conn.status == 200
      assert conn.resp_body =~ "Symphony Settings"
      assert conn.resp_body =~ "Git Provider"
      assert conn.resp_body =~ "AI Provider"
      assert conn.resp_body =~ "Issue Tracker"
    end
  end

  describe "GET /api/settings" do
    test "returns all settings as JSON" do
      conn = call(:get, "/api/settings")
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["ai_provider"] == "claude"
      assert body["git_provider"] == "gitlab"
      assert is_binary(body["ai_model"])
    end
  end

  describe "PATCH /api/settings" do
    test "updates settings and returns new values" do
      conn = call(:patch, "/api/settings", %{"ai_provider" => "openai", "ai_model" => "gpt-4o"})
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["ai_provider"] == "openai"
      assert body["ai_model"] == "gpt-4o"
    end

    test "ignores unknown keys" do
      conn = call(:patch, "/api/settings", %{"unknown_key" => "val", "ai_provider" => "gemini"})
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["ai_provider"] == "gemini"
      refute Map.has_key?(body, "unknown_key")
    end
  end

  # --- Task Lineage ---

  describe "GET /task-lineage" do
    test "returns HTML task lineage page" do
      conn = call(:get, "/task-lineage")
      assert conn.status == 200
      assert conn.resp_body =~ "Task Lineage"
      assert conn.resp_body =~ "tree-viewport"
    end
  end

  describe "POST /api/settings/reset" do
    test "resets settings to defaults" do
      Settings.update(%{"ai_provider" => "openai"})
      conn = call(:post, "/api/settings/reset")
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["ai_provider"] == "claude"
    end
  end

  # --- Auto Add Settings ---

  describe "GET /api/settings/auto-add" do
    test "returns auto-add defaults" do
      conn = call(:get, "/api/settings/auto-add")
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["auto_add_enabled"] == "false"
      assert body["max_todo_parallel"] == "3"
      assert body["segregate_by_project"] == "false"
    end
  end

  describe "PATCH /api/settings/auto-add" do
    test "updates auto_add_enabled" do
      conn = call(:patch, "/api/settings/auto-add", %{"auto_add_enabled" => "true"})
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["auto_add_enabled"] == "true"
      assert body["max_todo_parallel"] == "3"
    end

    test "updates max_todo_parallel" do
      conn = call(:patch, "/api/settings/auto-add", %{"max_todo_parallel" => "2"})
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["max_todo_parallel"] == "2"
    end

    test "updates segregate_by_project" do
      conn = call(:patch, "/api/settings/auto-add", %{"segregate_by_project" => "true"})
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["segregate_by_project"] == "true"
    end

    test "updates all board settings at once" do
      conn =
        call(:patch, "/api/settings/auto-add", %{
          "auto_add_enabled" => "true",
          "max_todo_parallel" => "1",
          "segregate_by_project" => "true"
        })

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["auto_add_enabled"] == "true"
      assert body["max_todo_parallel"] == "1"
      assert body["segregate_by_project"] == "true"
    end
  end

  describe "board UI auto-add bar" do
    test "renders auto-add and segregation controls" do
      conn = call(:get, "/")
      assert conn.status == 200
      assert conn.resp_body =~ "auto-add-dropdown"
      assert conn.resp_body =~ "auto-add-toggle"
      assert conn.resp_body =~ "max-todo-select"
      assert conn.resp_body =~ "Auto-dispatch issues"
      assert conn.resp_body =~ "segregate-toggle"
      assert conn.resp_body =~ "Group by Project"
    end
  end

  # --- Product Endpoints ---

  describe "GET /api/products" do
    test "returns empty products list" do
      conn = call(:get, "/api/products")
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["products"] == []
    end

    test "returns created products" do
      LocalBoard.create_product(%{"name" => "B2C API"})
      conn = call(:get, "/api/products")
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert length(body["products"]) == 1
      assert hd(body["products"])["name"] == "B2C API"
    end
  end

  describe "POST /api/products" do
    test "creates a new product" do
      {:ok, proj} = LocalBoard.create_project(%{"name" => "Data API"})

      conn =
        call(:post, "/api/products", %{
          "name" => "B2C Product",
          "description" => "Customer-facing",
          "project_ids" => [proj.id]
        })

      assert conn.status == 201
      body = Jason.decode!(conn.resp_body)
      assert body["name"] == "B2C Product"
      assert body["description"] == "Customer-facing"
      assert body["project_ids"] == [proj.id]
    end
  end

  describe "GET /api/products/:id" do
    test "returns product by id" do
      {:ok, product} = LocalBoard.create_product(%{"name" => "Find Me"})
      conn = call(:get, "/api/products/#{product.id}")
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["name"] == "Find Me"
    end

    test "returns 404 for missing product" do
      conn = call(:get, "/api/products/nonexistent")
      assert conn.status == 404
    end
  end

  describe "PATCH /api/products/:id" do
    test "updates product fields" do
      {:ok, product} = LocalBoard.create_product(%{"name" => "Old"})
      conn = call(:patch, "/api/products/#{product.id}", %{"name" => "New"})
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["name"] == "New"
    end

    test "returns 404 for missing product" do
      conn = call(:patch, "/api/products/bogus", %{"name" => "x"})
      assert conn.status == 404
    end
  end

  describe "DELETE /api/products/:id" do
    test "deletes a product" do
      {:ok, product} = LocalBoard.create_product(%{"name" => "Remove"})
      conn = call(:delete, "/api/products/#{product.id}")
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["deleted"] == true
    end

    test "returns 404 for missing product" do
      conn = call(:delete, "/api/products/bogus")
      assert conn.status == 404
    end
  end

  # --- Product Feature Endpoints ---

  describe "POST /api/products/:id/features" do
    test "adds a feature to a product" do
      {:ok, proj} = LocalBoard.create_project(%{"name" => "API"})

      {:ok, product} =
        LocalBoard.create_product(%{"name" => "Test", "project_ids" => [proj.id]})

      conn =
        call(:post, "/api/products/#{product.id}/features", %{
          "name" => "Authentication",
          "description" => "API key auth"
        })

      assert conn.status == 201
      body = Jason.decode!(conn.resp_body)
      assert length(body["features"]) == 1
      feature = hd(body["features"])
      assert feature["name"] == "Authentication"
      assert feature["statuses"][proj.id] == "missing"
    end

    test "adds a feature with category" do
      {:ok, proj} = LocalBoard.create_project(%{"name" => "API"})

      {:ok, product} =
        LocalBoard.create_product(%{"name" => "Test", "project_ids" => [proj.id]})

      conn =
        call(:post, "/api/products/#{product.id}/features", %{
          "name" => "Auth",
          "category" => "Security"
        })

      assert conn.status == 201
      body = Jason.decode!(conn.resp_body)
      feature = hd(body["features"])
      assert feature["category"] == "Security"
    end

    test "returns 404 for missing product" do
      conn = call(:post, "/api/products/bogus/features", %{"name" => "X"})
      assert conn.status == 404
    end
  end

  describe "PATCH /api/products/:id/features/bulk-category" do
    test "sets category on multiple features" do
      {:ok, product} = LocalBoard.create_product(%{"name" => "Bulk Test"})
      {:ok, product} = LocalBoard.add_product_feature(product.id, %{"name" => "A"})
      {:ok, product} = LocalBoard.add_product_feature(product.id, %{"name" => "B"})

      fids = Enum.map(product.features, & &1.id)

      conn =
        call(:patch, "/api/products/#{product.id}/features/bulk-category", %{
          "feature_ids" => fids,
          "category" => "Infrastructure"
        })

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      cats = Enum.map(body["features"], & &1["category"])
      assert cats == ["Infrastructure", "Infrastructure"]
    end

    test "returns 404 for missing product" do
      conn =
        call(:patch, "/api/products/bogus/features/bulk-category", %{
          "feature_ids" => [],
          "category" => "X"
        })

      assert conn.status == 404
    end
  end

  describe "feature depends_on" do
    test "adds a feature with depends_on" do
      {:ok, product} = LocalBoard.create_product(%{"name" => "Deps Test"})
      {:ok, product} = LocalBoard.add_product_feature(product.id, %{"name" => "Base"})
      base_id = hd(product.features).id

      conn =
        call(:post, "/api/products/#{product.id}/features", %{
          "name" => "Dependent",
          "depends_on" => [base_id]
        })

      assert conn.status == 201
      body = Jason.decode!(conn.resp_body)
      dep_feature = Enum.find(body["features"], fn f -> f["name"] == "Dependent" end)
      assert dep_feature["depends_on"] == [base_id]
    end

    test "updates depends_on on existing feature" do
      {:ok, product} = LocalBoard.create_product(%{"name" => "Deps Test"})
      {:ok, product} = LocalBoard.add_product_feature(product.id, %{"name" => "A"})
      {:ok, product} = LocalBoard.add_product_feature(product.id, %{"name" => "B"})
      [a, b] = product.features

      conn =
        call(
          :patch,
          "/api/products/#{product.id}/features/#{b.id}",
          %{"depends_on" => [a.id]}
        )

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      updated_b = Enum.find(body["features"], fn f -> f["id"] == b.id end)
      assert updated_b["depends_on"] == [a.id]
    end
  end

  describe "feature status_history" do
    test "records history when setting feature status" do
      {:ok, proj} = LocalBoard.create_project(%{"name" => "API"})

      {:ok, product} =
        LocalBoard.create_product(%{"name" => "History Test", "project_ids" => [proj.id]})

      {:ok, product} =
        LocalBoard.add_product_feature(product.id, %{"name" => "Auth"})

      feature = hd(product.features)

      conn =
        call(
          :patch,
          "/api/products/#{product.id}/features/#{feature.id}/status",
          %{"project_id" => proj.id, "status" => "done", "source" => "agent_check"}
        )

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      updated_feature = hd(body["features"])
      assert updated_feature["statuses"][proj.id] == "done"

      history = updated_feature["status_history"]
      assert length(history) == 1
      entry = hd(history)
      assert entry["project_id"] == proj.id
      assert entry["status"] == "done"
      assert entry["source"] == "agent_check"
      assert entry["changed_at"] != nil
    end

    test "accumulates multiple history entries" do
      {:ok, proj} = LocalBoard.create_project(%{"name" => "API"})

      {:ok, product} =
        LocalBoard.create_product(%{"name" => "History Test", "project_ids" => [proj.id]})

      {:ok, product} =
        LocalBoard.add_product_feature(product.id, %{"name" => "Auth"})

      feature = hd(product.features)

      # First status change
      call(
        :patch,
        "/api/products/#{product.id}/features/#{feature.id}/status",
        %{"project_id" => proj.id, "status" => "in_progress"}
      )

      # Second status change
      conn =
        call(
          :patch,
          "/api/products/#{product.id}/features/#{feature.id}/status",
          %{"project_id" => proj.id, "status" => "done"}
        )

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      updated_feature = hd(body["features"])
      history = updated_feature["status_history"]
      assert length(history) == 2
      # Most recent first
      assert hd(history)["status"] == "done"
      assert List.last(history)["status"] == "in_progress"
    end
  end

  describe "PATCH /api/products/:prod_id/features/:feature_id/status" do
    test "updates feature status for a project" do
      {:ok, proj} = LocalBoard.create_project(%{"name" => "API"})

      {:ok, product} =
        LocalBoard.create_product(%{"name" => "Test", "project_ids" => [proj.id]})

      {:ok, product} =
        LocalBoard.add_product_feature(product.id, %{"name" => "Auth"})

      feature = hd(product.features)

      conn =
        call(
          :patch,
          "/api/products/#{product.id}/features/#{feature.id}/status",
          %{"project_id" => proj.id, "status" => "done"}
        )

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      updated_feature = hd(body["features"])
      assert updated_feature["statuses"][proj.id] == "done"
    end
  end

  describe "DELETE /api/products/:prod_id/features/:feature_id" do
    test "removes a feature" do
      {:ok, product} = LocalBoard.create_product(%{"name" => "Test"})

      {:ok, product} =
        LocalBoard.add_product_feature(product.id, %{"name" => "Remove Me"})

      feature = hd(product.features)

      conn = call(:delete, "/api/products/#{product.id}/features/#{feature.id}")
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["features"] == []
    end
  end

  # --- Products Page ---

  describe "GET /products" do
    test "returns HTML products page" do
      conn = call(:get, "/products")
      assert conn.status == 200
      assert conn.resp_body =~ "Products"
    end
  end

  # --- Analyze Existing Features ---

  describe "POST /api/products/:id/analyze-existing-features" do
    test "creates an issue to analyze existing features" do
      {:ok, proj} = LocalBoard.create_project(%{"name" => "API", "repo_url" => "https://github.com/test/api.git"})

      {:ok, product} =
        LocalBoard.create_product(%{
          "name" => "My Product",
          "description" => "A test product",
          "project_ids" => [proj.id]
        })

      conn = call(:post, "/api/products/#{product.id}/analyze-existing-features")
      assert conn.status == 201
      body = Jason.decode!(conn.resp_body)
      assert body["issue"]["title"] =~ "Analyze existing features"
      assert body["issue"]["title"] =~ "My Product"
      assert body["issue"]["state"] == "Todo"
      assert "product-review" in body["issue"]["labels"]
      assert "analyze-existing" in body["issue"]["labels"]
      assert body["message"] =~ body["issue"]["identifier"]
    end

    test "includes existing features in issue description" do
      {:ok, proj} = LocalBoard.create_project(%{"name" => "API"})

      {:ok, product} =
        LocalBoard.create_product(%{"name" => "Feat Test", "project_ids" => [proj.id]})

      {:ok, _product} =
        LocalBoard.add_product_feature(product.id, %{"name" => "Auth", "description" => "Authentication system"})

      conn = call(:post, "/api/products/#{product.id}/analyze-existing-features")
      assert conn.status == 201
      body = Jason.decode!(conn.resp_body)
      assert body["issue"]["description"] =~ "Auth"
      assert body["issue"]["description"] =~ "Authentication system"
    end

    test "returns 404 for missing product" do
      conn = call(:post, "/api/products/nonexistent/analyze-existing-features")
      assert conn.status == 404
    end
  end

  # --- Code Review ---

  describe "POST /api/products/:id/code-review" do
    test "creates a code review issue" do
      {:ok, proj} = LocalBoard.create_project(%{"name" => "Backend", "repo_url" => "https://github.com/test/backend.git"})

      {:ok, product} =
        LocalBoard.create_product(%{
          "name" => "Platform",
          "description" => "Main platform",
          "project_ids" => [proj.id]
        })

      conn = call(:post, "/api/products/#{product.id}/code-review")
      assert conn.status == 201
      body = Jason.decode!(conn.resp_body)
      assert body["issue"]["title"] =~ "Code review"
      assert body["issue"]["title"] =~ "Platform"
      assert body["issue"]["state"] == "Todo"
      assert body["issue"]["priority"] == 1
      assert "code-review" in body["issue"]["labels"]
      assert "product-review" in body["issue"]["labels"]
      assert body["message"] =~ body["issue"]["identifier"]
    end

    test "includes focus areas in description when provided" do
      {:ok, proj} = LocalBoard.create_project(%{"name" => "API"})

      {:ok, product} =
        LocalBoard.create_product(%{"name" => "Focus Test", "project_ids" => [proj.id]})

      conn =
        call(:post, "/api/products/#{product.id}/code-review", %{
          "focus" => "security and error handling"
        })

      assert conn.status == 201
      body = Jason.decode!(conn.resp_body)
      assert body["issue"]["description"] =~ "security and error handling"
    end

    test "returns 404 for missing product" do
      conn = call(:post, "/api/products/nonexistent/code-review")
      assert conn.status == 404
    end
  end
end

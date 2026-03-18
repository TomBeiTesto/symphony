defmodule SymphonyElixir.LocalBoardTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.LocalBoard

  @store_path "test_board_#{System.unique_integer([:positive])}.json"

  setup context do
    unless context[:skip_setup] do
      start_supervised!({LocalBoard, store_path: @store_path, project_prefix: "TEST"})
    end

    on_exit(fn -> File.rm(@store_path) end)
    :ok
  end

  describe "list_issues/0" do
    test "returns empty list when no issues" do
      assert LocalBoard.list_issues() == []
    end

    test "returns created issues" do
      {:ok, _} = LocalBoard.create_issue(%{"title" => "First"})
      {:ok, _} = LocalBoard.create_issue(%{"title" => "Second"})

      issues = LocalBoard.list_issues()
      assert length(issues) == 2
      titles = Enum.map(issues, & &1.title)
      assert "First" in titles
      assert "Second" in titles
    end
  end

  describe "create_issue/1" do
    test "creates an issue with defaults" do
      {:ok, issue} = LocalBoard.create_issue(%{"title" => "My Issue"})

      assert issue.title == "My Issue"
      assert issue.identifier =~ ~r/^TEST-\d+$/
      assert issue.id != nil
      assert issue.state == "Backlog"
      assert issue.priority == 0
      assert issue.labels == []
      assert issue.created_at != nil
      assert issue.updated_at != nil
    end

    test "creates an issue with explicit state and priority" do
      {:ok, issue} =
        LocalBoard.create_issue(%{
          "title" => "Urgent task",
          "state" => "Todo",
          "priority" => 1,
          "labels" => "bug, critical"
        })

      assert issue.state == "Todo"
      assert issue.priority == 1
      assert issue.labels == ["bug", "critical"]
    end

    test "increments identifier numbers" do
      {:ok, i1} = LocalBoard.create_issue(%{"title" => "A"})
      {:ok, i2} = LocalBoard.create_issue(%{"title" => "B"})

      [_, num1] = String.split(i1.identifier, "-")
      [_, num2] = String.split(i2.identifier, "-")

      assert String.to_integer(num2) == String.to_integer(num1) + 1
    end
  end

  describe "get_issue/1" do
    test "returns issue by id" do
      {:ok, created} = LocalBoard.create_issue(%{"title" => "Find me"})
      assert {:ok, found} = LocalBoard.get_issue(created.id)
      assert found.title == "Find me"
    end

    test "returns not_found for missing id" do
      assert {:error, :not_found} = LocalBoard.get_issue("nonexistent")
    end
  end

  describe "update_issue/2" do
    test "updates title and description" do
      {:ok, issue} = LocalBoard.create_issue(%{"title" => "Original"})

      {:ok, updated} =
        LocalBoard.update_issue(issue.id, %{
          "title" => "Updated",
          "description" => "Now with desc"
        })

      assert updated.title == "Updated"
      assert updated.description == "Now with desc"
    end

    test "returns not_found for missing id" do
      assert {:error, :not_found} = LocalBoard.update_issue("bogus", %{"title" => "x"})
    end

    test "updates rerun_hint, plan_status, and plan_text" do
      {:ok, issue} = LocalBoard.create_issue(%{"title" => "Rerun test"})

      {:ok, updated} =
        LocalBoard.update_issue(issue.id, %{
          "rerun_hint" => "Be more thorough",
          "plan_status" => "approved",
          "plan_text" => "Step 1: Analyze. Step 2: Write."
        })

      assert updated.rerun_hint == "Be more thorough"
      assert updated.plan_status == "approved"
      assert updated.plan_text == "Step 1: Analyze. Step 2: Write."
    end

    test "updates product_id and project_id" do
      {:ok, issue} = LocalBoard.create_issue(%{"title" => "Product test"})

      {:ok, updated} =
        LocalBoard.update_issue(issue.id, %{
          "product_id" => "prod-123",
          "project_id" => "proj-456"
        })

      assert updated.product_id == "prod-123"
      assert updated.project_id == "proj-456"
    end

    test "clears rerun_hint with nil" do
      {:ok, issue} = LocalBoard.create_issue(%{"title" => "Clear hint"})
      {:ok, _} = LocalBoard.update_issue(issue.id, %{"rerun_hint" => "some hint"})
      {:ok, updated} = LocalBoard.update_issue(issue.id, %{"rerun_hint" => nil})
      assert updated.rerun_hint == nil
    end
  end

  describe "move_issue/2" do
    test "changes issue state" do
      {:ok, issue} = LocalBoard.create_issue(%{"title" => "Movable", "state" => "Todo"})

      {:ok, moved} = LocalBoard.move_issue(issue.id, "In Progress")
      assert moved.state == "In Progress"

      # Verify persistence
      {:ok, refetched} = LocalBoard.get_issue(issue.id)
      assert refetched.state == "In Progress"
    end

    test "returns not_found for missing id" do
      assert {:error, :not_found} = LocalBoard.move_issue("bogus", "Done")
    end
  end

  describe "delete_issue/1" do
    test "removes an issue" do
      {:ok, issue} = LocalBoard.create_issue(%{"title" => "Delete me"})
      assert :ok = LocalBoard.delete_issue(issue.id)
      assert {:error, :not_found} = LocalBoard.get_issue(issue.id)
    end

    test "returns not_found for missing id" do
      assert {:error, :not_found} = LocalBoard.delete_issue("bogus")
    end
  end

  describe "list_issues_by_states/1" do
    test "filters by state names (case-insensitive)" do
      {:ok, _} = LocalBoard.create_issue(%{"title" => "A", "state" => "Todo"})
      {:ok, _} = LocalBoard.create_issue(%{"title" => "B", "state" => "In Progress"})
      {:ok, _} = LocalBoard.create_issue(%{"title" => "C", "state" => "Done"})

      results = LocalBoard.list_issues_by_states(["todo", "in progress"])
      assert length(results) == 2
      states = Enum.map(results, & &1.state) |> MapSet.new()
      assert MapSet.member?(states, "Todo")
      assert MapSet.member?(states, "In Progress")
    end
  end

  describe "get_issues_by_ids/1" do
    test "returns matching issues" do
      {:ok, i1} = LocalBoard.create_issue(%{"title" => "First"})
      {:ok, _i2} = LocalBoard.create_issue(%{"title" => "Second"})
      {:ok, i3} = LocalBoard.create_issue(%{"title" => "Third"})

      results = LocalBoard.get_issues_by_ids([i1.id, i3.id])
      assert length(results) == 2
      ids = Enum.map(results, & &1.id) |> MapSet.new()
      assert MapSet.member?(ids, i1.id)
      assert MapSet.member?(ids, i3.id)
    end
  end

  describe "list_states/0" do
    test "returns the configured states" do
      states = LocalBoard.list_states()
      assert is_list(states)
      assert "Backlog" in states
      assert "Review" in states
      assert "Done" in states
      assert "Archived" in states
      assert "Cancelled" in states
    end
  end

  describe "get_board_snapshot/0" do
    test "returns columns with issues grouped by state" do
      {:ok, _} = LocalBoard.create_issue(%{"title" => "A", "state" => "Todo"})
      {:ok, _} = LocalBoard.create_issue(%{"title" => "B", "state" => "Todo"})
      {:ok, _} = LocalBoard.create_issue(%{"title" => "C", "state" => "Done"})

      snapshot = LocalBoard.get_board_snapshot()
      assert is_list(snapshot.columns)
      assert is_list(snapshot.states)
      assert snapshot.total_issues == 3

      todo_col = Enum.find(snapshot.columns, &(&1.state == "Todo"))
      assert length(todo_col.issues) == 2

      done_col = Enum.find(snapshot.columns, &(&1.state == "Done"))
      assert length(done_col.issues) == 1
    end
  end

  describe "to_issue_struct/1" do
    test "converts record to Issue struct" do
      {:ok, record} =
        LocalBoard.create_issue(%{
          "title" => "Test Issue",
          "description" => "Desc",
          "state" => "Todo",
          "priority" => 2,
          "labels" => ["bug"]
        })

      issue = LocalBoard.to_issue_struct(record)

      assert %SymphonyElixir.Issue{} = issue
      assert issue.id == record.id
      assert issue.identifier == record.identifier
      assert issue.title == "Test Issue"
      assert issue.description == "Desc"
      assert issue.state == "Todo"
      assert issue.priority == 2
      assert issue.labels == ["bug"]
      assert issue.blocked_by == []
    end

    test "includes rerun_hint, plan_status, plan_text, product_id, project_id" do
      {:ok, record} =
        LocalBoard.create_issue(%{
          "title" => "Full Fields",
          "state" => "In Progress"
        })

      {:ok, record} =
        LocalBoard.update_issue(record.id, %{
          "rerun_hint" => "improve output",
          "plan_status" => "approved",
          "plan_text" => "Do X then Y",
          "product_id" => "prod-1",
          "project_id" => "proj-2"
        })

      issue = LocalBoard.to_issue_struct(record)

      assert %SymphonyElixir.Issue{} = issue
      assert issue.rerun_hint == "improve output"
      assert issue.plan_status == "approved"
      assert issue.plan_text == "Do X then Y"
      assert issue.product_id == "prod-1"
      assert issue.project_id == "proj-2"
    end
  end

  describe "persistence" do
    @tag :skip_setup
    test "data survives restart" do
      store = "test_persist_#{System.unique_integer([:positive])}.json"
      on_exit(fn -> File.rm(store) end)

      # Start manually (not via start_supervised — we manage lifecycle)
      {:ok, pid} = LocalBoard.start_link(store_path: store, project_prefix: "PER")

      {:ok, issue} = LocalBoard.create_issue(%{"title" => "Persistent"})
      identifier = issue.identifier

      GenServer.stop(pid)
      Process.sleep(50)

      {:ok, pid2} = LocalBoard.start_link(store_path: store, project_prefix: "PER")

      issues = LocalBoard.list_issues()
      assert length(issues) == 1
      assert hd(issues).identifier == identifier

      GenServer.stop(pid2)
    end
  end

  # --- Project Tests ---

  describe "list_projects/0" do
    test "returns empty list when no projects" do
      assert LocalBoard.list_projects() == []
    end
  end

  describe "create_project/1" do
    test "creates a project with name and slug" do
      {:ok, project} = LocalBoard.create_project(%{"name" => "My App"})

      assert project.name == "My App"
      assert project.slug == "my-app"
      assert project.id != nil
      assert project.created_at != nil
    end

    test "creates a project with explicit fields" do
      {:ok, project} =
        LocalBoard.create_project(%{
          "name" => "Backend",
          "slug" => "backend-api",
          "path" => "/tmp/backend",
          "repo_url" => "https://github.com/example/backend.git",
          "description" => "API server"
        })

      assert project.slug == "backend-api"
      assert project.path == "/tmp/backend"
      assert project.repo_url == "https://github.com/example/backend.git"
      assert project.description == "API server"
    end
  end

  describe "get_project/1" do
    test "returns project by id" do
      {:ok, created} = LocalBoard.create_project(%{"name" => "Find Me"})
      assert {:ok, found} = LocalBoard.get_project(created.id)
      assert found.name == "Find Me"
    end

    test "returns not_found for missing id" do
      assert {:error, :not_found} = LocalBoard.get_project("nonexistent")
    end
  end

  describe "update_project/2" do
    test "updates project fields" do
      {:ok, project} = LocalBoard.create_project(%{"name" => "Old Name"})

      {:ok, updated} =
        LocalBoard.update_project(project.id, %{
          "name" => "New Name",
          "description" => "Updated desc"
        })

      assert updated.name == "New Name"
      assert updated.description == "Updated desc"
    end

    test "returns not_found for missing id" do
      assert {:error, :not_found} = LocalBoard.update_project("bogus", %{"name" => "x"})
    end
  end

  describe "delete_project/1" do
    test "removes a project" do
      {:ok, project} = LocalBoard.create_project(%{"name" => "Delete Me"})
      assert :ok = LocalBoard.delete_project(project.id)
      assert {:error, :not_found} = LocalBoard.get_project(project.id)
    end

    test "cascade deletes project issues" do
      {:ok, project} = LocalBoard.create_project(%{"name" => "Cascade"})

      {:ok, _} =
        LocalBoard.create_issue(%{"title" => "Linked A", "project_id" => project.id})

      {:ok, _} =
        LocalBoard.create_issue(%{"title" => "Linked B", "project_id" => project.id})

      {:ok, _} = LocalBoard.create_issue(%{"title" => "Unlinked"})

      assert :ok = LocalBoard.delete_project(project.id)

      # Project issues removed, unlinked issue remains
      issues = LocalBoard.list_issues()
      assert length(issues) == 1
      assert hd(issues).title == "Unlinked"
    end

    test "returns not_found for missing id" do
      assert {:error, :not_found} = LocalBoard.delete_project("bogus")
    end
  end

  describe "clone_project_repo/1" do
    test "returns error when project has no repo_url" do
      {:ok, project} = LocalBoard.create_project(%{"name" => "No Repo"})
      assert {:error, :no_repo_url} = LocalBoard.clone_project_repo(project.id)
    end

    test "returns not_found for missing project" do
      assert {:error, :not_found} = LocalBoard.clone_project_repo("bogus")
    end
  end

  describe "issue with project_id" do
    test "creates an issue linked to a project" do
      {:ok, project} = LocalBoard.create_project(%{"name" => "My Project"})

      {:ok, issue} =
        LocalBoard.create_issue(%{"title" => "Linked Issue", "project_id" => project.id})

      assert issue.project_id == project.id
    end

    test "creates an issue without project_id" do
      {:ok, issue} = LocalBoard.create_issue(%{"title" => "Unlinked"})
      assert issue.project_id == nil
    end
  end

  describe "board snapshot includes projects" do
    test "snapshot contains projects list" do
      {:ok, _} = LocalBoard.create_project(%{"name" => "Test Project"})
      snapshot = LocalBoard.get_board_snapshot()
      assert is_list(snapshot.projects)
      assert length(snapshot.projects) == 1
      assert hd(snapshot.projects).name == "Test Project"
    end
  end

  # --- Project Persistence ---

  describe "project persistence" do
    @tag :skip_setup
    test "projects survive restart" do
      store = "test_proj_persist_#{System.unique_integer([:positive])}.json"
      on_exit(fn -> File.rm(store) end)

      {:ok, pid} = LocalBoard.start_link(store_path: store, project_prefix: "PP")
      {:ok, proj} = LocalBoard.create_project(%{"name" => "Persisted"})
      proj_id = proj.id
      GenServer.stop(pid)
      Process.sleep(50)

      {:ok, pid2} = LocalBoard.start_link(store_path: store, project_prefix: "PP")
      projects = LocalBoard.list_projects()
      assert length(projects) == 1
      assert hd(projects).id == proj_id
      assert hd(projects).name == "Persisted"
      GenServer.stop(pid2)
    end
  end

  # --- Product Tests ---

  describe "list_products/0" do
    test "returns empty list when no products" do
      assert LocalBoard.list_products() == []
    end
  end

  describe "create_product/1" do
    test "creates a product with defaults" do
      {:ok, product} = LocalBoard.create_product(%{"name" => "B2C Async API"})

      assert product.name == "B2C Async API"
      assert product.id != nil
      assert product.project_ids == []
      assert product.features == []
      assert product.created_at != nil
      assert product.updated_at != nil
    end

    test "creates a product with project_ids" do
      {:ok, p1} = LocalBoard.create_project(%{"name" => "Data API"})
      {:ok, p2} = LocalBoard.create_project(%{"name" => "Frontend"})

      {:ok, product} =
        LocalBoard.create_product(%{
          "name" => "B2C Product",
          "description" => "Customer-facing async API",
          "project_ids" => [p1.id, p2.id]
        })

      assert product.project_ids == [p1.id, p2.id]
      assert product.description == "Customer-facing async API"
    end
  end

  describe "get_product/1" do
    test "returns product by id" do
      {:ok, created} = LocalBoard.create_product(%{"name" => "Find Me"})
      assert {:ok, found} = LocalBoard.get_product(created.id)
      assert found.name == "Find Me"
    end

    test "returns not_found for missing id" do
      assert {:error, :not_found} = LocalBoard.get_product("nonexistent")
    end
  end

  describe "update_product/2" do
    test "updates product fields" do
      {:ok, product} = LocalBoard.create_product(%{"name" => "Old"})

      {:ok, updated} =
        LocalBoard.update_product(product.id, %{
          "name" => "New",
          "description" => "Updated"
        })

      assert updated.name == "New"
      assert updated.description == "Updated"
    end

    test "updates project_ids" do
      {:ok, p1} = LocalBoard.create_project(%{"name" => "Proj A"})
      {:ok, product} = LocalBoard.create_product(%{"name" => "Test"})

      {:ok, updated} =
        LocalBoard.update_product(product.id, %{"project_ids" => [p1.id]})

      assert updated.project_ids == [p1.id]
    end

    test "returns not_found for missing id" do
      assert {:error, :not_found} = LocalBoard.update_product("bogus", %{"name" => "x"})
    end
  end

  describe "delete_product/1" do
    test "removes a product" do
      {:ok, product} = LocalBoard.create_product(%{"name" => "Delete Me"})
      assert :ok = LocalBoard.delete_product(product.id)
      assert {:error, :not_found} = LocalBoard.get_product(product.id)
    end

    test "returns not_found for missing id" do
      assert {:error, :not_found} = LocalBoard.delete_product("bogus")
    end
  end

  describe "add_product_feature/2" do
    test "adds a feature with statuses initialized to missing" do
      {:ok, p1} = LocalBoard.create_project(%{"name" => "API"})
      {:ok, p2} = LocalBoard.create_project(%{"name" => "Docs"})

      {:ok, product} =
        LocalBoard.create_product(%{
          "name" => "Test Product",
          "project_ids" => [p1.id, p2.id]
        })

      {:ok, updated} =
        LocalBoard.add_product_feature(product.id, %{"name" => "Auth"})

      assert length(updated.features) == 1
      feature = hd(updated.features)
      assert feature.name == "Auth"
      assert feature.statuses[p1.id] == "missing"
      assert feature.statuses[p2.id] == "missing"
    end

    test "returns not_found for missing product" do
      assert {:error, :not_found} =
               LocalBoard.add_product_feature("bogus", %{"name" => "X"})
    end
  end

  describe "set_feature_status/4" do
    test "updates a feature status for a project" do
      {:ok, proj} = LocalBoard.create_project(%{"name" => "API"})

      {:ok, product} =
        LocalBoard.create_product(%{
          "name" => "Test",
          "project_ids" => [proj.id]
        })

      {:ok, product} =
        LocalBoard.add_product_feature(product.id, %{"name" => "Feature A"})

      feature = hd(product.features)

      {:ok, updated} =
        LocalBoard.set_feature_status(product.id, feature.id, proj.id, "done")

      updated_feature = hd(updated.features)
      assert updated_feature.statuses[proj.id] == "done"
    end
  end

  describe "delete_product_feature/2" do
    test "removes a feature from a product" do
      {:ok, product} = LocalBoard.create_product(%{"name" => "Test"})

      {:ok, product} =
        LocalBoard.add_product_feature(product.id, %{"name" => "Remove Me"})

      feature = hd(product.features)
      {:ok, updated} = LocalBoard.delete_product_feature(product.id, feature.id)
      assert updated.features == []
    end
  end

  describe "issue with product_id" do
    test "creates an issue linked to a product" do
      {:ok, product} = LocalBoard.create_product(%{"name" => "My Product"})

      {:ok, issue} =
        LocalBoard.create_issue(%{"title" => "Product Task", "product_id" => product.id})

      assert issue.product_id == product.id
    end

    test "creates an issue without product_id" do
      {:ok, issue} = LocalBoard.create_issue(%{"title" => "No Product"})
      assert issue.product_id == nil
    end
  end

  # --- Product Persistence ---

  describe "product persistence" do
    @tag :skip_setup
    test "products and features survive restart" do
      store = "test_product_persist_#{System.unique_integer([:positive])}.json"
      on_exit(fn -> File.rm(store) end)

      {:ok, pid} = LocalBoard.start_link(store_path: store, project_prefix: "PP")
      {:ok, proj} = LocalBoard.create_project(%{"name" => "API"})

      {:ok, product} =
        LocalBoard.create_product(%{
          "name" => "Persisted Product",
          "project_ids" => [proj.id]
        })

      {:ok, _} =
        LocalBoard.add_product_feature(product.id, %{"name" => "Auth Feature"})

      product_id = product.id
      GenServer.stop(pid)
      Process.sleep(50)

      {:ok, pid2} = LocalBoard.start_link(store_path: store, project_prefix: "PP")
      products = LocalBoard.list_products()
      assert length(products) == 1
      assert hd(products).id == product_id
      assert hd(products).name == "Persisted Product"
      assert length(hd(products).features) == 1
      assert hd(hd(products).features).name == "Auth Feature"
      GenServer.stop(pid2)
    end
  end
end

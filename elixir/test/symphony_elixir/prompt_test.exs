defmodule SymphonyElixir.PromptTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.{Issue, Prompt}

  @issue %Issue{
    id: "abc123",
    identifier: "MT-649",
    title: "Fix login bug",
    state: "In Progress",
    description: "The login form has a bug.",
    labels: ["bug", "urgent"],
    blocked_by: [],
    propose_followups: false
  }

  describe "render/3" do
    test "renders a simple template with issue variables" do
      template = "Work on {{ issue.identifier }}: {{ issue.title }}"
      assert {:ok, rendered} = Prompt.render(template, @issue)
      assert rendered == "Work on MT-649: Fix login bug"
    end

    test "renders with attempt variable" do
      template =
        "{% if attempt %}Retry attempt {{ attempt }}.{% endif %} Work on {{ issue.identifier }}."

      assert {:ok, rendered} = Prompt.render(template, @issue, 3)
      assert String.contains?(rendered, "Retry attempt 3")
      assert String.contains?(rendered, "MT-649")
    end

    test "renders without attempt when nil" do
      template = "{% if attempt %}Retry.{% endif %}Work on {{ issue.identifier }}."
      assert {:ok, rendered} = Prompt.render(template, @issue, nil)
      assert rendered == "Work on MT-649."
    end

    test "uses default prompt for empty template" do
      issue = %{@issue | propose_followups: true}
      assert {:ok, rendered} = Prompt.render("", issue)
      assert String.starts_with?(rendered, "You are working on an issue from the project board.")
      # propose_followups is true, so follow-up instructions are appended
      assert String.contains?(rendered, "Follow-up Proposals")
    end

    test "does not append follow-up instructions when propose_followups is false" do
      issue = %{@issue | propose_followups: false}
      assert {:ok, rendered} = Prompt.render("", issue)
      assert rendered == "You are working on an issue from the project board."
    end

    test "renders issue labels" do
      template = "Labels: {% for label in issue.labels %}{{ label }} {% endfor %}"
      assert {:ok, rendered} = Prompt.render(template, @issue)
      assert String.contains?(rendered, "bug")
      assert String.contains?(rendered, "urgent")
    end

    test "renders issue description" do
      template = "Description: {{ issue.description }}"
      assert {:ok, rendered} = Prompt.render(template, @issue)
      assert String.contains?(rendered, "The login form has a bug.")
    end

    test "returns error for invalid template syntax" do
      template = "{% invalid_tag %}"
      assert {:error, _} = Prompt.render(template, @issue)
    end
  end
end

defmodule SymphonyElixir.PromptContextTest do
  @moduledoc "Tests for Prompt.render/3 with project, product, blocker, skill, and plan contexts."
  use ExUnit.Case, async: false

  alias SymphonyElixir.{Issue, LocalBoard, Prompt}

  setup do
    board_store = "test_prompt_board_#{System.unique_integer([:positive])}.json"

    start_supervised!({LocalBoard, store_path: board_store, project_prefix: "PT"})

    on_exit(fn -> File.rm(board_store) end)

    :ok
  end

  @template """
  Work on {{ issue.identifier }}: {{ issue.title }}.
  {% if project %}Project: {{ project.name }}.{% endif %}
  {% if product %}Product: {{ product.name }}. {{ product.description }}{% endif %}
  {% if blocked_by %}Blockers: {% for b in blocked_by %}{{ b.identifier }}({{ b.state }}) {% endfor %}{% endif %}
  {% if skills %}Skills: {{ skills }}{% endif %}
  {% if planning_phase %}PLANNING PHASE: Create a plan.{% endif %}
  {% if execution_phase %}EXECUTION PHASE with plan: {{ plan }}{% endif %}
  """

  describe "render/3 with project context" do
    test "renders project name when issue has project_id" do
      {:ok, project} = LocalBoard.create_project(%{"name" => "Backend API", "path" => "/tmp/be"})

      issue = %Issue{
        id: "p1",
        identifier: "PT-1",
        title: "Add endpoint",
        state: "Todo",
        project_id: project.id,
        blocked_by: [],
        propose_followups: false
      }

      assert {:ok, rendered} = Prompt.render(@template, issue)
      assert String.contains?(rendered, "Project: Backend API.")
    end
  end

  describe "render/3 with product context" do
    test "renders product details when issue has product_id" do
      {:ok, product} =
        LocalBoard.create_product(%{
          "name" => "Customer Portal",
          "description" => "B2C portal for customers"
        })

      issue = %Issue{
        id: "pd1",
        identifier: "PT-2",
        title: "Implement auth",
        state: "Todo",
        product_id: product.id,
        blocked_by: [],
        propose_followups: false
      }

      assert {:ok, rendered} = Prompt.render(@template, issue)
      assert String.contains?(rendered, "Product: Customer Portal.")
      assert String.contains?(rendered, "B2C portal for customers")
    end
  end

  describe "render/3 with blockers" do
    test "renders blocker identifiers and states" do
      issue = %Issue{
        id: "b1",
        identifier: "PT-3",
        title: "Blocked task",
        state: "Todo",
        blocked_by: [
          %{id: "dep1", identifier: "PT-10", state: "In Progress"},
          %{id: "dep2", identifier: "PT-11", state: "Done"}
        ],
        propose_followups: false
      }

      assert {:ok, rendered} = Prompt.render(@template, issue)
      assert String.contains?(rendered, "Blockers:")
      assert String.contains?(rendered, "PT-10(In Progress)")
      assert String.contains?(rendered, "PT-11(Done)")
    end
  end

  describe "render/3 with skills" do
    test "renders skill content when issue has skill_ids" do
      {:ok, skill} =
        LocalBoard.create_skill(%{
          "name" => "Elixir Testing",
          "content" => "Always use ExUnit. Prefer async: true.",
          "category" => "testing",
          "tags" => ["elixir", "testing"]
        })

      issue = %Issue{
        id: "s1",
        identifier: "PT-4",
        title: "Write tests",
        state: "Todo",
        skill_ids: [skill.id],
        blocked_by: [],
        propose_followups: false
      }

      assert {:ok, rendered} = Prompt.render(@template, issue)
      assert String.contains?(rendered, "Skills:")
      assert String.contains?(rendered, "Elixir Testing")
      assert String.contains?(rendered, "Always use ExUnit")
    end
  end

  describe "render/3 in planning phase" do
    test "sets planning_phase flag when plan_status is planning" do
      issue = %Issue{
        id: "plan1",
        identifier: "PT-5",
        title: "Plan this feature",
        state: "Todo",
        plan_status: "planning",
        blocked_by: [],
        propose_followups: false
      }

      assert {:ok, rendered} = Prompt.render(@template, issue)
      assert String.contains?(rendered, "PLANNING PHASE: Create a plan.")
      refute String.contains?(rendered, "EXECUTION PHASE")
    end
  end

  describe "render/3 in execution phase" do
    test "injects plan text when plan_status is approved" do
      issue = %Issue{
        id: "exec1",
        identifier: "PT-6",
        title: "Execute this feature",
        state: "In Progress",
        plan_status: "approved",
        plan_text: "Step 1: Refactor. Step 2: Test.",
        blocked_by: [],
        propose_followups: false
      }

      assert {:ok, rendered} = Prompt.render(@template, issue)
      assert String.contains?(rendered, "EXECUTION PHASE with plan:")
      assert String.contains?(rendered, "Step 1: Refactor. Step 2: Test.")
      refute String.contains?(rendered, "PLANNING PHASE")
    end
  end

  describe "render/3 with missing project graceful handling" do
    test "renders without project section when project_id does not exist" do
      issue = %Issue{
        id: "mp1",
        identifier: "PT-7",
        title: "Orphan task",
        state: "Todo",
        project_id: "nonexistent_project_id",
        blocked_by: [],
        propose_followups: false
      }

      assert {:ok, rendered} = Prompt.render(@template, issue)
      refute String.contains?(rendered, "Project:")
      # Template still renders the issue fields
      assert String.contains?(rendered, "PT-7")
      assert String.contains?(rendered, "Orphan task")
    end
  end

  describe "render/3 with missing product graceful handling" do
    test "renders without product section when product_id does not exist" do
      issue = %Issue{
        id: "mp2",
        identifier: "PT-8",
        title: "No product task",
        state: "Todo",
        product_id: "nonexistent_product_id",
        blocked_by: [],
        propose_followups: false
      }

      assert {:ok, rendered} = Prompt.render(@template, issue)
      refute String.contains?(rendered, "Product:")
      assert String.contains?(rendered, "PT-8")
      assert String.contains?(rendered, "No product task")
    end
  end
end

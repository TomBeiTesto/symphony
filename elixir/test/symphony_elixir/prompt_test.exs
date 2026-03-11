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

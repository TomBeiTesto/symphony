defmodule SymphonyElixir.IssueTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Issue

  @valid_attrs %{
    id: "abc123",
    identifier: "MT-649",
    title: "Implement feature X",
    state: "In Progress",
    blocked_by: []
  }

  describe "struct creation" do
    test "creates issue with required fields" do
      issue = struct!(Issue, @valid_attrs)
      assert issue.id == "abc123"
      assert issue.identifier == "MT-649"
      assert issue.title == "Implement feature X"
      assert issue.state == "In Progress"
      assert issue.labels == []
      assert issue.blocked_by == []
    end

    test "raises on missing required fields" do
      assert_raise ArgumentError, fn ->
        struct!(Issue, %{id: "123"})
      end
    end
  end

  describe "workspace_key/1" do
    test "preserves valid characters" do
      issue = struct!(Issue, @valid_attrs)
      assert Issue.workspace_key(issue) == "MT-649"
    end

    test "replaces special characters with underscore" do
      issue = struct!(Issue, %{@valid_attrs | identifier: "MT/649 foo@bar"})
      assert Issue.workspace_key(issue) == "MT_649_foo_bar"
    end

    test "handles complex identifiers" do
      issue = struct!(Issue, %{@valid_attrs | identifier: "ORG~123.4_5"})
      assert Issue.workspace_key(issue) == "ORG_123.4_5"
    end
  end

  describe "sanitize_identifier/1" do
    test "only allows alphanumeric, dot, dash, underscore" do
      assert Issue.sanitize_identifier("ABC-123") == "ABC-123"
      assert Issue.sanitize_identifier("abc.123_test") == "abc.123_test"
      assert Issue.sanitize_identifier("a/b\\c:d") == "a_b_c_d"
      assert Issue.sanitize_identifier("") == ""
    end
  end

  describe "valid_for_dispatch?/1" do
    test "returns true when all required fields present" do
      issue = struct!(Issue, @valid_attrs)
      assert Issue.valid_for_dispatch?(issue) == true
    end

    test "returns false when id is empty" do
      issue = struct!(Issue, %{@valid_attrs | id: ""})
      assert Issue.valid_for_dispatch?(issue) == false
    end

    test "returns false when identifier is empty" do
      issue = struct!(Issue, %{@valid_attrs | identifier: ""})
      assert Issue.valid_for_dispatch?(issue) == false
    end

    test "returns false when title is empty" do
      issue = struct!(Issue, %{@valid_attrs | title: ""})
      assert Issue.valid_for_dispatch?(issue) == false
    end

    test "returns false when state is empty" do
      issue = struct!(Issue, %{@valid_attrs | state: ""})
      assert Issue.valid_for_dispatch?(issue) == false
    end
  end

  describe "normalize_state/1" do
    test "lowercases and trims" do
      assert Issue.normalize_state("In Progress") == "in progress"
      assert Issue.normalize_state("  Todo  ") == "todo"
      assert Issue.normalize_state("DONE") == "done"
    end
  end

  describe "has_non_terminal_blockers?/2" do
    test "returns false when no blockers" do
      issue = struct!(Issue, @valid_attrs)
      terminal = MapSet.new(["done", "closed"])
      assert Issue.has_non_terminal_blockers?(issue, terminal) == false
    end

    test "returns false when all blockers are terminal" do
      issue =
        struct!(Issue, %{
          @valid_attrs
          | blocked_by: [%{id: "1", identifier: "X-1", state: "Done"}]
        })

      terminal = MapSet.new(["done", "closed"])
      assert Issue.has_non_terminal_blockers?(issue, terminal) == false
    end

    test "returns true when a blocker is non-terminal" do
      issue =
        struct!(Issue, %{
          @valid_attrs
          | blocked_by: [%{id: "1", identifier: "X-1", state: "In Progress"}]
        })

      terminal = MapSet.new(["done", "closed"])
      assert Issue.has_non_terminal_blockers?(issue, terminal) == true
    end

    test "returns true when a blocker has nil state" do
      issue =
        struct!(Issue, %{@valid_attrs | blocked_by: [%{id: "1", identifier: "X-1", state: nil}]})

      terminal = MapSet.new(["done", "closed"])
      assert Issue.has_non_terminal_blockers?(issue, terminal) == true
    end
  end

  describe "to_template_map/1" do
    test "converts issue to string-keyed map" do
      issue = struct!(Issue, @valid_attrs)
      map = Issue.to_template_map(issue)
      assert map["id"] == "abc123"
      assert map["identifier"] == "MT-649"
      assert map["title"] == "Implement feature X"
      assert map["state"] == "In Progress"
      assert is_list(map["labels"])
      assert is_list(map["blocked_by"])
    end
  end
end

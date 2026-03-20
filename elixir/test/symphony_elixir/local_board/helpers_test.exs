defmodule SymphonyElixir.LocalBoard.HelpersTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.LocalBoard.Helpers

  describe "generate_id/0" do
    test "returns a 16-char URL-safe base64 string" do
      id = Helpers.generate_id()
      assert is_binary(id)
      assert String.length(id) == 16
    end

    test "generates unique ids" do
      ids = for _ <- 1..100, do: Helpers.generate_id()
      assert length(Enum.uniq(ids)) == 100
    end
  end

  describe "parse_priority/1" do
    test "passes through integers" do
      assert Helpers.parse_priority(3) == 3
      assert Helpers.parse_priority(0) == 0
    end

    test "parses string integers" do
      assert Helpers.parse_priority("2") == 2
    end

    test "returns 0 for non-parseable strings" do
      assert Helpers.parse_priority("high") == 0
    end

    test "returns 0 for nil and other types" do
      assert Helpers.parse_priority(nil) == 0
      assert Helpers.parse_priority(:atom) == 0
    end
  end

  describe "parse_labels/1" do
    test "passes through list" do
      assert Helpers.parse_labels(["a", "b"]) == ["a", "b"]
    end

    test "converts list elements to strings" do
      assert Helpers.parse_labels([1, :atom]) == ["1", "atom"]
    end

    test "splits comma-separated string" do
      assert Helpers.parse_labels("bug, frontend, urgent") == ["bug", "frontend", "urgent"]
    end

    test "returns empty list for other types" do
      assert Helpers.parse_labels(nil) == []
      assert Helpers.parse_labels(42) == []
    end
  end

  describe "parse_boolean/1" do
    test "true values" do
      assert Helpers.parse_boolean(true) == true
      assert Helpers.parse_boolean("true") == true
    end

    test "false values" do
      assert Helpers.parse_boolean(false) == false
      assert Helpers.parse_boolean("false") == false
      assert Helpers.parse_boolean(nil) == false
      assert Helpers.parse_boolean(0) == false
    end
  end

  describe "sort_issues/1" do
    test "sorts by priority descending then created_at ascending" do
      issues = [
        %{priority: 1, created_at: "2024-01-02"},
        %{priority: 3, created_at: "2024-01-01"},
        %{priority: 1, created_at: "2024-01-01"}
      ]

      sorted = Helpers.sort_issues(issues)
      assert [%{priority: 3}, %{priority: 1, created_at: "2024-01-01"}, %{priority: 1, created_at: "2024-01-02"}] = sorted
    end

    test "handles nil priority and created_at" do
      issues = [%{priority: nil, created_at: nil}, %{priority: 1, created_at: "2024-01-01"}]
      sorted = Helpers.sort_issues(issues)
      assert [%{priority: 1}, %{priority: nil}] = sorted
    end
  end

  describe "maybe_put/3" do
    test "puts value when not nil" do
      assert Helpers.maybe_put(%{}, "key", "value") == %{"key" => "value"}
    end

    test "skips nil values" do
      assert Helpers.maybe_put(%{"a" => 1}, "b", nil) == %{"a" => 1}
    end
  end

  describe "maybe_update/3" do
    test "updates key when present in attrs as string" do
      record = %{name: "old"}
      assert %{name: "new"} = Helpers.maybe_update(record, :name, %{"name" => "new"})
    end

    test "does not update when key absent from attrs" do
      record = %{name: "old"}
      assert %{name: "old"} = Helpers.maybe_update(record, :name, %{"other" => "x"})
    end
  end

  describe "maybe_update/4 with transform" do
    test "applies transform function to value" do
      record = %{count: 0}
      assert %{count: 10} = Helpers.maybe_update(record, :count, %{"count" => "10"}, &String.to_integer/1)
    end
  end

  describe "slugify/1" do
    test "lowercases and replaces non-alphanumeric" do
      assert Helpers.slugify("My Cool Project!") == "my-cool-project"
    end

    test "trims leading and trailing hyphens" do
      assert Helpers.slugify("--hello--") == "hello"
    end

    test "truncates to 32 chars" do
      long_name = String.duplicate("a", 50)
      assert String.length(Helpers.slugify(long_name)) == 32
    end

    test "returns 'project' for non-string input" do
      assert Helpers.slugify(nil) == "project"
      assert Helpers.slugify(123) == "project"
    end
  end
end

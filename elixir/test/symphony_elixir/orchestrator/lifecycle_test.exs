defmodule SymphonyElixir.Orchestrator.LifecycleTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Orchestrator.Lifecycle

  describe "token_exhaustion_error?/1" do
    test "detects rate limit" do
      assert Lifecycle.token_exhaustion_error?("Rate limit exceeded")
      assert Lifecycle.token_exhaustion_error?(:rate_limit)
      assert Lifecycle.token_exhaustion_error?({:error, "rate_limit hit"})
    end

    test "detects quota errors" do
      assert Lifecycle.token_exhaustion_error?("quota exceeded")
      assert Lifecycle.token_exhaustion_error?("429 Too Many Requests")
      assert Lifecycle.token_exhaustion_error?("resource_exhausted")
      assert Lifecycle.token_exhaustion_error?("tokens_exceeded")
      assert Lifecycle.token_exhaustion_error?("billing limit reached")
      assert Lifecycle.token_exhaustion_error?("usage limit")
      assert Lifecycle.token_exhaustion_error?("plan limit")
      assert Lifecycle.token_exhaustion_error?("budget exceeded")
    end

    test "returns false for normal errors" do
      refute Lifecycle.token_exhaustion_error?("turn_failed")
      refute Lifecycle.token_exhaustion_error?(:timeout)
      refute Lifecycle.token_exhaustion_error?({:error, :network_error})
      refute Lifecycle.token_exhaustion_error?(nil)
    end

    test "is case-insensitive" do
      assert Lifecycle.token_exhaustion_error?("RATE LIMIT EXCEEDED")
      assert Lifecycle.token_exhaustion_error?("Quota Exceeded")
    end
  end

  describe "extract_follow_ups/1" do
    test "parses valid follow-ups block" do
      result_text = """
      Done.
      
      ```follow-ups
      [
        {"title": "Add tests", "description": "Cover edge cases", "labels": ["test"], "priority": 2},
        {"title": "Update docs"}
      ]
      ```
      """

      follow_ups = Lifecycle.extract_follow_ups(result_text)
      assert length(follow_ups) == 2

      first = hd(follow_ups)
      assert first["title"] == "Add tests"
      assert first["description"] == "Cover edge cases"
      assert first["labels"] == ["test"]
      assert first["priority"] == 2
      assert first["status"] == "proposed"
      assert String.starts_with?(first["id"], "fu_")

      second = Enum.at(follow_ups, 1)
      assert second["title"] == "Update docs"
      assert second["priority"] == 3
      assert second["labels"] == []
    end

    test "returns empty list when no block present" do
      assert Lifecycle.extract_follow_ups("All done.") == []
    end

    test "returns empty list for invalid JSON" do
      assert Lifecycle.extract_follow_ups("```follow-ups\nnot json\n```") == []
    end

    test "returns empty list when JSON is not a list" do
      assert Lifecycle.extract_follow_ups("```follow-ups\n{\"a\":1}\n```") == []
    end

    test "returns empty list for nil" do
      assert Lifecycle.extract_follow_ups(nil) == []
    end

    test "uses default title for items without title" do
      text = "```follow-ups\n[{}]\n```"
      [item] = Lifecycle.extract_follow_ups(text)
      assert item["title"] == "Untitled follow-up"
    end
  end

  describe "extract_status_verdict/1" do
    test "extracts a valid status" do
      for status <- ~w(done in_progress missing n_a planned) do
        text = "```status-verdict\n{\"status\": \"#{status}\"}\n```"
        assert {:ok, ^status} = Lifecycle.extract_status_verdict(text)
      end
    end

    test "returns error for invalid status" do
      text = "```status-verdict\n{\"status\": \"unknown_value\"}\n```"
      assert :error = Lifecycle.extract_status_verdict(text)
    end

    test "returns error when no block present" do
      assert :error = Lifecycle.extract_status_verdict("No verdict here.")
    end

    test "returns error for invalid JSON" do
      assert :error = Lifecycle.extract_status_verdict("```status-verdict\nnot json\n```")
    end

    test "returns error for nil" do
      assert :error = Lifecycle.extract_status_verdict(nil)
    end
  end

  describe "extract_product_definition/1" do
    test "extracts name and description" do
      text = """
      ```product-definition
      {"name": "My Product", "description": "Does great things"}
      ```
      """

      assert {:ok, attrs} = Lifecycle.extract_product_definition(text)
      assert attrs["name"] == "My Product"
      assert attrs["description"] == "Does great things"
    end

    test "omits blank name, returns description only" do
      text = "```product-definition\n{\"name\": \"\", \"description\": \"Desc\"}\n```"
      assert {:ok, attrs} = Lifecycle.extract_product_definition(text)
      refute Map.has_key?(attrs, "name")
      assert attrs["description"] == "Desc"
    end

    test "returns error when both fields are blank" do
      text = "```product-definition\n{\"name\": \"\", \"description\": \"\"}\n```"
      assert :error = Lifecycle.extract_product_definition(text)
    end

    test "returns error when block is absent" do
      assert :error = Lifecycle.extract_product_definition("No definition here.")
    end

    test "returns error for invalid JSON" do
      assert :error = Lifecycle.extract_product_definition("```product-definition\nnot json\n```")
    end

    test "returns error for nil" do
      assert :error = Lifecycle.extract_product_definition(nil)
    end
  end

  describe "normalize_tokens/1" do
    test "returns zero map for nil" do
      assert Lifecycle.normalize_tokens(nil) == %{
               "input_tokens" => 0,
               "output_tokens" => 0,
               "total_tokens" => 0
             }
    end

    test "converts atom-keyed map to string-keyed" do
      tokens = %{input_tokens: 100, output_tokens: 200, total_tokens: 300}

      assert Lifecycle.normalize_tokens(tokens) == %{
               "input_tokens" => 100,
               "output_tokens" => 200,
               "total_tokens" => 300
             }
    end

    test "uses 0 for missing keys" do
      assert Lifecycle.normalize_tokens(%{}) == %{
               "input_tokens" => 0,
               "output_tokens" => 0,
               "total_tokens" => 0
             }
    end
  end
end

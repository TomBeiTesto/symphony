defmodule SymphonyElixir.LLMTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.LLM

  describe "call/2" do
    test "returns {:error, :no_api_key} when ANTHROPIC_API_KEY is unset" do
      original = System.get_env("ANTHROPIC_API_KEY")
      System.delete_env("ANTHROPIC_API_KEY")
      on_exit(fn -> if original, do: System.put_env("ANTHROPIC_API_KEY", original) end)

      assert {:error, :no_api_key} = LLM.call("Hello")
    end

    test "returns {:error, :no_api_key} when ANTHROPIC_API_KEY is empty string" do
      original = System.get_env("ANTHROPIC_API_KEY")
      System.put_env("ANTHROPIC_API_KEY", "")
      on_exit(fn -> if original, do: System.put_env("ANTHROPIC_API_KEY", original) end)

      assert {:error, :no_api_key} = LLM.call("Hello")
    end
  end
end

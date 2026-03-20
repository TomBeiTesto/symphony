defmodule SymphonyElixir.BoardCase do
  @moduledoc """
  ExUnit case template for tests that require a supervised `LocalBoard` process.

  Generates a unique store-path per test module, starts `LocalBoard` under a
  supervisor, and removes the file on exit.

  ## Options

  Options are forwarded to `LocalBoard` at startup.  Common options:

    * `:project_prefix` – identifier prefix for generated issue IDs (default: `"TEST"`)
    * `:states`         – list of valid workflow states

  ## Example

      defmodule MyTest do
        use SymphonyElixir.BoardCase, project_prefix: "MY"

        test "empty board" do
          assert SymphonyElixir.LocalBoard.list_issues() == []
        end
      end
  """

  defmacro __using__(opts \\ []) do
    quote do
      use ExUnit.Case, async: false

      alias SymphonyElixir.LocalBoard

      @store_path "test_board_#{System.unique_integer([:positive])}.json"

      setup do
        extra_opts = unquote(opts)
        project_prefix = Keyword.get(extra_opts, :project_prefix, "TEST")
        board_opts = [store_path: @store_path, project_prefix: project_prefix]

        board_opts =
          case Keyword.fetch(extra_opts, :states) do
            {:ok, states} -> Keyword.put(board_opts, :states, states)
            :error -> board_opts
          end

        start_supervised!({LocalBoard, board_opts})
        on_exit(fn -> File.rm(@store_path) end)
        :ok
      end
    end
  end
end

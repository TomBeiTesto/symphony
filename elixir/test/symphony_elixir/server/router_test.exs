defmodule SymphonyElixir.Server.RouterTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Server.Router

  describe "route matching" do
    test "module uses Plug.Router" do
      assert Router.__info__(:functions) |> Keyword.has_key?(:call)
    end

    test "call/2 is callable" do
      fns = Router.__info__(:functions)
      assert {:call, 2} in fns
    end
  end
end

defmodule SymphonyElixir.Application do
  @moduledoc """
  OTP Application for Symphony Elixir.

  Starts the supervision tree for development/runtime.
  In escript mode, `CLI.startup/2` builds the tree directly.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = []

    opts = [strategy: :one_for_one, name: SymphonyElixir.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

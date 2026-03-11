defmodule SymphonyElixir.Server.CombinedRouter do
  @moduledoc """
  Combined Plug router that serves:
  - `/board*` — Local Kanban board UI and API
  - `/*` — Symphony orchestrator dashboard and API

  Used when `tracker.kind` is `"local"` so both the board and
  the orchestrator dashboard are served on the same port.
  """

  use Plug.Router

  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)
  plug(:dispatch)

  # Forward /board/* to the board router
  forward("/board", to: SymphonyElixir.Server.BoardRouter)

  # Everything else goes to the orchestrator dashboard router
  forward("/", to: SymphonyElixir.Server.Router)
end

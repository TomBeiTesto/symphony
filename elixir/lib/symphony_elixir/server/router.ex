defmodule SymphonyElixir.Server.Router do
  @moduledoc """
  HTTP router for the optional observability dashboard and JSON API.

  See SPEC Section 13.7.
  """

  use Plug.Router

  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)
  plug(:dispatch)

  # --- Dashboard ---

  get "/" do
    snapshot = SymphonyElixir.Orchestrator.get_snapshot()
    html = SymphonyElixir.Server.Dashboard.render(snapshot)

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  # --- JSON API ---

  get "/api/v1/state" do
    snapshot = SymphonyElixir.Orchestrator.get_snapshot()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(snapshot))
  end

  get "/api/v1/:identifier" do
    case SymphonyElixir.Orchestrator.get_issue_detail(identifier) do
      {:ok, detail} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(detail))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          404,
          Jason.encode!(%{
            error: %{
              code: "issue_not_found",
              message: "Issue #{identifier} not found in current state"
            }
          })
        )
    end
  end

  post "/api/v1/refresh" do
    SymphonyElixir.Orchestrator.request_refresh()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      202,
      Jason.encode!(%{
        queued: true,
        coalesced: false,
        requested_at: DateTime.utc_now(),
        operations: ["poll", "reconcile"]
      })
    )
  end

  match _ do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "not_found"}))
  end
end

defmodule SymphonyElixir.Server.RouterTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias SymphonyElixir.{Config, LocalBoard, Orchestrator}
  alias SymphonyElixir.Server.Router

  @minimal_config %Config{
    tracker_kind: "local",
    workspace_root: System.tmp_dir!() |> Path.join("symphony_router_test"),
    poll_interval_ms: 999_999_999,
    max_concurrent_agents: 2,
    stall_timeout_ms: 600_000
  }

  setup do
    board_store = "test_router_board_#{System.unique_integer([:positive])}.json"
    settings_store = "test_router_settings_#{System.unique_integer([:positive])}.json"

    start_supervised!({LocalBoard, store_path: board_store, project_prefix: "RT"})
    start_supervised!({SymphonyElixir.Settings, store_path: settings_store})

    start_supervised!(
      {Orchestrator, config: @minimal_config, prompt_template: "Work on {{ issue.identifier }}"},
      restart: :temporary
    )

    Process.sleep(100)

    on_exit(fn ->
      File.rm(board_store)
      File.rm(settings_store)
    end)

    :ok
  end

  defp call(method, path, body \\ nil) do
    conn =
      conn(method, path, body)
      |> put_req_header("content-type", "application/json")

    Router.call(conn, Router.init([]))
  end

  describe "GET /" do
    test "returns 200 HTML dashboard" do
      conn = call(:get, "/")
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/html"
      assert conn.resp_body =~ "Symphony"
    end
  end

  describe "GET /api/v1/state" do
    test "returns 200 JSON snapshot" do
      conn = call(:get, "/api/v1/state")
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/json"

      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "counts")
      assert Map.has_key?(body, "running")
    end
  end

  describe "GET /api/v1/:identifier" do
    test "returns 404 for unknown identifier" do
      conn = call(:get, "/api/v1/RT-999")
      assert conn.status == 404

      body = Jason.decode!(conn.resp_body)
      assert get_in(body, ["error", "code"]) == "issue_not_found"
    end
  end

  describe "POST /api/v1/refresh" do
    test "returns 202 with queued response" do
      conn = call(:post, "/api/v1/refresh")
      assert conn.status == 202

      body = Jason.decode!(conn.resp_body)
      assert body["queued"] == true
    end
  end

  describe "unmatched routes" do
    test "returns 404 JSON for unknown path" do
      conn = call(:get, "/api/v1/no/such/path/here")
      assert conn.status == 404

      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "not_found"
    end
  end
end

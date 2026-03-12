# Test server for Playwright E2E tests.
# Starts a minimal Orchestrator + Bandit on port 4545.
# Uses isolated board/settings files to avoid clobbering real data.

Logger.configure(level: :warning)

# Use dedicated test files so E2E runs don't touch the real board data
test_board_path = "test_e2e_board.json"
test_settings_path = "test_e2e_settings.json"

# Clean up any leftover test data from previous runs
File.rm(test_board_path)
File.rm(test_settings_path)

# Build a minimal config that won't crash
{:ok, config} =
  SymphonyElixir.Config.from_workflow(%{
    "tracker" => %{
      "kind" => "local",
      "project_slug" => "test",
      "api_key" => "test_placeholder"
    },
    "polling" => %{"interval_ms" => 600_000},
    "server" => %{"port" => 4545}
  })

children = [
  {SymphonyElixir.Settings, store_path: test_settings_path},
  {SymphonyElixir.LocalBoard, store_path: test_board_path},
  {SymphonyElixir.Orchestrator, config: config, prompt_template: "Test prompt"},
  {Bandit, plug: SymphonyElixir.Server.CombinedRouter, port: 4545, ip: {127, 0, 0, 1}}
]

{:ok, _pid} = Supervisor.start_link(children, strategy: :one_for_one)

# Seed built-in skills so E2E tests have them available
SymphonyElixir.SkillsSeed.seed()

IO.puts("E2E test server running on http://127.0.0.1:4545")
IO.puts("  Board file:    #{test_board_path}")
IO.puts("  Settings file: #{test_settings_path}")

Process.sleep(:infinity)

import Config

config :symphony_elixir,
  workflow_path: System.get_env("SYMPHONY_WORKFLOW_PATH"),
  port: System.get_env("SYMPHONY_PORT", "4000")

if config_env() == :prod do
  if is_nil(System.get_env("SYMPHONY_WORKFLOW_PATH")) do
    raise "SYMPHONY_WORKFLOW_PATH environment variable is required but not set"
  end
end

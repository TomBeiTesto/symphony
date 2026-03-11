import Config

config :symphony_elixir,
  workflow_path: System.get_env("SYMPHONY_WORKFLOW_PATH"),
  port: System.get_env("SYMPHONY_PORT")

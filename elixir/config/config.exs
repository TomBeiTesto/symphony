import Config

config :symphony_elixir,
  workflow_path: nil,
  port: nil

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:issue_id, :issue_identifier, :session_id]

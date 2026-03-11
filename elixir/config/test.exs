import Config

config :symphony_elixir,
  tracker_client: SymphonyElixir.Tracker.MockClient

config :logger, level: :warning

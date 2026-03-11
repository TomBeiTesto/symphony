defmodule SymphonyElixir do
  @moduledoc """
  Symphony Elixir – an orchestration service that polls an issue tracker,
  creates per-issue workspaces, and runs coding-agent sessions.

  See `SPEC.md` for the full service specification.
  """

  @version Mix.Project.config()[:version]

  @spec version() :: String.t()
  def version, do: @version
end

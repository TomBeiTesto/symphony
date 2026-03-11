defmodule SymphonyElixir.Tracker.Behaviour do
  @moduledoc """
  Behaviour for issue tracker clients (GitLab, Local Board, etc.).
  Allows mocking in tests via Mox.
  """

  alias SymphonyElixir.Issue

  @callback fetch_candidate_issues(config :: SymphonyElixir.Config.t()) ::
              {:ok, [Issue.t()]} | {:error, atom() | {atom(), term()}}

  @callback fetch_issues_by_states(
              config :: SymphonyElixir.Config.t(),
              state_names :: [String.t()]
            ) ::
              {:ok, [Issue.t()]} | {:error, atom() | {atom(), term()}}

  @callback fetch_issue_states_by_ids(
              config :: SymphonyElixir.Config.t(),
              issue_ids :: [String.t()]
            ) ::
              {:ok, [Issue.t()]} | {:error, atom() | {atom(), term()}}
end

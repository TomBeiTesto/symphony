defmodule SymphonyElixir.LocalBoard.Client do
  @moduledoc """
  Local board implementation of the tracker behaviour.

  Reads from `SymphonyElixir.LocalBoard` GenServer instead of hitting
  a remote API. This lets Symphony run fully offline with
  a local Kanban board.
  """

  @behaviour SymphonyElixir.Tracker.Behaviour

  alias SymphonyElixir.{Config, Issue, LocalBoard}

  @impl true
  @spec fetch_candidate_issues(Config.t()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_candidate_issues(%Config{} = config) do
    issues = LocalBoard.list_issues_by_states(config.active_states)
    {:ok, Enum.map(issues, &LocalBoard.to_issue_struct/1)}
  rescue
    e -> {:error, {:local_board_error, Exception.message(e)}}
  end

  @impl true
  @spec fetch_issues_by_states(Config.t(), [String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issues_by_states(%Config{} = _config, []), do: {:ok, []}

  def fetch_issues_by_states(%Config{} = _config, state_names) do
    issues = LocalBoard.list_issues_by_states(state_names)
    {:ok, Enum.map(issues, &LocalBoard.to_issue_struct/1)}
  rescue
    e -> {:error, {:local_board_error, Exception.message(e)}}
  end

  @impl true
  @spec fetch_issue_states_by_ids(Config.t(), [String.t()]) ::
          {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issue_states_by_ids(%Config{} = _config, []), do: {:ok, []}

  def fetch_issue_states_by_ids(%Config{} = _config, issue_ids) do
    records = LocalBoard.get_issues_by_ids(issue_ids)
    {:ok, Enum.map(records, &LocalBoard.to_issue_struct/1)}
  rescue
    e -> {:error, {:local_board_error, Exception.message(e)}}
  end

  @spec execute_graphql(Config.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def execute_graphql(%Config{} = _config, _query, _variables) do
    # GraphQL is not supported on the local board — this is a no-op.
    {:error, :graphql_not_supported_on_local_board}
  end
end

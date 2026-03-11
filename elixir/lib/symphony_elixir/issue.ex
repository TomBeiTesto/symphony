defmodule SymphonyElixir.Issue do
  @moduledoc """
  Normalized issue record used by orchestration, prompt rendering, and observability.

  See SPEC Section 4.1.1.
  """

  @type blocker_ref :: %{
          id: String.t() | nil,
          identifier: String.t() | nil,
          state: String.t() | nil
        }

  @type t :: %__MODULE__{
          id: String.t(),
          identifier: String.t(),
          title: String.t(),
          description: String.t() | nil,
          priority: integer() | nil,
          state: String.t(),
          branch_name: String.t() | nil,
          url: String.t() | nil,
          labels: [String.t()],
          blocked_by: [blocker_ref()],
          project_id: String.t() | nil,
          product_id: String.t() | nil,
          parent_issue_id: String.t() | nil,
          propose_followups: boolean(),
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @enforce_keys [:id, :identifier, :title, :state]
  defstruct [
    :id,
    :identifier,
    :title,
    :description,
    :priority,
    :state,
    :branch_name,
    :url,
    :project_id,
    :product_id,
    :parent_issue_id,
    :created_at,
    :updated_at,
    labels: [],
    blocked_by: [],
    propose_followups: true
  ]

  @doc """
  Returns the sanitized workspace key for this issue's identifier.

  Only `[A-Za-z0-9._-]` are preserved; all other characters become `_`.
  """
  @spec workspace_key(t()) :: String.t()
  def workspace_key(%__MODULE__{identifier: identifier}) do
    sanitize_identifier(identifier)
  end

  @doc """
  Sanitize an identifier string for use as a workspace directory name.
  """
  @spec sanitize_identifier(String.t()) :: String.t()
  def sanitize_identifier(identifier) when is_binary(identifier) do
    String.replace(identifier, ~r/[^A-Za-z0-9._-]/, "_")
  end

  @doc """
  Returns true if the issue has all required fields for dispatch eligibility.
  """
  @spec valid_for_dispatch?(t()) :: boolean()
  def valid_for_dispatch?(%__MODULE__{id: id, identifier: ident, title: title, state: state}) do
    is_binary(id) and id != "" and
      is_binary(ident) and ident != "" and
      is_binary(title) and title != "" and
      is_binary(state) and state != ""
  end

  @doc """
  Normalize a state string: trim + lowercase.
  """
  @spec normalize_state(String.t()) :: String.t()
  def normalize_state(state) when is_binary(state) do
    state |> String.trim() |> String.downcase()
  end

  @doc """
  Check if any blocker is non-terminal.
  """
  @spec has_non_terminal_blockers?(t(), MapSet.t()) :: boolean()
  def has_non_terminal_blockers?(%__MODULE__{blocked_by: blockers}, terminal_states) do
    Enum.any?(blockers, fn blocker ->
      case blocker do
        %{state: nil} -> true
        %{state: state} -> not MapSet.member?(terminal_states, normalize_state(state))
        _ -> true
      end
    end)
  end

  @doc """
  Convert issue to a template-friendly map with string keys.
  """
  @spec to_template_map(t()) :: map()
  def to_template_map(%__MODULE__{} = issue) do
    issue
    |> Map.from_struct()
    |> Map.new(fn {k, v} -> {Atom.to_string(k), serialize_value(v)} end)
  end

  defp serialize_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp serialize_value(list) when is_list(list), do: Enum.map(list, &serialize_value/1)

  defp serialize_value(%{} = map) do
    Map.new(map, fn {k, v} -> {to_string(k), serialize_value(v)} end)
  end

  defp serialize_value(other), do: other
end

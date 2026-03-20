defmodule SymphonyElixir.DateTimeUtils do
  @moduledoc """
  Shared date/time parsing utilities.
  """

  @doc """
  Parse an ISO 8601 datetime string into a `DateTime` struct.
  
  Returns `nil` for `nil` input or unparseable strings.
  """
  @spec parse_datetime(String.t() | nil) :: DateTime.t() | nil
  def parse_datetime(nil), do: nil

  def parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end
end

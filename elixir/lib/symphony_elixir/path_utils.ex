defmodule SymphonyElixir.PathUtils do
  @moduledoc """
  Shared path normalization helpers for traversal-safe comparisons.

  `normalize_path/1` expands a path to its absolute form and, on Windows,
  additionally converts backslashes to forward slashes and lowercases the
  result so that comparisons are case-insensitive.
  """

  @doc """
  Expand and canonicalize a filesystem path.

  On Windows the result is further normalized to forward slashes and
  lowercase so that prefix comparisons are case-insensitive.
  """
  @spec normalize_path(String.t()) :: String.t()
  def normalize_path(path) do
    expanded = Path.expand(path)

    case :os.type() do
      {:win32, _} ->
        expanded |> String.replace("\\", "/") |> String.downcase()

      _ ->
        expanded
    end
  end
end

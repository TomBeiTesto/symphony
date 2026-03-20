defmodule SymphonyElixir.YamlParser do
  @moduledoc """
  Minimal YAML frontmatter parser shared across knowledge-base modules.

  Handles flat key-value pairs and simple list items (lines starting with "- ").
  Strings may be single- or double-quoted; quotes are stripped on read.
  """

  @doc """
  Parse a YAML block string into a map.

  Returns `%{}` for an empty or blank input.
  """
  @spec parse(String.t()) :: map()
  def parse(""), do: %{}

  def parse(yaml_block) do
    yaml_block
    |> String.split("\n")
    |> Enum.reject(&(String.trim(&1) == ""))
    |> parse_lines(%{}, nil)
  end

  defp parse_lines([], acc, _current_list_key), do: acc

  defp parse_lines([line | rest], acc, current_list_key) do
    trimmed = String.trim(line)

    cond do
      # List item: "  - value"
      String.starts_with?(trimmed, "- ") and current_list_key != nil ->
        value = String.trim_leading(trimmed, "- ") |> String.trim()
        existing = Map.get(acc, current_list_key, [])

        parse_lines(
          rest,
          Map.put(acc, current_list_key, existing ++ [value]),
          current_list_key
        )

      # Key with empty value (list follows): "key:"
      String.ends_with?(trimmed, ":") ->
        key = String.trim_trailing(trimmed, ":")
        parse_lines(rest, acc, key)

      # Key-value pair: "key: value"
      String.contains?(trimmed, ": ") ->
        [key | value_parts] = String.split(trimmed, ": ", parts: 2)
        value = Enum.join(value_parts, ": ") |> String.trim() |> unquote_value()
        parse_lines(rest, Map.put(acc, key, value), nil)

      true ->
        parse_lines(rest, acc, current_list_key)
    end
  end

  defp unquote_value("\"" <> rest), do: String.trim_trailing(rest, "\"")
  defp unquote_value("'" <> rest), do: String.trim_trailing(rest, "'")
  defp unquote_value(other), do: other
end

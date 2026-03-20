defmodule SymphonyElixir.LocalBoard.Helpers do
  @moduledoc """
  Shared helper functions used across local board submodules.

  Provides ID generation, parsing utilities, and common map-update helpers.
  """

  alias SymphonyElixir.ParseUtils

  def generate_id do
    :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
  end

  def parse_priority(val) when is_integer(val), do: val
  def parse_priority(val) when is_binary(val), do: ParseUtils.parse_optional_int(val) || 0
  def parse_priority(_), do: 0

  def parse_labels(val) when is_list(val), do: Enum.map(val, &to_string/1)

  def parse_labels(val) when is_binary(val),
    do: String.split(val, ",") |> Enum.map(&String.trim/1)

  def parse_labels(_), do: []

  def parse_boolean(true), do: true
  def parse_boolean(false), do: false
  def parse_boolean("true"), do: true
  def parse_boolean(_), do: false

  def sort_issues(issues) do
    Enum.sort_by(issues, fn i -> {-(i.priority || 0), i.created_at || ""} end)
  end

  def maybe_put(map, _key, nil), do: map
  def maybe_put(map, key, value), do: Map.put(map, key, value)

  def maybe_update(record, key, attrs) do
    str_key = Atom.to_string(key)

    if Map.has_key?(attrs, str_key) do
      Map.put(record, key, attrs[str_key])
    else
      record
    end
  end

  def maybe_update(record, key, attrs, transform) do
    str_key = Atom.to_string(key)

    if Map.has_key?(attrs, str_key) do
      Map.put(record, key, transform.(attrs[str_key]))
    else
      record
    end
  end

  def slugify(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> String.slice(0, 32)
  end

  def slugify(_), do: "project"
end

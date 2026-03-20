defmodule SymphonyElixir.ParseUtils do
  @moduledoc """
  Shared integer-parsing helpers used across configuration and routing modules.

  All functions accept `nil`, integers, binary strings, or arbitrary terms.
  Binary inputs are parsed strictly (`{n, ""}`) unless noted otherwise.
  """

  @doc "Parse a strictly positive integer (> 0); return `default` otherwise."
  @spec parse_positive_int(term(), integer()) :: integer()
  def parse_positive_int(nil, default), do: default
  def parse_positive_int(val, _default) when is_integer(val) and val > 0, do: val
  def parse_positive_int(val, default) when is_integer(val), do: default

  def parse_positive_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, ""} when n > 0 -> n
      _ -> default
    end
  end

  def parse_positive_int(_, default), do: default

  @doc "Parse a non-negative integer (>= 0); return `default` otherwise."
  @spec parse_non_neg_int(term(), integer()) :: integer()
  def parse_non_neg_int(nil, default), do: default
  def parse_non_neg_int(val, _default) when is_integer(val) and val >= 0, do: val

  def parse_non_neg_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, ""} when n >= 0 -> n
      _ -> default
    end
  end

  def parse_non_neg_int(_, default), do: default

  @doc "Parse any integer without a sign constraint; return `default` otherwise."
  @spec parse_optional_int(term()) :: integer() | nil
  def parse_optional_int(nil), do: nil
  def parse_optional_int(val) when is_integer(val), do: val

  def parse_optional_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, ""} -> n
      _ -> nil
    end
  end

  def parse_optional_int(_), do: nil

  @doc """
  Leniently parse an integer from a binary, accepting trailing non-numeric
  characters (e.g. query-param values such as `\"50px\"`).
  Returns `default` when the value cannot be parsed at all.
  """
  @spec parse_int(term(), integer()) :: integer()
  def parse_int(nil, default), do: default
  def parse_int(val, _default) when is_integer(val), do: val

  def parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> default
    end
  end

  def parse_int(_, default), do: default
end

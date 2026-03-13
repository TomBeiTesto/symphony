defmodule SymphonyElixir.DateTimeUtilsTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.DateTimeUtils

  describe "parse_datetime/1" do
    test "parses a valid ISO 8601 string" do
      assert {:ok, expected, _} = DateTime.from_iso8601("2024-03-15T10:30:00Z")
      assert DateTimeUtils.parse_datetime("2024-03-15T10:30:00Z") == expected
    end

    test "parses ISO 8601 string with offset" do
      result = DateTimeUtils.parse_datetime("2024-03-15T10:30:00+02:00")
      assert %DateTime{} = result
    end

    test "returns nil for nil input" do
      assert DateTimeUtils.parse_datetime(nil) == nil
    end

    test "returns nil for invalid string" do
      assert DateTimeUtils.parse_datetime("not a date") == nil
      assert DateTimeUtils.parse_datetime("") == nil
      assert DateTimeUtils.parse_datetime("2024-13-01") == nil
    end
  end
end

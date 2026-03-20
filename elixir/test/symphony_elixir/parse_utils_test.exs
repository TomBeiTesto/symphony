defmodule SymphonyElixir.ParseUtilsTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.ParseUtils

  describe "parse_positive_int/2" do
    test "returns value for positive integer" do
      assert ParseUtils.parse_positive_int(5, 0) == 5
    end

    test "returns default for zero" do
      assert ParseUtils.parse_positive_int(0, 99) == 99
    end

    test "returns default for negative integer" do
      assert ParseUtils.parse_positive_int(-3, 99) == 99
    end

    test "returns default for nil" do
      assert ParseUtils.parse_positive_int(nil, 42) == 42
    end

    test "parses positive string" do
      assert ParseUtils.parse_positive_int("10", 0) == 10
    end

    test "returns default for zero string" do
      assert ParseUtils.parse_positive_int("0", 99) == 99
    end

    test "returns default for negative string" do
      assert ParseUtils.parse_positive_int("-5", 99) == 99
    end

    test "returns default for non-numeric string" do
      assert ParseUtils.parse_positive_int("abc", 99) == 99
    end

    test "returns default for string with trailing chars" do
      assert ParseUtils.parse_positive_int("10px", 99) == 99
    end

    test "returns default for non-string non-integer term" do
      assert ParseUtils.parse_positive_int(:atom, 99) == 99
      assert ParseUtils.parse_positive_int([1], 99) == 99
    end
  end

  describe "parse_non_neg_int/2" do
    test "returns value for positive integer" do
      assert ParseUtils.parse_non_neg_int(5, 99) == 5
    end

    test "returns value for zero" do
      assert ParseUtils.parse_non_neg_int(0, 99) == 0
    end

    test "returns default for negative integer" do
      assert ParseUtils.parse_non_neg_int(-1, 99) == 99
    end

    test "returns default for nil" do
      assert ParseUtils.parse_non_neg_int(nil, 42) == 42
    end

    test "parses zero string" do
      assert ParseUtils.parse_non_neg_int("0", 99) == 0
    end

    test "parses positive string" do
      assert ParseUtils.parse_non_neg_int("7", 99) == 7
    end

    test "returns default for negative string" do
      assert ParseUtils.parse_non_neg_int("-1", 99) == 99
    end

    test "returns default for non-numeric string" do
      assert ParseUtils.parse_non_neg_int("nope", 99) == 99
    end

    test "returns default for non-string non-integer term" do
      assert ParseUtils.parse_non_neg_int(%{}, 99) == 99
    end
  end

  describe "parse_optional_int/1" do
    test "returns nil for nil" do
      assert ParseUtils.parse_optional_int(nil) == nil
    end

    test "returns integer directly" do
      assert ParseUtils.parse_optional_int(42) == 42
      assert ParseUtils.parse_optional_int(-3) == -3
      assert ParseUtils.parse_optional_int(0) == 0
    end

    test "parses valid integer string" do
      assert ParseUtils.parse_optional_int("100") == 100
      assert ParseUtils.parse_optional_int("-5") == -5
    end

    test "returns nil for non-numeric string" do
      assert ParseUtils.parse_optional_int("abc") == nil
    end

    test "returns nil for string with trailing chars" do
      assert ParseUtils.parse_optional_int("10px") == nil
    end

    test "returns nil for non-string non-integer term" do
      assert ParseUtils.parse_optional_int(:atom) == nil
    end
  end

  describe "parse_int/2" do
    test "returns value for integer" do
      assert ParseUtils.parse_int(42, 0) == 42
      assert ParseUtils.parse_int(-3, 0) == -3
    end

    test "returns default for nil" do
      assert ParseUtils.parse_int(nil, 99) == 99
    end

    test "parses valid string" do
      assert ParseUtils.parse_int("50", 0) == 50
    end

    test "leniently parses string with trailing chars" do
      assert ParseUtils.parse_int("50px", 0) == 50
      assert ParseUtils.parse_int("100%", 0) == 100
    end

    test "returns default for completely non-numeric string" do
      assert ParseUtils.parse_int("abc", 99) == 99
    end

    test "returns default for empty string" do
      assert ParseUtils.parse_int("", 99) == 99
    end

    test "returns default for non-string non-integer term" do
      assert ParseUtils.parse_int(:atom, 99) == 99
    end
  end
end

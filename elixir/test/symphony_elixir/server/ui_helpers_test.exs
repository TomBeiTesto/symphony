defmodule SymphonyElixir.Server.UIHelpersTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Server.UIHelpers

  describe "motion_css/0" do
    setup do
      css = UIHelpers.motion_css()
      {:ok, css: css}
    end

    test "includes active/pressed scale-down for buttons", %{css: css} do
      assert css =~ ".btn:active"
      assert css =~ "scale(0.98)"
    end

    test "includes active/pressed feedback for cards", %{css: css} do
      assert css =~ ".card:active"
    end

    test "includes active/pressed feedback for sidebar items", %{css: css} do
      assert css =~ ".sidebar-item:active"
    end

    test "overrides toastIn keyframe with slide-in-from-right", %{css: css} do
      assert css =~ "@keyframes toastIn"
      assert css =~ "translateX(20px)"
    end

    test "wraps entrance animations in prefers-reduced-motion: no-preference", %{css: css} do
      assert css =~ "prefers-reduced-motion: no-preference"
    end

    test "includes modal entrance animation", %{css: css} do
      assert css =~ "@keyframes modalIn"
      assert css =~ ".modal-overlay.active .modal"
    end

    test "includes modal overlay fade animation", %{css: css} do
      assert css =~ "@keyframes overlayIn"
      assert css =~ ".modal-overlay.active"
    end

    test "includes card entrance with stagger choreography", %{css: css} do
      assert css =~ "@keyframes cardEntrance"
      assert css =~ ".card:nth-child(2)"
      assert css =~ ".card:nth-child(10)"
      # Max delay must not exceed 300ms (30ms * 10 = 300ms)
      assert css =~ "animation-delay: 270ms"
      refute css =~ "animation-delay: 300ms"
    end

    test "includes dropdown entrance animation", %{css: css} do
      assert css =~ "@keyframes dropdownIn"
      assert css =~ ".dropdown.open .dropdown-menu"
    end

    test "includes tab content fade-in", %{css: css} do
      assert css =~ "@keyframes fadeSlideUp"
      assert css =~ ".tab-content"
    end

    test "includes scroll-driven entrance hook classes", %{css: css} do
      assert css =~ ".enter-on-scroll"
      assert css =~ ".enter-on-scroll.entered"
    end

    test "uses will-change sparingly — only on the animated modal panel", %{css: css} do
      assert css =~ "will-change: transform, opacity"
      # Should appear exactly once (only for modal)
      assert length(String.split(css, "will-change")) == 2
    end

    test "no animation exceeds 500ms", %{css: css} do
      # Extract all duration values and verify none exceed 500ms
      duration_values =
        Regex.scan(~r/(\d+)ms/, css)
        |> Enum.map(fn [_, n] -> String.to_integer(n) end)

      assert Enum.all?(duration_values, fn ms -> ms <= 500 end),
             "Found animation duration > 500ms: #{inspect(Enum.filter(duration_values, &(&1 > 500)))}"
    end
  end

  describe "scroll_entrance_js/0" do
    test "returns IntersectionObserver setup" do
      js = UIHelpers.scroll_entrance_js()
      assert js =~ "IntersectionObserver"
      assert js =~ ".enter-on-scroll"
      assert js =~ ".entered"
      assert js =~ "observer.unobserve"
    end

    test "is safe when IntersectionObserver is unavailable" do
      js = UIHelpers.scroll_entrance_js()
      assert js =~ "typeof IntersectionObserver === 'undefined'"
    end
  end

  describe "standard_css/0" do
    test "includes motion_css output" do
      css = UIHelpers.standard_css()
      assert css =~ "cardEntrance"
      assert css =~ "modalIn"
      assert css =~ "dropdownIn"
    end

    test "includes reduced_motion_css after motion_css" do
      css = UIHelpers.standard_css()
      assert css =~ "prefers-reduced-motion: reduce"
      motion_pos = :binary.match(css, "cardEntrance") |> elem(0)
      reduced_pos = :binary.match(css, "prefers-reduced-motion: reduce") |> elem(0)
      assert motion_pos < reduced_pos,
             "motion_css should appear before reduced_motion_css in the bundle"
    end
  end

  describe "page_template/4" do
    test "includes scroll_entrance_js in output" do
      html = UIHelpers.page_template("Test", "", "", "<p>body</p>")
      assert html =~ "IntersectionObserver"
      assert html =~ "enter-on-scroll"
    end

    test "includes motion CSS in the style block" do
      html = UIHelpers.page_template("Test", "", "", "<p>body</p>")
      assert html =~ "cardEntrance"
      assert html =~ "modalIn"
    end
  end
end

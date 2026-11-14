defmodule PolticoolWeb.BadgeComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import PolticoolWeb.BadgeComponents

  defp query(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)

  describe "outcome_badge/1" do
    for {input, outcome, label} <- [
          {:kept, "kept", "Kept"},
          {:partial, "partial", "Partial"},
          {:broken, "broken", "Broken"},
          {:untested, "untested", "Untested"},
          {:absent, "absent", "Absent/NV"},
          {"KEPT", "kept", "Kept"},
          {"absent_nv", "absent", "Absent/NV"}
        ] do
      test "renders #{inspect(input)} as #{outcome} with the outcome DOM hook" do
        assigns = %{outcome: unquote(input)}

        badge =
          rendered_to_string(~H"<.outcome_badge outcome={@outcome} />")
          |> query("[data-role=outcome]")

        assert Enum.count(badge) == 1
        assert LazyHTML.attribute(badge, "data-outcome") == [unquote(outcome)]
        assert LazyHTML.text(badge) |> String.trim() == unquote(label)
      end
    end

    test "draws Absent/NV dashed, since it is shown but not graded" do
      assigns = %{}

      [class] =
        rendered_to_string(~H"<.outcome_badge outcome={:absent} />")
        |> query("[data-role=outcome]")
        |> LazyHTML.attribute("class")

      assert class =~ "border-dashed"
    end

    test "raises on an unknown outcome rather than showing the wrong verdict" do
      assigns = %{}

      assert_raise ArgumentError, ~r/unknown receipt outcome/, fn ->
        rendered_to_string(~H"<.outcome_badge outcome={:maybe} />")
      end

      assert_raise ArgumentError, fn ->
        rendered_to_string(~H"<.outcome_badge outcome={nil} />")
      end
    end
  end

  describe "party_label/1" do
    for {input, letter, name} <- [
          {"R", "R", "Republican"},
          {:d, "D", "Democrat"},
          {"U", "U", "Unaffiliated"},
          {"Democratic", "D", "Democratic"},
          {"Libertarian", "L", "Libertarian"}
        ] do
      test "renders #{inspect(input)} as #{letter} with the full name for screen readers" do
        assigns = %{party: unquote(input)}

        label =
          rendered_to_string(~H"<.party_label party={@party} />") |> query("[data-role=party]")

        assert LazyHTML.attribute(label, "data-party") == [unquote(letter)]
        assert LazyHTML.query(label, "[aria-hidden=true]") |> LazyHTML.text() == unquote(letter)
        assert LazyHTML.query(label, ".sr-only") |> LazyHTML.text() == unquote(name)
      end
    end

    test "raises without a party" do
      assigns = %{}

      assert_raise ArgumentError, fn -> rendered_to_string(~H"<.party_label party={nil} />") end
      assert_raise ArgumentError, fn -> rendered_to_string(~H|<.party_label party=" " />|) end
    end
  end

  describe "unofficial_badge/1" do
    test "includes the canvass date by default" do
      assigns = %{}

      badge =
        rendered_to_string(~H"<.unofficial_badge />") |> query("[data-role=unofficial-result]")

      assert LazyHTML.text(badge) |> String.trim() == "Unofficial result · canvass Nov 23"
    end

    test "omits the canvass date when it is nil" do
      assigns = %{}

      badge =
        rendered_to_string(~H"<.unofficial_badge canvass={nil} />")
        |> query("[data-role=unofficial-result]")

      assert LazyHTML.text(badge) |> String.trim() == "Unofficial result"
    end
  end
end

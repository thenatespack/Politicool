defmodule PolticoolWeb.MoneyComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import PolticoolWeb.MoneyComponents

  defp industries do
    [
      %{industry: "Real Estate & Construction", total: 3400.0, share: 0.314},
      %{industry: "Energy & Mining", total: 2200.0, share: 0.2},
      %{industry: "Healthcare", total: 1_234_567.4, share: 0.17}
    ]
  end

  defp doc(html), do: LazyHTML.from_fragment(html)

  test "renders a segment and a legend row per industry, with dollars and shares" do
    assigns = %{industries: industries()}
    doc = rendered_to_string(~H|<.money_bar id="m" industries={@industries} />|) |> doc()

    rows = LazyHTML.query(doc, "#m li[data-industry]")
    assert Enum.count(rows) == 3
    assert LazyHTML.query(doc, "#m [aria-hidden=true] span") |> Enum.count() == 3

    first =
      LazyHTML.query(doc, "#m li[data-industry='Real Estate & Construction']") |> LazyHTML.text()

    assert first =~ "$3,400"
    assert first =~ "31%"

    assert LazyHTML.query(doc, "#m li[data-industry=Healthcare]") |> LazyHTML.text() =~
             "$1,234,567"
  end

  test "states facts only, with no implied cause" do
    assigns = %{industries: industries()}
    html = rendered_to_string(~H|<.money_bar id="m" industries={@industries} />|)

    assert doc(html) |> LazyHTML.query("#m p") |> LazyHTML.text() =~
             "facts only, no implied cause"
  end

  test "donor_tag/1 names the related industries" do
    assigns = %{}
    html = rendered_to_string(~H|<.donor_tag industries={["Energy & Mining", "Agriculture"]} />|)

    assert doc(html) |> LazyHTML.query("[data-role=donor-tag]") |> LazyHTML.text() =~
             "Top donor industry: Energy & Mining, Agriculture"
  end

  test "dollars/1 groups thousands" do
    assert dollars(0) == "$0"
    assert dollars(999.6) == "$1,000"
    assert dollars(1_234_567) == "$1,234,567"
  end
end

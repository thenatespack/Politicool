defmodule PolticoolWeb.LayoutsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias PolticoolWeb.Layouts

  defp parse(html), do: LazyHTML.from_fragment(html)
  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()

  test "app shell renders the top bar, a home link and the page content in main" do
    assigns = %{}

    doc =
      rendered_to_string(~H"""
      <Layouts.app flash={%{}}>
        <p id="page-content">Hello</p>
      </Layouts.app>
      """)
      |> parse()

    assert count(doc, "#site-header #site-logo[href='/']") == 1
    assert count(doc, "main#main #page-content") == 1
    assert count(doc, "a[href='#main']") == 1
    assert count(doc, "#flash-group") == 1
    assert count(doc, "#site-tag") == 0
  end

  test "app shell shows the optional top-bar tag" do
    assigns = %{}

    doc =
      rendered_to_string(~H"""
      <Layouts.app flash={%{}} tag="Sample">content</Layouts.app>
      """)
      |> parse()

    assert doc |> LazyHTML.query("#site-header #site-tag") |> LazyHTML.text() |> String.trim() ==
             "Sample"
  end
end

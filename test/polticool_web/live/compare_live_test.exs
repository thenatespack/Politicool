defmodule PolticoolWeb.CompareLiveTest do
  use PolticoolWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup do
    seeds = Polticool.Seeds.hd62!()
    %{thurston: seeds.thurston, chappell: seeds.chappell}
  end

  defp count(view, selector),
    do: view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.count()

  test "#compare-grid has a column per candidate with grade and the three bars", %{
    conn: conn,
    thurston: thurston,
    chappell: chappell
  } do
    {:ok, view, _html} = live(conn, ~p"/races/hd62/compare")

    for c <- [thurston, chappell] do
      assert has_element?(view, "#compare-grid #candidate-#{c.id} [data-role=grade]")
      assert has_element?(view, "#candidate-#{c.id} [data-role=score-bars] [data-bar=promised]")
    end

    # Chappell has no voting record: shown as "No record", not as a zero.
    assert has_element?(view, "#candidate-#{chappell.id} [data-bar=voted][data-value=none]")
  end

  test "rows are issues, chosen issues first", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/races/hd62/compare?#{%{issues: "water"}}")

    ids =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#compare-grid section[id^=issue-row-]")
      |> Enum.map(&hd(LazyHTML.attribute(&1, "id")))

    assert List.first(ids) == "issue-row-water"
    assert "issue-row-education" in ids
    assert has_element?(view, "#issue-row-water-title", "your issue")
  end

  test "opens one receipt by default so the demo can flip it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/races/hd62/compare")

    assert has_element?(view, "#receipt-panel [data-role=receipt]")
    assert count(view, "button[id$=-next-1]") == 1
    assert has_element?(view, "#receipt-panel button", "See the bill")
    assert count(view, "#compare-grid button[aria-current=true]") == 1
  end

  test "tapping a receipt opens it in the panel", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/races/hd62/compare")

    [target] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#compare-grid button[id^=item-]:not([aria-current])")
      |> Enum.take(1)
      |> Enum.map(&hd(LazyHTML.attribute(&1, "id")))

    item_id = String.replace_prefix(target, "item-", "")
    view |> element("##{target}") |> render_click()

    assert_patch(view, ~p"/races/hd62/compare?#{%{receipt: item_id}}")
    assert has_element?(view, "#receipt-panel #receipt-#{item_id}")
    assert has_element?(view, "##{target}[aria-current=true]")
  end

  test "an unknown race goes back to the ballot", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/ballot", flash: flash}}} =
             live(conn, ~p"/races/nope/compare")

    assert flash["error"] =~ "couldn't find"
  end
end

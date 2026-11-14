defmodule PolticoolWeb.IssuesLiveTest do
  use PolticoolWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "shows the four issue toggles with the agreed button texts", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#issue-housing", "Housing & cost of living")
    assert has_element?(view, "#issue-water", "Water & environment")
    assert has_element?(view, "#issue-education", "Education & taxes")
    assert has_element?(view, "#issue-growth", "Growth, transit & health")
    assert has_element?(view, "#see-ballot", "See my ballot")
    assert has_element?(view, "#issue-housing[aria-pressed=false]")
  end

  test "toggling an issue flips aria-pressed", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("#issue-housing") |> render_click()
    assert has_element?(view, "#issue-housing[aria-pressed=true]")

    view |> element("#issue-housing") |> render_click()
    assert has_element?(view, "#issue-housing[aria-pressed=false]")
  end

  test "See my ballot navigates with the chosen issues in display order", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("#issue-water") |> render_click()
    view |> element("#issue-housing") |> render_click()

    assert {:error, {:live_redirect, %{to: to}}} =
             view |> element("#see-ballot") |> render_click()

    assert to == ~p"/ballot?#{%{issues: "housing,water"}}"
  end

  test "See my ballot with nothing chosen goes to the whole ballot", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert {:error, {:live_redirect, %{to: "/ballot"}}} =
             view |> element("#see-ballot") |> render_click()
  end

  test "preselects issues from the URL and ignores unknown ones", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/?#{%{issues: "water,bogus"}}")

    assert has_element?(view, "#issue-water[aria-pressed=true]")
    assert has_element?(view, "#issue-housing[aria-pressed=false]")

    render_click(view, "toggle", %{"issue" => "bogus"})
    assert has_element?(view, "#issue-water[aria-pressed=true]")
  end
end

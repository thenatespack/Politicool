defmodule PolticoolWeb.BallotLiveTest do
  use PolticoolWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "with the HD62 seeds" do
    setup do
      Polticool.Seeds.hd62!()
      :ok
    end

    test "shows the HD62 race card with its Compare link (demo hooks)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/ballot?#{%{issues: "housing,water"}}")

      assert has_element?(view, "#section-house #race-hd62")

      assert has_element?(
               view,
               "#race-hd62 a#compare-hd62[href='/races/hd62/compare']",
               "Compare"
             )

      assert has_element?(view, "#race-hd62 [data-role=grade]")
      assert has_element?(view, "#race-hd62 [data-role=party][data-party=R]")
      assert has_element?(view, "#race-hd62 [data-role=party][data-party=D]")
      assert has_element?(view, "#race-hd62 [data-role=unofficial-result]")
    end

    test "has judicial retention and amendment sections", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/ballot")

      assert has_element?(view, "#section-judicial #race-judicial-pohlman")
      assert has_element?(view, "#brief-pohlman[href='/races/judicial/pohlman']")
      assert has_element?(view, "#section-amendments #amendment-a")
      refute has_element?(view, "#section-house #race-judicial-pohlman")
    end

    test "issue chips reflect the URL and patch it when toggled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/ballot?#{%{issues: "housing"}}")

      assert has_element?(view, "#filter-housing[aria-pressed=true]")
      assert has_element?(view, "#filter-water[aria-pressed=false]")

      view |> element("#filter-water") |> render_click()
      assert_patch(view, ~p"/ballot?#{%{issues: "housing,water"}}")
      assert has_element?(view, "#filter-water[aria-pressed=true]")
      assert has_element?(view, "#race-hd62")
    end
  end

  test "shows empty states before any data is loaded", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/ballot")

    refute has_element?(view, "#race-hd62")
    assert has_element?(view, "#house-races", "No House races loaded yet.")
    assert has_element?(view, "#judicial-races", "No judges on this ballot.")
  end
end

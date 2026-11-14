defmodule PolticoolWeb.ResearchLiveTest do
  use PolticoolWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  defp step(id, status, detail \\ nil),
    do: %{id: id, label: "Step #{id}", detail: detail, status: status}

  test "has the labelled name input and the Research button (demo hooks)", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/research")

    assert has_element?(view, "label[for=research_name]", "Legislator name")
    assert has_element?(view, "input#research_name")
    assert has_element?(view, "#research-submit", "Research")
    refute has_element?(view, "#research-run")
  end

  test "asks for a name when the field is empty", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/research")

    view |> form("#research-form", research: %{name: "  "}) |> render_submit()
    assert has_element?(view, "#research-error")
  end

  test "says so when no legislator matches", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/research")

    view |> form("#research-form", research: %{name: "Zzyzx"}) |> render_submit()
    assert has_element?(view, "#research-error", "Zzyzx")
    refute has_element?(view, "#research-run")
  end

  test "shows a picker for an ambiguous name", %{conn: conn} do
    seeds = Polticool.Seeds.hd62!()
    {:ok, view, _html} = live(conn, ~p"/research")

    # "ll" matches both David Chappell and Jill M. Pohlman.
    view |> form("#research-form", research: %{name: "ll"}) |> render_submit()

    assert has_element?(view, "#research-picker #pick-#{seeds.chappell.id}")
    assert has_element?(view, "#research-picker #pick-#{seeds.pohlman.id}")
  end

  test "streams steps, replaces a step by id, and lists receipts", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/research")

    send(view.pid, {:step, step("find", :running)})
    assert has_element?(view, "#research-steps #step-find[data-status=running]")
    assert has_element?(view, "#research-steps[aria-busy=true]")

    send(view.pid, {:step, step("find", :ok, "Found on le.utah.gov")})
    assert has_element?(view, "#step-find[data-status=ok]", "Found on le.utah.gov")
    refute has_element?(view, "#step-find[data-status=running]")

    send(
      view.pid,
      {:receipt,
       %{
         id: 7,
         outcome: :kept,
         bill_title: "Sample Act",
         pledge_text: "x",
         possibly_related: false
       }}
    )

    assert has_element?(view, "#research-receipt-7 [data-role=outcome][data-outcome=kept]")
  end

  test "shows #research-done with the scorecard when the run finishes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/research")

    send(view.pid, {:step, step("grade", :ok)})

    send(
      view.pid,
      {:done,
       %{
         candidate: %{name: "Sample Legislator", party: "R", office: "Utah House", district: "3"},
         bars: %{promised: 80.0, proposed: nil, voted: 70.0},
         bars_used: [:voted, :promised],
         grade: "B",
         absence_rate: 0.11,
         receipts_count: 9,
         pledges_count: 4,
         industries: [%{industry: "Healthcare", total: 1000.0, share: 0.5}]
       }}
    )

    assert has_element?(view, "#research-done #research-money li[data-industry=Healthcare]")

    assert has_element?(view, "#research-done [data-role=grade][data-grade=B]")
    assert has_element?(view, "#research-done [data-bar=proposed][data-value=none]")
    assert has_element?(view, "#research-done", "Graded on 2 of 3 bars")
    assert has_element?(view, "#research-done", "11%")
    assert has_element?(view, "#research-steps[aria-busy=false]")
    assert has_element?(view, "#research-run", "not human-verified yet")
  end

  test "shows why a run stopped", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/research")

    send(view.pid, {:step, step("cache", :error, "No saved run")})
    send(view.pid, {:failed, %{reason: "no cached run"}})

    assert has_element?(view, "#research-failed", "no cached run")
    assert has_element?(view, "#step-cache[data-status=error]")
    refute has_element?(view, "#research-done")
  end
end

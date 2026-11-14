defmodule PolticoolWeb.CandidateLiveTest do
  use PolticoolWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Polticool.Ballot.{Pledge, Receipt}
  alias Polticool.Repo

  setup do
    seeds = Polticool.Seeds.hd62!()
    %{thurston: seeds.thurston, chappell: seeds.chappell}
  end

  test "header: grade tile, party label, unofficial-result badge", %{conn: conn, thurston: t} do
    {:ok, view, _html} = live(conn, ~p"/candidates/#{t.id}")

    assert has_element?(view, "h1", t.name)
    assert has_element?(view, "[data-role=grade]")
    assert has_element?(view, "h1 [data-role=party][data-party=R]")
    assert has_element?(view, "[data-role=unofficial-result]")
  end

  test "bars with long labels, the graded-on note and the three stats", %{conn: conn, thurston: t} do
    {:ok, view, _html} = live(conn, ~p"/candidates/#{t.id}")

    assert has_element?(view, "#scorecard-bars [data-bar=promised]", "specific promises")
    assert has_element?(view, "#scorecard-bars [data-bar=voted][data-value=none]", "No record")
    assert has_element?(view, "#scorecard-bars", "Graded on 2 of 3 bars")
    assert has_element?(view, "#stat-receipts", "receipts")
    assert has_element?(view, "#stat-untested", "untested")
    assert has_element?(view, "#stat-absence", "absent rate")
  end

  test "receipts are grouped by issue, including graded receipts on vague pledges", %{
    conn: conn,
    thurston: t
  } do
    {:ok, view, _html} = live(conn, ~p"/candidates/#{t.id}")

    assert has_element?(view, "#issue-group-education [data-role=outcome][data-outcome=kept]")
    # The Great Salt Lake pledge is vague, but its broken trap vote still counts.
    assert has_element?(view, "#issue-group-water [data-role=outcome][data-outcome=broken]")
    assert has_element?(view, "#issue-group-other [data-role=outcome][data-outcome=absent]")
    assert has_element?(view, "#vague-promises summary", "Vague promises (1)")
  end

  test "track-record receipts get their own, ungraded section", %{conn: conn, thurston: t} do
    refute_track_record = fn view -> refute has_element?(view, "#track-record") end
    {:ok, view, _html} = live(conn, ~p"/candidates/#{t.id}")
    refute_track_record.(view)

    pledge = Repo.get_by!(Pledge, candidate_id: t.id, issue: "income-tax")

    Repo.insert!(%Receipt{
      pledge_id: pledge.id,
      outcome: :kept,
      track_record: true,
      bill_title: "Old Bill"
    })

    {:ok, view, _html} = live(conn, ~p"/candidates/#{t.id}")
    assert has_element?(view, "#track-record", "context only, not graded")
    assert has_element?(view, "#track-record button", "Old Bill")
    refute has_element?(view, "#issue-group-education button", "Old Bill")
  end

  test "opens a receipt in the card and switches on tap", %{conn: conn, thurston: t} do
    {:ok, view, _html} = live(conn, ~p"/candidates/#{t.id}")

    assert has_element?(view, "#receipt-panel [data-role=receipt]")

    [target] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("button[id^=item-r]:not([aria-current])")
      |> Enum.take(1)
      |> Enum.map(&hd(LazyHTML.attribute(&1, "id")))

    item_id = String.replace_prefix(target, "item-", "")
    view |> element("##{target}") |> render_click()

    assert_patch(view, ~p"/candidates/#{t.id}?#{%{receipt: item_id}}")
    assert has_element?(view, "#receipt-panel #receipt-#{item_id}")
  end

  test "a challenger with promises only shows them as untested", %{conn: conn, chappell: c} do
    {:ok, view, _html} = live(conn, ~p"/candidates/#{c.id}")

    assert has_element?(view, "h1 [data-role=party][data-party=D]")
    assert has_element?(view, "[data-role=outcome][data-outcome=untested]")
    refute has_element?(view, "#vague-promises")
  end

  test "an unknown or malformed id goes back to the ballot", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/ballot"}}} = live(conn, ~p"/candidates/999999")
    assert {:error, {:live_redirect, %{to: "/ballot"}}} = live(conn, ~p"/candidates/abc")
  end

  test "compare and ballot pages link to the scorecard", %{conn: conn, thurston: t} do
    {:ok, view, _html} = live(conn, ~p"/races/hd62/compare")
    assert has_element?(view, "#scorecard-link-#{t.id}[href='/candidates/#{t.id}']")

    {:ok, view, _html} = live(conn, ~p"/ballot")
    assert has_element?(view, "#race-hd62 a[href='/candidates/#{t.id}']", t.name)
  end

  describe "money trail" do
    test "is left out when there are no contributions", %{conn: conn, thurston: t} do
      {:ok, view, _html} = live(conn, ~p"/candidates/#{t.id}")

      refute has_element?(view, "#money")
      refute has_element?(view, "[data-role=donor-tag]")
    end

    test "shows top industries and tags receipts on related issues", %{conn: conn, thurston: t} do
      for {industry, cents, i} <- [{"Energy & Mining", 500_000, 1}, {"Legal", 100_000, 2}] do
        Repo.insert!(%Polticool.Money.Contribution{
          candidate_id: t.id,
          donor_name: "Donor #{i}",
          normalized_donor: "donor #{i}",
          amount_cents: cents,
          industry: industry
        })
      end

      {:ok, view, _html} = live(conn, ~p"/candidates/#{t.id}")

      assert has_element?(view, "#money #money-bar li[data-industry='Energy & Mining']", "83%")
      assert has_element?(view, "#money-bar", "facts only, no implied cause")
      # Water receipts get the tag (Energy & Mining is related); education ones don't.
      assert has_element?(view, "#issue-group-water [data-role=donor-tag]", "Energy & Mining")
      refute has_element?(view, "#issue-group-education [data-role=donor-tag]")
    end
  end
end

defmodule PolticoolWeb.BriefingLiveTest do
  use PolticoolWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "the demo route shows Pohlman's JPEC briefing first, with no grade", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/races/judicial/pohlman")

    assert has_element?(view, "h1#judge-pohlman-title", "Justice Jill M. Pohlman")
    assert has_element?(view, "#jpec-pohlman", "Meets or Exceeds")
    assert has_element?(view, "#jpec-pohlman", "12–0")
    assert has_element?(view, "#jpec-pohlman", "8 of 8")
    assert has_element?(view, "#judge-pohlman", "96%")
    assert has_element?(view, "#judge-pohlman", "We don't grade judges")
    refute has_element?(view, "#judge-pohlman [data-role=grade]")

    assert has_element?(
             view,
             "#judge-pohlman [data-role=sources] a[href='https://judges.utah.gov']"
           )
  end

  test "the amendment decoder follows on the same page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/races/judicial/pohlman")

    assert has_element?(view, "h2#amendment-a-title", "Amendment A")
    assert has_element?(view, "#yes-a", "published online instead of in newspapers")
    assert has_element?(view, "#no-a", "stays")
    assert has_element?(view, "#amendment-a", "$1.4 million every 2 years")
    assert has_element?(view, "#amendment-a", "House 70-0-5 · Senate 29-0")
    assert has_element?(view, "#reps-a", "Jason E. Thompson")
    assert has_element?(view, "#reps-a", "Yea")
    assert has_element?(view, "#reps-a", "Norman K. Thurston")
    assert has_element?(view, "#reps-a", "Absent")
    assert has_element?(view, "#amendment-a [data-role=unofficial-result]")

    assert has_element?(
             view,
             "#amendment-a [data-role=sources] a[href*='svotes.jsp?sessionid=2025GS&voteid=852']"
           )
  end

  test "/amendments/a puts the amendment first", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/amendments/a")

    assert has_element?(view, "h1#amendment-a-title", "Amendment A")
    assert has_element?(view, "h2#judge-pohlman-title")
  end

  test "/amendments/b shows Amendment B with rep votes from the roll call", %{conn: conn} do
    alias Polticool.Repo
    alias Polticool.Ballot.{Bill, Vote, VotePosition}

    bill = Repo.insert!(%Bill{session: "2025GS", number: "SJR002", title: "S.J.R. 2"})

    third =
      Repo.insert!(%Vote{
        bill_id: bill.id,
        vote_id: "ls-2",
        house: "H",
        kind: :floor,
        date: ~D[2025-03-04]
      })

    earlier =
      Repo.insert!(%Vote{
        bill_id: bill.id,
        vote_id: "ls-1",
        house: "H",
        kind: :floor,
        date: ~D[2025-02-01]
      })

    Repo.insert!(%VotePosition{vote_id: third.id, legislator_code: "THURSNK", position: :yea})
    Repo.insert!(%VotePosition{vote_id: earlier.id, legislator_code: "THURSNK", position: :nay})

    {:ok, view, _html} = live(conn, ~p"/amendments/b")

    assert has_element?(view, "h1#amendment-b-title", "Amendment B")
    assert has_element?(view, "#yes-b", "60%")
    assert has_element?(view, "#amendment-b", "Senate 21-8-0 · House 55-17-3")
    # Latest House floor vote wins; Thompson has no position on record.
    assert has_element?(view, "#reps-b", "Norman K. Thurston")
    assert has_element?(view, "#reps-b", "Yea")
    assert has_element?(view, "#reps-b", "Not on record")
    assert has_element?(view, "#reps-a", "Absent")
  end

  test "an unknown briefing goes back to the ballot", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/ballot"}}} = live(conn, ~p"/races/judicial/nobody")
    assert {:error, {:live_redirect, %{to: "/ballot"}}} = live(conn, ~p"/amendments/z")
  end

  test "the ballot links to both briefings", %{conn: conn} do
    Polticool.Seeds.hd62!()
    {:ok, view, _html} = live(conn, ~p"/ballot")

    assert has_element?(view, "#brief-pohlman[href='/races/judicial/pohlman']", "Brief")
    assert has_element?(view, "#decode-amendment-a[href='/amendments/a']", "Decode")
    assert has_element?(view, "#decode-amendment-b[href='/amendments/b']", "Decode")
  end
end

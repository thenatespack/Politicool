defmodule Polticool.SeedsTest do
  use Polticool.DataCase, async: true

  alias Polticool.{Ballot, Repo, Seeds}
  alias Polticool.Ballot.{Candidate, Receipt}

  test "hd62!/0 seeds the race, every receipt outcome, and is idempotent" do
    rows = Seeds.hd62!()
    counts = {Repo.aggregate(Candidate, :count), Repo.aggregate(Receipt, :count)}
    assert Seeds.hd62!().thurston.id == rows.thurston.id
    assert {Repo.aggregate(Candidate, :count), Repo.aggregate(Receipt, :count)} == counts

    assert [%{key: "hd62", candidates: [_, _]}, %{key: "judicial-pohlman"}] =
             Ballot.list_races([]) |> Enum.sort_by(& &1.key)

    thurston = Ballot.get_candidate!(rows.thurston.id)
    receipts = Enum.flat_map(thurston.pledges, & &1.receipts)

    assert receipts |> Enum.map(& &1.outcome) |> Enum.sort() ==
             [:absent, :broken, :kept, :partial, :untested]

    assert Enum.any?(receipts, &(&1.outcome == :absent and &1.bill.number == "HJR010"))
    assert Ballot.scorecard(thurston).grade

    assert rows.pohlman.office =~ "Supreme Court"
    assert rows.amendment_a.number == "HJR010"
  end
end

defmodule Polticool.SeedsTest do
  use Polticool.DataCase, async: true

  import Ecto.Query

  alias Polticool.{Ballot, Repo, Seeds}
  alias Polticool.Ballot.{Bill, Candidate, Pledge, Receipt}

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
             [:broken, :kept, :partial, :untested]

    assert Ballot.scorecard(thurston).grade

    assert rows.pohlman.office =~ "Supreme Court"
    assert rows.amendment_a.number == "HJR010"
  end

  test "seeds no SAMPLE pledge and removes a pre-existing one with its receipts" do
    rows = Seeds.hd62!()

    old =
      Repo.insert!(%Pledge{
        candidate_id: rows.thurston.id,
        text: "SAMPLE (replace with a verified quote): support open, low-cost public notices",
        issue: "transparency",
        specific: true,
        source_kind: :site
      })

    Repo.insert!(%Receipt{pledge_id: old.id, outcome: :absent})

    Seeds.hd62!()

    refute Repo.get(Pledge, old.id)
    refute Repo.get_by(Receipt, pledge_id: old.id)
    assert Repo.all(from p in Pledge, where: like(p.text, "SAMPLE%")) == []
    assert Ballot.scorecard(Ballot.get_candidate!(rows.thurston.id)).grade
  end

  test "seeded bills store the sponsor as the legislator code" do
    Seeds.hd62!()

    for number <- ~w(HB0394 HB0231) do
      assert Repo.get_by!(Bill, number: number).prime_sponsor == "THURSNK"
    end
  end
end

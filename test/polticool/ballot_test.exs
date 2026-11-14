defmodule Polticool.BallotTest do
  use Polticool.DataCase, async: true

  alias Polticool.Repo
  alias Polticool.Ballot
  alias Polticool.Ballot.{Candidate, Pledge, Receipt, Bill, Vote, VotePosition}

  setup do
    cand =
      Repo.insert!(%Candidate{
        name: "A",
        party: "R",
        office: "House",
        district: "62",
        race_key: "hd62",
        incumbent: true
      })

    Repo.insert!(%Candidate{name: "B", office: "House", district: "62", race_key: "hd62"})
    %{cand: cand}
  end

  test "list_races groups candidates by race" do
    assert [%{key: "hd62", candidates: [_, _]}] = Ballot.list_races([])
  end

  test "schemas round trip and scorecard", %{cand: cand} do
    bill = Repo.insert!(%Bill{session: "2026GS", number: "HB0001", versions: [%{"v" => 1}]})

    vote =
      Repo.insert!(%Vote{
        bill_id: bill.id,
        vote_id: "1",
        house: "H",
        kind: :floor,
        tally: %{"yea" => 70}
      })

    Repo.insert!(%VotePosition{vote_id: vote.id, legislator_code: "THURN", position: :yea})
    p1 = Repo.insert!(%Pledge{candidate_id: cand.id, text: "x", specific: true})
    Repo.insert!(%Pledge{candidate_id: cand.id, text: "vague", specific: false})

    Repo.insert!(%Receipt{
      pledge_id: p1.id,
      bill_id: bill.id,
      vote_id: vote.id,
      outcome: :kept,
      confidence: :high
    })

    c = Ballot.get_candidate!(cand.id)
    assert Enum.any?(c.pledges, &match?(%{receipts: [%{outcome: :kept, bill: %Bill{}}]}, &1))
    card = Ballot.scorecard(c)
    assert card.bars_used == 3
    assert card.promised == 50.0
    assert card.voted == 100.0
    assert card.grade in ~w(A B C D F)
  end

  test "outcome enum rejects unknown values" do
    cs = Receipt.changeset(%Receipt{}, %{pledge_id: 1, outcome: "bogus"})
    assert %{outcome: _} = errors_on(cs)
  end

  test "no pledges yields nil grade" do
    c = Repo.insert!(%Candidate{name: "Z"})
    assert %{grade: nil, bars_used: 0} = Ballot.scorecard(c)
  end
end

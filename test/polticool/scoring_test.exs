defmodule Polticool.ScoringTest do
  use ExUnit.Case, async: true

  alias Polticool.Scoring

  defp r(kind, outcome, extra \\ %{}), do: Map.merge(%{kind: kind, outcome: outcome}, extra)

  test "outcome points" do
    assert Scoring.points(:kept) == 100
    assert Scoring.points(:partial) == 50
    assert Scoring.points(:broken) == 0
    assert Scoring.points(:untested) == nil
    assert Scoring.points(:absent) == nil
  end

  test "no receipts" do
    res = Scoring.score([])
    assert res.bars_used == []
    assert res.score == nil
    assert res.grade == nil
    assert res.absence_rate == nil
    assert res.bars == %{voted: nil, proposed: nil, promised: nil}
  end

  test "all three bars use 50/30/20 weights" do
    res = Scoring.score([r(:voted, :kept), r(:proposed, :partial), r(:promised, :broken)])
    assert res.bars_used == [:voted, :proposed, :promised]
    assert_in_delta res.score, 65.0, 1.0e-9
    assert res.grade == "D"
  end

  test "bar score averages scored receipts" do
    res = Scoring.score([r(:voted, :kept), r(:voted, :partial), r(:voted, :broken)])
    assert res.bars.voted == 50.0
  end

  test "missing bar redistributes proportionally" do
    # voted 100, proposed 0, promised missing -> (100*50 + 0*30) / 80
    res = Scoring.score([r(:voted, :kept), r(:proposed, :broken)])
    assert res.bars_used == [:voted, :proposed]
    assert_in_delta res.score, 62.5, 1.0e-9
    assert res.grade == "D"
  end

  test "single bar carries full weight" do
    res = Scoring.score([r(:promised, :kept)])
    assert res.bars_used == [:promised]
    assert res.score == 100.0
    assert res.grade == "A"
  end

  test "untested and absent are excluded; all excluded means no bars" do
    res = Scoring.score([r(:voted, :untested), r(:voted, :absent), r(:proposed, :untested)])
    assert res.bars_used == []
    assert res.grade == nil
    assert res.absence_rate == 1.0
  end

  test "excluded receipts do not change a bar" do
    res = Scoring.score([r(:voted, :kept), r(:voted, :absent), r(:voted, :untested)])
    assert res.bars.voted == 100.0
  end

  test "absence rate over voted receipts only" do
    res =
      Scoring.score([
        r(:voted, :kept),
        r(:voted, :broken),
        r(:voted, :absent),
        r(:voted, :untested),
        r(:proposed, :absent)
      ])

    assert_in_delta res.absence_rate, 1 / 3, 1.0e-9
  end

  test "grade cutoffs" do
    cases = [
      {100, "A"},
      {90, "A"},
      {89.9, "B"},
      {80, "B"},
      {79.9, "C"},
      {70, "C"},
      {69.9, "D"},
      {60, "D"},
      {59.9, "F"},
      {0, "F"}
    ]

    for {s, g} <- cases, do: assert(Scoring.grade(s) == g)
    assert Scoring.grade(nil) == nil
  end

  test "trap vote weight scales down influence" do
    res = Scoring.score([r(:voted, :kept), r(:voted, :broken, %{weight: 0.25})])
    assert_in_delta res.bars.voted, 80.0, 1.0e-9
  end

  test "accepts strings, ignores unknown values" do
    res =
      Scoring.score([
        %{kind: "voted", outcome: "Kept"},
        %{kind: "bogus", outcome: :kept},
        %{kind: :voted, outcome: "weird"}
      ])

    assert res.bars_used == [:voted]
    assert res.score == 100.0
  end
end

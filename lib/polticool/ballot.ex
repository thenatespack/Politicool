defmodule Polticool.Ballot do
  @moduledoc """
  Context for races, candidates, pledges, receipts and scorecards.
  """
  import Ecto.Query

  alias Polticool.Repo
  alias Polticool.Ballot.{Candidate, Race}

  @weights %{promised: 0.20, proposed: 0.30, voted: 0.50}

  @doc """
  Lists races with their candidates. `issues` (list of issue strings) orders
  races so those whose candidates have pledges on those issues come first.
  """
  def list_races(issues \\ []) do
    issues = List.wrap(issues)

    Candidate
    |> order_by([c], asc: c.office, desc: c.incumbent, asc: c.name)
    |> preload(:pledges)
    |> Repo.all()
    |> Enum.group_by(&(&1.race_key || "#{&1.office}-#{&1.district}"))
    |> Enum.map(fn {key, cands} ->
      first = List.first(cands)
      %Race{key: key, office: first.office, district: first.district, candidates: cands}
    end)
    |> Enum.sort_by(fn race -> {-issue_hits(race, issues), race.key} end)
  end

  defp issue_hits(_race, []), do: 0

  defp issue_hits(race, issues) do
    Enum.count(Enum.flat_map(race.candidates, & &1.pledges), &(&1.issue in issues))
  end

  @doc "Fetches a candidate with pledges -> receipts -> bill/vote preloaded."
  def get_candidate!(id) do
    Candidate
    |> Repo.get!(id)
    |> Repo.preload(pledges: [receipts: [:bill, :vote]])
  end

  @doc """
  Computes `%{promised, proposed, voted, score, grade, bars_used}`. Bars are 0..100
  or nil when there is no record; missing bars have their weight redistributed.
  """
  def scorecard(%Candidate{} = candidate) do
    pledges = Repo.preload(candidate, pledges: :receipts).pledges

    promised = ratio(Enum.count(pledges, & &1.specific), length(pledges))
    testable = Enum.filter(pledges, & &1.specific)

    proposed =
      ratio(
        Enum.count(testable, fn p ->
          Enum.any?(p.receipts, &(&1.bill_id && &1.confidence == :high))
        end),
        length(testable)
      )

    voted = voted_bar(Enum.flat_map(pledges, & &1.receipts))

    bars = %{promised: promised, proposed: proposed, voted: voted}
    used = for {k, v} <- bars, v != nil, do: k

    score =
      case used do
        [] ->
          nil

        _ ->
          total = Enum.sum(for k <- used, do: @weights[k])
          Enum.sum(for k <- used, do: bars[k] * @weights[k] / total)
      end

    grade = score && letter(score)

    Map.merge(bars, %{grade: grade, score: score, bars_used: length(used)})
  end

  defp voted_bar(receipts) do
    graded =
      Enum.filter(receipts, fn r ->
        r.vote_id && !r.track_record && r.confidence == :high &&
          r.outcome in [:kept, :partial, :broken]
      end)

    weight = fn r -> if r.trap, do: 0.5, else: 1.0 end
    value = fn r -> Map.fetch!(%{kept: 1.0, partial: 0.5, broken: 0.0}, r.outcome) end
    total = Enum.sum(Enum.map(graded, weight))

    if total == 0 do
      nil
    else
      Enum.sum(Enum.map(graded, &(value.(&1) * weight.(&1)))) / total * 100
    end
  end

  defp ratio(_n, 0), do: nil
  defp ratio(n, d), do: n / d * 100

  defp letter(s) when s >= 90, do: "A"
  defp letter(s) when s >= 80, do: "B"
  defp letter(s) when s >= 70, do: "C"
  defp letter(s) when s >= 60, do: "D"
  defp letter(_), do: "F"

  @doc "PubSub topic for live research of the given id."
  def research_topic(id), do: "research:#{id}"
end

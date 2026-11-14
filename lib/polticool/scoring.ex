defmodule Polticool.Scoring do
  @moduledoc """
  Pure rules engine: receipt outcomes -> 3 bars -> overall score -> A-F grade.

  Input is a list of plain maps/structs with `:kind` (`:promised | :proposed | :voted`)
  and `:outcome` (`:kept | :partial | :broken | :untested | :absent`). String values
  are accepted too. An optional numeric `:weight` (default 1.0) lets trap votes be
  weighted down.

  Rules (Decisions Log -> Scorecard):

    * Kept 100 / Partial 50 / Broken 0. Untested and Absent are excluded from scores.
    * Bars weighted Voted 50 / Proposed 30 / Promised 20. A bar with no scored
      receipts is missing and its weight is redistributed proportionally.
    * Grade cutoffs: A >= 90, B >= 80, C >= 70, D >= 60, else F.
    * Absence rate = absent / (absent + scored) among `:voted` receipts.
  """

  @points %{kept: 100, partial: 50, broken: 0}
  @weights %{voted: 50, proposed: 30, promised: 20}
  @kinds [:voted, :proposed, :promised]
  @outcomes [:kept, :partial, :broken, :untested, :absent]

  @doc "Points for an outcome, or nil when the outcome is excluded from scoring."
  def points(outcome), do: Map.get(@points, normalize(outcome, @outcomes))

  @doc "Bar weights."
  def weights, do: @weights

  @doc """
  Score a list of receipts. Returns `%{bars, bars_used, score, grade, absence_rate}`.
  `score`/`grade` are nil when no bar has any scored receipt.
  """
  @spec score([map()]) :: map()
  def score(receipts) when is_list(receipts) do
    rows =
      for r <- receipts,
          kind = normalize(Map.get(r, :kind), @kinds),
          outcome = normalize(Map.get(r, :outcome), @outcomes),
          do: {kind, outcome, weight(r)}

    bars = Map.new(@kinds, fn kind -> {kind, bar(rows, kind)} end)
    used = Enum.filter(@kinds, &(bars[&1] != nil))
    overall = overall(bars, used)

    %{
      bars: bars,
      bars_used: used,
      score: overall,
      grade: grade(overall),
      absence_rate: absence_rate(rows)
    }
  end

  @doc "Weighted average of bar scores over the bars present, redistributing missing weight."
  def overall(_bars, []), do: nil

  def overall(bars, used) do
    total = used |> Enum.map(&@weights[&1]) |> Enum.sum()
    Enum.sum(for k <- used, do: bars[k] * @weights[k]) / total
  end

  @doc "Letter grade for a numeric score (nil -> nil)."
  def grade(nil), do: nil
  def grade(s) when s >= 90, do: "A"
  def grade(s) when s >= 80, do: "B"
  def grade(s) when s >= 70, do: "C"
  def grade(s) when s >= 60, do: "D"
  def grade(_), do: "F"

  defp bar(rows, kind) do
    scored = for {^kind, o, w} <- rows, p = @points[o], w > 0, do: {p, w}

    case scored do
      [] ->
        nil

      _ ->
        total_w = scored |> Enum.map(&elem(&1, 1)) |> Enum.sum()
        Enum.sum(for {p, w} <- scored, do: p * w) / total_w
    end
  end

  defp absence_rate(rows) do
    voted = for {:voted, o, _} <- rows, o in [:kept, :partial, :broken, :absent], do: o

    case voted do
      [] -> nil
      _ -> Enum.count(voted, &(&1 == :absent)) / length(voted)
    end
  end

  defp weight(r) do
    case Map.get(r, :weight) do
      w when is_number(w) -> w
      _ -> 1.0
    end
  end

  defp normalize(v, allowed) when is_atom(v) and not is_nil(v), do: if(v in allowed, do: v)

  defp normalize(v, allowed) when is_binary(v),
    do: Enum.find(allowed, &(Atom.to_string(&1) == String.downcase(v)))

  defp normalize(_, _), do: nil
end

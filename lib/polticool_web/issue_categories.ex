defmodule PolticoolWeb.IssueCategories do
  @moduledoc """
  The four voter-facing issue groups (Decisions Log → UX) and the pledge
  issue slugs each one covers.

  Pledge slugs come from `Polticool.Pledges.issues/0` plus the hand-written
  seed slugs. Slugs not listed here fall into no group: they still count on
  a candidate's scorecard but aren't put first for any chosen issue.
  """

  @categories [
    %{
      id: "housing",
      title: "Housing & cost of living",
      short: "Housing",
      blurb: "Affordability, zoning, rent",
      slugs: ~w(housing economy cost-of-living)
    },
    %{
      id: "water",
      title: "Water & environment",
      short: "Water",
      blurb: "Great Salt Lake, air quality",
      slugs: ~w(environment water great-salt-lake air-quality)
    },
    %{
      id: "education",
      title: "Education & taxes",
      short: "Education & taxes",
      blurb: "School funding, income tax",
      slugs: ~w(education taxes income-tax)
    },
    %{
      id: "growth",
      title: "Growth, transit & health",
      short: "Growth",
      blurb: "I-15, transit, mental health access",
      slugs: ~w(transportation healthcare growth transit)
    }
  ]

  @ids Enum.map(@categories, & &1.id)

  @doc "All four groups, in display order."
  def all, do: @categories

  @doc "The group with this id, or nil."
  def get(id), do: Enum.find(@categories, &(&1.id == id))

  @doc "The group a pledge issue slug belongs to, or nil."
  def for_issue(slug), do: Enum.find(@categories, &(slug in &1.slugs))

  @doc "Pledge issue slugs covered by the given group ids."
  def slugs_for(ids), do: Enum.flat_map(ids, &(get(&1) || %{slugs: []}).slugs)

  @doc ~s|Parses the `issues` query param ("housing,water") into known ids, in display order.|
  def parse(param) when is_binary(param) do
    wanted = String.split(param, ",", trim: true)
    Enum.filter(@ids, &(&1 in wanted))
  end

  def parse(_), do: []

  @doc "Adds or removes `id` (unknown ids are ignored), keeping display order."
  def toggle(selected, id) when id in @ids do
    if id in selected,
      do: List.delete(selected, id),
      else: Enum.filter(@ids, &(&1 in [id | selected]))
  end

  def toggle(selected, _unknown), do: selected

  @doc "Query params for the ballot URL; empty when nothing is chosen."
  def to_params([]), do: %{}
  def to_params(ids), do: %{issues: Enum.join(ids, ",")}
end

defmodule PolticoolWeb.Briefings do
  @moduledoc """
  Down-ballot briefings: judicial retention and constitutional amendments.

  Facts are hand-entered from the board's Research doc ("3 · Research:
  Candidates, Market & Legal") and the Data & Tech Reference (the HJR 10
  roll call is marked verified there). Each briefing lists its sources. We
  don't grade judges or recommend votes; judges show JPEC's own evaluation.

  Move these into the database once the down-ballot ingest exists.
  """

  @hjr10_vote_url "https://le.utah.gov/DynaBill/svotes.jsp?sessionid=2025GS&voteid=852&house=H"

  @judges [
    %{
      slug: "pohlman",
      name: "Jill M. Pohlman",
      title: "Justice",
      court: "Utah Supreme Court",
      recommendation: "Meets or Exceeds",
      jpec_vote: "12–0",
      standards: "8 of 8",
      survey_recommend: "96%",
      sources: [
        {"2026 Voter Information Pamphlet", "https://vote.utah.gov"},
        {"Judicial Performance Evaluation Commission", "https://judges.utah.gov"}
      ]
    }
  ]

  @amendments [
    %{
      slug: "a",
      name: "Amendment A",
      bill: "H.J.R. 10 · 2025 General Session",
      summary: "Publish proposed constitutional amendments online instead of in newspapers.",
      yes_means:
        "Proposed constitutional amendments are published online instead of in newspapers.",
      no_means: "The requirement to publish proposed amendments in newspapers stays.",
      fiscal_impact: "Saves up to $1.4 million every 2 years",
      legislature: "House 70-0-5 · Senate 29-0",
      result: "Passing, about 60–40",
      reps: [
        %{name: "Jason E. Thompson", party: "R", district: "HD3", vote: "Yea"},
        %{name: "Norman K. Thurston", party: "R", district: "HD62", vote: "Absent"}
      ],
      sources: [
        {"le.utah.gov · H.J.R. 10", "https://le.utah.gov/~2025/bills/static/HJR010.html"},
        {"House roll call", @hjr10_vote_url},
        {"2026 Voter Information Pamphlet", "https://vote.utah.gov"}
      ]
    }
  ]

  def judges, do: @judges
  def amendments, do: @amendments

  def judge(slug), do: Enum.find(@judges, &(&1.slug == slug))
  def amendment(slug), do: Enum.find(@amendments, &(&1.slug == slug))
end

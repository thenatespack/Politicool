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
    },
    %{
      slug: "b",
      name: "Amendment B",
      bill: "S.J.R. 2 · 2025 General Session",
      summary: "Require 60% of the vote for citizen initiatives that raise taxes.",
      yes_means:
        "Citizen initiatives that create a new tax, expand a tax or raise a tax rate need at " <>
          "least 60% of the vote to pass.",
      no_means: "Those initiatives keep passing with a simple majority.",
      fiscal_impact: "Not entered yet · see the Voter Information Pamphlet",
      legislature: "Senate 21-8-0 · House 55-17-3",
      result: "Not entered yet",
      # Votes come from the imported roll call (LegiScan), not hand entry.
      rep_votes: %{session: "2025GS", number: "SJR002", house: "H"},
      reps: [
        %{name: "Jason E. Thompson", party: "R", district: "HD3", code: "THOMJA"},
        %{name: "Norman K. Thurston", party: "R", district: "HD62", code: "THURSNK"}
      ],
      sources: [
        {"le.utah.gov · S.J.R. 2", "https://le.utah.gov/~2025/bills/static/SJR002.html"},
        {"2026 Proposed Constitutional Amendments",
         "https://le.utah.gov/constitutionalAmendment/2026/constitutionalamendments.pdf"},
        {"2026 Voter Information Pamphlet", "https://vote.utah.gov"}
      ]
    }
  ]

  def judges, do: @judges
  def amendments, do: Enum.map(@amendments, &resolve_rep_votes/1)

  # Fill rep votes from the database roll call; "Not on record" when missing.
  defp resolve_rep_votes(%{rep_votes: %{session: s, number: n, house: h}} = a) do
    reps =
      for r <- a.reps do
        Map.put(r, :vote, vote_label(Polticool.Ballot.floor_position(s, n, h, r.code)))
      end

    %{a | reps: reps}
  end

  defp resolve_rep_votes(a), do: a

  defp vote_label(:yea), do: "Yea"
  defp vote_label(:nay), do: "Nay"
  defp vote_label(:absent), do: "Absent"
  defp vote_label(nil), do: "Not on record"

  def judge(slug), do: Enum.find(@judges, &(&1.slug == slug))
  def amendment(slug), do: Enum.find(amendments(), &(&1.slug == slug))
end

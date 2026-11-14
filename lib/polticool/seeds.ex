defmodule Polticool.Seeds do
  @moduledoc """
  Hand-written, idempotent fixtures for Utah House District 62 (plus the Pohlman
  retention and Amendment A rows) so the UI can be built against realistic data.

  Real facts (from the board's "3 · Research: Candidates, Market & Legal" doc and
  the ingested roll call): the candidates and their parties, Thurston's le code
  `THURSNK`, the 2025GS HJR 10 House vote 852 (70 yea, 0 nay, 5 absent, Thurston
  absent), Pohlman's JPEC numbers and Amendment A's description.

  Everything else is **SAMPLE** data and says so: pledge wording is lifted from the
  Research doc's key quotes but not yet verified, and placeholder rationales are
  prefixed `SAMPLE`. Replace before anything is shown publicly.

  Run with `mix run priv/repo/seeds.exs`. Safe to re-run.
  """

  import Ecto.Query

  alias Polticool.Repo
  alias Polticool.Ballot.{Bill, Candidate, Pledge, Receipt, Vote, VotePosition}

  @research_url "task-board://16/docs/19"
  @sample "SAMPLE (replace with verified data): "
  @hjr10_vote_url "https://le.utah.gov/DynaBill/svotes.jsp?sessionid=2025GS&voteid=852&house=H"

  @doc "Seeds HD62, Pohlman and Amendment A. Returns a map of the key rows."
  def hd62! do
    {:ok, rows} = Repo.transact(fn -> {:ok, seed()} end)
    rows
  end

  defp seed do
    thurston =
      upsert!(Candidate, [le_code: "THURSNK"], %{
        name: "Norman K. Thurston",
        party: "R",
        office: "Utah House",
        district: "62",
        race_key: "hd62",
        incumbent: true,
        result: "lost",
        result_status: "unofficial (canvass Nov 23)",
        site_url: "https://normthurston.com"
      })

    chappell =
      upsert!(Candidate, [race_key: "hd62", name: "David Chappell"], %{
        party: "D",
        office: "Utah House",
        district: "62",
        incumbent: false,
        result: "won",
        result_status: "unofficial (canvass Nov 23)",
        site_url: "https://davidforutah.com"
      })

    pohlman =
      upsert!(Candidate, [race_key: "judicial-pohlman"], %{
        name: "Jill M. Pohlman",
        office: "Utah Supreme Court (retention)",
        district: "Statewide",
        incumbent: true
      })

    hjr10 =
      upsert!(Bill, [session: "2025GS", number: "HJR010"], %{
        title: "Amendment A (H.J.R. 10): publish constitutional amendments online",
        provisions:
          "Publish proposed constitutional amendments online instead of in newspapers. " <>
            "House 70-0-5, Senate 29-0. Saves up to $1.4M every 2 years.",
        url: "https://le.utah.gov/~2025/bills/static/HJR010.html"
      })

    hjr10_vote =
      upsert!(Vote, [bill_id: hjr10.id, vote_id: "852", house: "H"], %{
        kind: :floor,
        action: "House passed",
        url: @hjr10_vote_url,
        tally: %{"yea" => 70, "nay" => 0, "absent" => 5}
      })

    upsert!(VotePosition, [vote_id: hjr10_vote.id, legislator_code: "THURSNK"], %{
      legislator_name: "Thurston, N.",
      position: :absent
    })

    hb394 =
      upsert!(Bill, [session: "2026GS", number: "HB0394"], %{
        title: "Veterinary Amendments",
        prime_sponsor: "THURSNK",
        url: "https://le.utah.gov/Session/2026/bills/static/HB0394.html"
      })

    hb231 =
      upsert!(Bill, [session: "2026GS", number: "HB0231"], %{
        title: "Restaurant Tax Repeal Amendments",
        prime_sponsor: "THURSNK",
        url: "https://le.utah.gov/Session/2026/bills/static/HB0231.html"
      })

    remove_placeholder_pledges!(thurston)

    # Thurston: pledges + one receipt per outcome
    tax =
      pledge!(
        thurston,
        "income-tax",
        true,
        :site,
        "Reduced the Income Tax Rate for the 6th Year in a Row to 4.45%"
      )

    gsl =
      pledge!(thurston, "great-salt-lake", false, :news, "The Great Salt Lake needs more water")

    receipt!(tax, %{
      outcome: :kept,
      confidence: :high,
      vote_position: :yea,
      bill_id: hb394.id,
      bill_title: hb394.title,
      rationale: @sample <> "placeholder kept receipt; bill is not tax-related."
    })

    receipt!(tax, %{
      outcome: :partial,
      confidence: :medium,
      bill_id: hb231.id,
      bill_title: hb231.title,
      rationale: @sample <> "placeholder partial receipt."
    })

    receipt!(gsl, %{
      outcome: :broken,
      confidence: :low,
      trap: true,
      rationale: @sample <> "placeholder broken receipt (trap vote, down-weighted)."
    })

    receipt!(gsl, %{
      outcome: :untested,
      rationale: @sample <> "no related floor vote found yet."
    })

    # Chappell: promises only
    for {issue, text} <- [
          {"great-salt-lake", "Declare a State Emergency to Save the Great Salt Lake"},
          {"education", "Provide Free School Meals"},
          {"housing", "I will work with the Governor to declare a Housing Emergency"}
        ] do
      pledge!(chappell, issue, true, :site, text)
    end

    # Pohlman: retention, track record only
    jpec =
      pledge!(
        pohlman,
        "judicial-retention",
        false,
        :news,
        "JPEC: 12-0 Meets or Exceeds, 8/8 standards, 96% recommend retention"
      )

    receipt!(jpec, %{
      outcome: :untested,
      track_record: true,
      source_url: @research_url,
      rationale:
        "Real data from the Research doc (JPEC evaluation). Judges are not graded on pledges."
    })

    %{
      thurston: thurston,
      chappell: chappell,
      pohlman: pohlman,
      amendment_a: hjr10,
      hjr10_vote: hjr10_vote
    }
  end

  # Earlier versions seeded a "SAMPLE (replace with a verified quote): ..." pledge
  # (#937). Seeds only upsert, so delete it (and its receipts) from existing DBs.
  defp remove_placeholder_pledges!(candidate) do
    ids =
      Repo.all(
        from p in Pledge,
          where: p.candidate_id == ^candidate.id and like(p.text, "SAMPLE%"),
          select: p.id
      )

    Repo.delete_all(from r in Receipt, where: r.pledge_id in ^ids)
    Repo.delete_all(from p in Pledge, where: p.id in ^ids)
  end

  defp pledge!(candidate, issue, specific, kind, text) do
    upsert!(Pledge, [candidate_id: candidate.id, text: text], %{
      issue: issue,
      specific: specific,
      source_kind: kind,
      source_url: candidate.site_url,
      rubric_hits: %{"sample" => true}
    })
  end

  defp receipt!(pledge, attrs) do
    upsert!(Receipt, [pledge_id: pledge.id, outcome: attrs.outcome], Map.delete(attrs, :outcome))
  end

  # Finds a row by `keys`, inserting it if missing, then applies `attrs`.
  defp upsert!(schema, keys, attrs) do
    row = Repo.one(from s in schema, where: ^keys, limit: 1) || struct(schema, keys)

    row
    |> schema.changeset(Map.merge(attrs, Map.new(keys)))
    |> Repo.insert_or_update!()
  end
end

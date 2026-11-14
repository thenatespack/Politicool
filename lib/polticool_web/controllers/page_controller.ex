defmodule PolticoolWeb.PageController do
  use PolticoolWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  # Dev-only UI kit (routed under dev_routes in the router)
  def ui(conn, _params) do
    render(conn, :ui, page_title: "UI kit", receipt_samples: receipt_samples())
  end

  # Fictional SAMPLE receipts covering the card's states. Never real candidates.
  defp receipt_samples do
    alias Polticool.Ballot.{Bill, Candidate, Pledge, Receipt, Vote}

    candidate = %Candidate{name: "Sample Candidate", party: "R", le_code: "SAMPLC"}
    retrieved = ~U[2026-11-14 16:00:00Z]

    bill = %Bill{
      session: "2026GS",
      number: "HB0000",
      title: "Sample Water Infrastructure Amendments",
      prime_sponsor: "SAMPLC",
      versions: [%{"subVersion" => "0"}, %{"subVersion" => "1"}]
    }

    kept = %Receipt{
      outcome: :kept,
      confidence: :high,
      rationale: "Rule: prime sponsor + voted yea",
      verified: true,
      trap: true,
      quote: "Sample quote: the lake needs more water.",
      bill_summary:
        "Sample summary. Funds water-conservation projects and sets reporting rules. Every sentence is cited to the bill text.",
      vote_position: :yea,
      retrieved_at: retrieved,
      citations: [%{"title" => "Sample bill text", "url" => "https://example.com/bill"}],
      bill: bill,
      vote: %Vote{
        house: "H",
        kind: :floor,
        action: "House/ passed 3rd reading",
        tally: %{"yea" => 70, "nay" => 0, "absent" => 5},
        date: ~D[2026-03-04],
        url: "https://example.com/roll-call"
      }
    }

    kept_pledge = %Pledge{
      text: kept.quote,
      source_kind: :news,
      source_url: "https://www.example.com/news/water",
      archive_url: "https://web.archive.org/web/2026/https://example.com/news/water",
      quoted_at: ~D[2026-10-12],
      retrieved_at: retrieved,
      rubric_hits: %{
        "measurable_outcome" => false,
        "mechanism" => false,
        "timeframe" => false,
        "within_office_power" => true
      }
    }

    absent = %Receipt{
      outcome: :absent,
      quote: "Sample quote: cut the income tax rate.",
      vote_position: :absent,
      track_record: false,
      retrieved_at: retrieved,
      bill: %{bill | number: "HJR010", title: "Sample Publication Amendments", prime_sponsor: nil},
      vote: %Vote{
        house: "H",
        kind: :floor,
        tally: %{"yea" => 70, "nay" => 0, "absent" => 5},
        date: ~D[2025-02-26]
      }
    }

    absent_pledge = %Pledge{
      text: absent.quote,
      source_kind: :site,
      source_url: "https://example.com/platform",
      retrieved_at: retrieved,
      rubric_hits: %{
        "measurable_outcome" => true,
        "mechanism" => true,
        "timeframe" => false,
        "within_office_power" => true
      }
    }

    untested = %Receipt{outcome: :untested, quote: "Sample quote: declare a housing emergency."}
    untested_pledge = %Pledge{text: untested.quote, source_kind: :filing, retrieved_at: retrieved}

    [
      {"sample-kept", kept, kept_pledge, "Sample · Water"},
      {"sample-absent", absent, absent_pledge, "Sample · Education & taxes"},
      {"sample-untested", untested, untested_pledge, "Sample · Housing"}
    ]
    |> Enum.map(fn {id, receipt, pledge, label} ->
      %{id: id, receipt: receipt, pledge: pledge, candidate: candidate, label: label}
    end)
  end
end

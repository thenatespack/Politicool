defmodule PolticoolWeb.ReceiptComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import PolticoolWeb.ReceiptComponents

  alias Polticool.Ballot.{Bill, Candidate, Pledge, Receipt, Vote}

  defp candidate, do: %Candidate{name: "Sample Candidate", party: "R", le_code: "SAMPLC"}

  defp pledge(attrs \\ %{}) do
    struct!(
      %Pledge{
        text: "Sample pledge.",
        source_kind: :news,
        source_url: "https://www.example.com/news/water",
        archive_url: "https://web.archive.org/web/2026/https://example.com/news/water",
        quoted_at: ~D[2026-10-12],
        retrieved_at: ~U[2026-11-14 16:00:00Z],
        rubric_hits: %{
          "measurable_outcome" => false,
          "mechanism" => false,
          "timeframe" => false,
          "within_office_power" => true
        }
      },
      attrs
    )
  end

  defp full_receipt(attrs \\ %{}) do
    struct!(
      %Receipt{
        outcome: :kept,
        confidence: :high,
        rationale: "Rule: prime sponsor + voted yea",
        verified: true,
        trap: true,
        quote: "Sample quote.",
        bill_summary: "Sample summary.",
        vote_position: :yea,
        retrieved_at: ~U[2026-11-14 16:00:00Z],
        citations: [
          %{"title" => "Bill text", "url" => "https://example.com/bill"},
          %{"title" => "Bad link", "url" => "javascript:alert(1)"}
        ],
        bill: %Bill{
          session: "2026GS",
          number: "HB0023",
          title: "Sample Amendments",
          prime_sponsor: "SAMPLC",
          versions: [%{"subVersion" => "0"}, %{"subVersion" => "1"}]
        },
        vote: %Vote{
          house: "H",
          kind: :floor,
          action: "House/ passed 3rd reading",
          tally: %{"yea" => 70, "nay" => 0, "absent" => 5},
          date: ~D[2026-03-04],
          url: "https://example.com/roll-call"
        }
      },
      attrs
    )
  end

  defp render_card(receipt, pledge \\ pledge()) do
    assigns = %{receipt: receipt, pledge: pledge, candidate: candidate()}

    rendered_to_string(~H"""
    <.receipt_card
      id="r"
      receipt={@receipt}
      pledge={@pledge}
      candidate={@candidate}
      label="HD62 · Water"
    />
    """)
    |> LazyHTML.from_fragment()
  end

  defp q(doc, selector), do: LazyHTML.query(doc, selector)
  defp count(doc, selector), do: doc |> q(selector) |> Enum.count()

  defp text(doc, selector),
    do: doc |> q(selector) |> LazyHTML.text() |> String.replace(~r/\s+/, " ") |> String.trim()

  describe "steps and DOM hooks" do
    test "renders all three steps with only the quote step visible" do
      doc = render_card(full_receipt())

      assert count(doc, "article#r[data-role=receipt]") == 1
      assert count(doc, "#r-step-1:not([hidden])") == 1
      assert count(doc, "#r-step-2[hidden]") == 1
      assert count(doc, "#r-step-3[hidden]") == 1
    end

    test "has the agreed 'See the bill' / 'See the vote' buttons wired to the next step" do
      doc = render_card(full_receipt())

      assert text(doc, "#r-next-1") =~ "See the bill"
      assert text(doc, "#r-next-2") =~ "See the vote"
      assert [js1] = doc |> q("#r-next-1") |> LazyHTML.attribute("phx-click")
      assert js1 =~ "#r-step-2"
      assert [js2] = doc |> q("#r-next-2") |> LazyHTML.attribute("phx-click")
      assert js2 =~ "#r-step-3"
    end

    test "shows the outcome badge (data-role=outcome) on the vote step" do
      doc = render_card(full_receipt())

      assert doc |> q("#r-step-3 [data-role=outcome]") |> LazyHTML.attribute("data-outcome") ==
               ["kept"]

      assert count(doc, "#r-step-1 [data-role=outcome]") == 0
    end

    test "show_receipt_step/3 hides the other steps and focuses the new heading" do
      js = show_receipt_step("r", 2) |> Jason.encode!()

      assert js =~ ~s|"to":"#r-step-1"|
      assert js =~ ~s|"to":"#r-step-3"|
      assert js =~ ~s|"to":"#r-step-2-heading"|
    end
  end

  describe "quote step" do
    test "shows every rubric criterion, including the ones not met" do
      doc = render_card(full_receipt())

      hits =
        for li <- q(doc, "#r-rubric li"),
            do:
              {hd(LazyHTML.attribute(li, "data-rubric")), hd(LazyHTML.attribute(li, "data-hit"))}

      assert hits == [
               {"measurable_outcome", "false"},
               {"mechanism", "false"},
               {"timeframe", "false"},
               {"within_office_power", "true"}
             ]
    end

    test "has a chip for every rubric key pledge extraction produces" do
      keys = Polticool.Pledges.rubric_keys()
      doc = render_card(full_receipt(), pledge(%{rubric_hits: Map.new(keys, &{&1, true})}))

      chips = for li <- q(doc, "#r-rubric li"), do: hd(LazyHTML.attribute(li, "data-rubric"))
      assert Enum.sort(chips) == Enum.sort(keys)
    end

    test "badges news quotes as a secondary source, and only those" do
      assert count(render_card(full_receipt()), "#r-step-1 [data-role=secondary-source]") == 1

      site = render_card(full_receipt(), pledge(%{source_kind: :site}))
      assert count(site, "[data-role=secondary-source]") == 0
    end

    test "cites the source with its date, archive and retrieved-on date" do
      doc = render_card(full_receipt())

      assert count(doc, "#r-step-1 a[href='https://www.example.com/news/water']") == 1
      assert count(doc, "#r-step-1 a[href^='https://web.archive.org']") == 1
      assert text(doc, "#r-step-1 [data-role=sources]") =~ "retrieved Nov 14, 2026"
    end
  end

  describe "bill step" do
    test "formats the bill number and session and shows the sponsor role and versions" do
      doc = render_card(full_receipt())

      assert text(doc, "#r-step-2") =~ "H.B. 23 · 2026 General Session"
      assert text(doc, "#r-sponsor-role") == "Prime sponsor"
      assert text(doc, "#r-step-2") =~ "Original → 1st Substitute"
      assert count(doc, "#r-trap") == 1

      assert count(doc, "#r-step-2 a[href='https://le.utah.gov/~2026/bills/static/HB0023.html']") ==
               1
    end

    test "says so when there is no related bill" do
      doc = render_card(%Receipt{outcome: :untested, quote: "Sample."})

      assert count(doc, "#r-no-bill") == 1
      assert count(doc, "#r-no-vote") == 1
    end
  end

  describe "vote step" do
    test "shows the position and the human-verified mark" do
      doc = render_card(full_receipt())

      assert text(doc, "#r-position") == "Yea"
      assert count(doc, "#r-step-3 [data-role=verified]") == 1
      assert count(doc, "#r-unverified") == 0
    end

    test "only says a vote counts toward the grade when it actually does" do
      assert text(render_card(full_receipt()), "#r-timing") == "No · counts toward the grade"

      assert text(
               render_card(full_receipt(%{outcome: :absent, vote_position: :absent})),
               "#r-timing"
             ) ==
               "No"

      assert text(render_card(full_receipt(%{track_record: true})), "#r-timing") ==
               "Yes · context only, not graded"
    end

    test "discloses unverified receipts as AI-matched" do
      doc = render_card(full_receipt(%{verified: false}))

      assert count(doc, "[data-role=verified]") == 0
      assert count(doc, "#r-unverified") == 1
    end

    test "falls back to the receipt's source_url for the roll-call link" do
      receipt =
        full_receipt(%{
          vote: %Vote{house: "H", kind: :floor},
          source_url: "https://le.utah.gov/vote"
        })

      doc = render_card(receipt)

      assert count(doc, "#r-step-3 a[href='https://le.utah.gov/vote']") == 1
    end

    test "only links http(s) citations" do
      doc = render_card(full_receipt())

      assert count(doc, "#r-step-3 a[href='https://example.com/bill']") == 1
      assert count(doc, "a[href^='javascript']") == 0
    end

    test "leaves out the sources line when there is nothing to cite" do
      doc =
        render_card(
          %Receipt{outcome: :untested, quote: "Sample."},
          pledge(%{source_url: nil, archive_url: nil, quoted_at: nil, retrieved_at: nil})
        )

      assert count(doc, "[data-role=sources]") == 0
    end
  end

  describe "formatters" do
    test "format_bill_number/1" do
      assert format_bill_number("HB0023") == "H.B. 23"
      assert format_bill_number("HJR010") == "H.J.R. 10"
      assert format_bill_number("SB0001") == "S.B. 1"
      assert format_bill_number("odd") == "odd"
    end

    test "session_label/1" do
      assert session_label("2026GS") == "2026 General Session"
      assert session_label("2025S1") == "2025 1st Special Session"
      assert session_label("other") == "other"
    end
  end
end

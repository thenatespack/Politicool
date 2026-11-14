defmodule Polticool.MatchingTest do
  use Polticool.DataCase, async: false

  alias Polticool.{Anthropic, Ballot, Matching, Repo}
  alias Polticool.Ballot.{Bill, Candidate, Pledge, Receipt, Vote, VotePosition}

  @provision "Directs counties to approve residential building permits within 60 days."

  # Stubs both calls: Sonnet (has a document) returns cited/uncited text, Haiku the tool call.
  defp stub(opts) do
    cited? = Keyword.get(opts, :cited, true)
    input = Keyword.fetch!(opts, :input)

    Req.Test.stub(Anthropic, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      body = Jason.decode!(raw)

      if body["model"] == Anthropic.sonnet() do
        assert Enum.any?(hd(body["messages"])["content"], &(&1["type"] == "document"))
        refute Map.has_key?(body, "output_config")
        citations = if cited?, do: [citation()], else: []

        # Real Citations replies interleave uncited connector text with cited spans.
        Req.Test.json(conn, %{
          "content" => [
            %{"type" => "text", "text" => "The bill advances the pledge. It says "},
            %{"type" => "text", "text" => "permits within 60 days", "citations" => citations},
            %{"type" => "text", "text" => ", which is the pledged reform."}
          ]
        })
      else
        refute inspect(body["messages"]) =~ "document"

        Req.Test.json(conn, %{
          "content" => [%{"type" => "tool_use", "name" => "record_match", "input" => input}]
        })
      end
    end)
  end

  defp citation,
    do: %{
      "type" => "char_location",
      "cited_text" => @provision,
      "document_title" => "HB1",
      "document_index" => 0,
      "start_char_index" => 10,
      "end_char_index" => 80
    }

  defp input(rel, conf),
    do: %{
      "relation" => rel,
      "confidence" => conf,
      "rationale" => "Because.",
      "quote" => @provision
    }

  setup do
    {:ok, c} =
      %Candidate{} |> Candidate.changeset(%{name: "T", le_code: "THURSNK"}) |> Repo.insert()

    {:ok, p} =
      %Pledge{}
      |> Pledge.changeset(%{
        candidate_id: c.id,
        text: "Cut permit waits to 60 days.",
        specific: true,
        quoted_at: ~D[2026-06-01]
      })
      |> Repo.insert()

    {:ok, bill} =
      %Bill{}
      |> Bill.changeset(%{
        session: "2025GS",
        number: "HB1",
        title: "Permits",
        provisions: @provision,
        url: "https://le.utah.gov/HB1"
      })
      |> Repo.insert()

    %{c: c, p: p, bill: bill}
  end

  defp add_vote(bill, date, position) do
    {:ok, v} =
      %Vote{}
      |> Vote.changeset(%{
        bill_id: bill.id,
        vote_id: "V#{System.unique_integer([:positive])}",
        kind: :floor,
        date: date,
        tally: %{"yea" => 50, "nay" => 20}
      })
      |> Repo.insert()

    Repo.insert!(%VotePosition{vote_id: v.id, legislator_code: "THURSNK", position: position})
    v
  end

  test "high-confidence match with later vote is graded kept, with citations", %{
    c: c,
    p: p,
    bill: bill
  } do
    add_vote(bill, ~D[2026-09-01], :yea)
    stub(input: input("advances", "high"))

    assert {:ok, %{receipts: [r], rejected: []}} = Matching.match_pledge(p, [bill])
    assert r.outcome == :kept and r.confidence == :high
    refute r.verified, "AI-matched receipts must not be marked human-verified"
    refute r.track_record
    assert r.vote_position == :yea and r.tally == "50-20-0"
    assert [%{"cited_text" => @provision, "start_char_index" => 10}] = r.citations
    assert r.quote == @provision
    assert Ballot.scorecard(c).voted == 100.0
  end

  test "votes before the pledge are track record and not graded", %{c: c, p: p, bill: bill} do
    add_vote(bill, ~D[2025-02-01], :nay)
    stub(input: input("advances", "high"))

    assert {:ok, %{receipts: [r]}} = Matching.match_pledge(p, [bill])
    assert r.track_record and r.outcome == :broken
    assert Ballot.scorecard(c).voted == nil
  end

  test "medium confidence is possibly related and ungraded", %{c: c, p: p, bill: bill} do
    add_vote(bill, ~D[2026-09-01], :yea)
    stub(input: input("possibly_related", "medium"))

    assert {:ok, %{receipts: [r]}} = Matching.match_pledge(p, [bill])
    assert r.outcome == :untested and Receipt.possibly_related?(r)
    assert Ballot.scorecard(c).voted == nil
  end

  test "interleaved uncited connector text still yields a cited receipt", %{p: p, bill: bill} do
    stub(input: input("advances", "high"))

    assert {:ok, %{receipts: [r], rejected: []}} = Matching.match_pledge(p, [bill])
    assert [%{"cited_text" => @provision}] = r.citations
    assert r.quote == @provision
  end

  test "uncited verdicts and unrelated bills produce no receipt", %{p: p, bill: bill} do
    stub(cited: false, input: input("advances", "high"))
    assert {:ok, %{receipts: [], rejected: [{_, :uncited}]}} = Matching.match_pledge(p, [bill])

    stub(input: input("unrelated", "high"))
    assert {:ok, %{receipts: [], rejected: [{_, :unrelated}]}} = Matching.match_pledge(p, [bill])
    assert Repo.aggregate(Receipt, :count) == 0
  end

  test "hallucinated quote falls back to cited text; rerun replaces", %{p: p, bill: bill} do
    stub(input: Map.put(input("advances", "high"), "quote", "invented"))
    assert {:ok, %{receipts: [%{quote: @provision}]}} = Matching.match_pledge(p, [bill])
    assert {:ok, _} = Matching.match_pledge(p, [bill])
    assert Repo.aggregate(Receipt, :count) == 1
  end

  test "match_candidate reports progress per pledge", %{c: c, bill: bill} do
    stub(input: input("advances", "high"))
    test_pid = self()

    assert {:ok, %{pledges: 1, receipts: [_]}} =
             Matching.match_candidate(c, bills: [bill], on_progress: &send(test_pid, &1))

    assert_received {:pledge, %Pledge{}, %{receipts: [_]}}
  end
end

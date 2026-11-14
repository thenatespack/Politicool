defmodule Polticool.Matching do
  @moduledoc """
  Matches pledges to bills and votes and stores the result as receipts.
  "No source = no claim."

  Citations cannot be combined with structured output (the API returns 400), so each
  pledge/bill pair takes two calls:

    1. **Match (Sonnet)** gets the bill text as a citations-enabled document and
       returns a plain-text verdict. `Anthropic.verify_citations/1` must pass, so an
       answer with no citations at all is rejected and produces no receipt.
    2. **Format (Haiku)** gets only the verified text (no documents) and fills a forced
       tool call: `relation`, `confidence`, `rationale`, `quote`. The receipt's
       `citations` (`cited_text` plus location) come from step 1, never from Haiku.

  ## Grading rules

    * Only `confidence: :high` matches get a graded outcome (`:kept`, `:broken` or
      `:absent`, from the legislator's floor vote and whether the bill advances or
      contradicts the pledge). Medium and low matches are stored with outcome
      `:untested`, so they are "Possibly related" (`Receipt.possibly_related?/1`)
      and excluded from the scorecard.
    * A vote dated before the pledge is `track_record: true`. It is shown but not
      graded.
    * `relation: unrelated` produces no receipt.

  The legislator is identified by `candidate.le_code` (from
  `Polticool.Legislators.fetch_roster/1`; Thurston is THURSNK), matched against
  `vote_positions.legislator_code`.

  ## Return shapes

    * `match_pledge(pledge, bills, opts)` returns
      `{:ok, %{receipts: [%Receipt{}], rejected: [{bill_id, reason}]}}`.
      Reasons: `:no_text`, `:uncited`, `:unrelated`, `{:error, term}`.
      Re-running replaces the pledge's earlier receipts for the same bills.
    * `match_candidate(candidate, opts)` returns
      `{:ok, %{receipts: [...], rejected: [...], pledges: n}}`. Only specific pledges
      are matched. Pass `on_progress: fn {:pledge, pledge, result} -> ... end` to
      report each step.

  Opts: `:pledge_date` (override), `:on_progress` (candidate only), `:bills`
  (candidate only; default all bills with text).
  """

  import Ecto.Query

  alias Polticool.{Anthropic, Repo}
  alias Polticool.Ballot.{Bill, Candidate, Pledge, Receipt, Vote, VotePosition}

  @relations ~w(advances contradicts possibly_related unrelated)
  @confidences ~w(high medium low)
  @max_chars 150_000

  @doc "Matches one pledge against `bills`. See the moduledoc for the return shape."
  def match_pledge(%Pledge{} = pledge, bills, opts \\ []) when is_list(bills) do
    pledge = Repo.preload(pledge, :candidate)

    results =
      Enum.map(bills, fn bill ->
        {bill, match_bill(pledge, Repo.preload(bill, :votes), opts)}
      end)

    receipts = for {_, {:ok, r}} <- results, do: r
    rejected = for {bill, {:rejected, reason}} <- results, do: {bill.id, reason}

    {:ok, %{receipts: receipts, rejected: rejected}}
  end

  @doc "Matches all of a candidate's specific pledges. See the moduledoc."
  def match_candidate(%Candidate{} = candidate, opts \\ []) do
    pledges =
      Repo.all(
        from p in Pledge, where: p.candidate_id == ^candidate.id and p.specific, order_by: p.id
      )

    bills =
      Keyword.get_lazy(opts, :bills, fn ->
        Repo.all(from b in Bill, where: not is_nil(b.provisions), order_by: b.id)
      end)

    progress = Keyword.get(opts, :on_progress, fn _ -> :ok end)

    acc =
      Enum.reduce(pledges, %{receipts: [], rejected: []}, fn pledge, acc ->
        {:ok, res} = match_pledge(pledge, bills, opts)
        progress.({:pledge, pledge, res})
        %{receipts: acc.receipts ++ res.receipts, rejected: acc.rejected ++ res.rejected}
      end)

    {:ok, Map.put(acc, :pledges, length(pledges))}
  end

  defp match_bill(_pledge, %Bill{provisions: p}, _opts) when p in [nil, ""],
    do: {:rejected, :no_text}

  defp match_bill(pledge, bill, opts) do
    with {:ok, verified} <- run_match(pledge, bill),
         {:ok, fmt} <- run_format(pledge, verified) do
      case fmt.relation do
        "unrelated" -> {:rejected, :unrelated}
        _ -> {:ok, store(pledge, bill, verified, fmt, opts)}
      end
    else
      {:error, :uncited, _} -> {:rejected, :uncited}
      {:error, reason} -> {:rejected, {:error, reason}}
    end
  end

  # Step 1: Sonnet + Citations, plain text.
  defp run_match(pledge, bill) do
    text = String.slice(bill_text(bill), 0, @max_chars)

    messages = [
      %{
        role: "user",
        content: [
          Anthropic.document(text, title: "#{bill.number} #{bill.title}", cache: false),
          %{
            type: "text",
            text:
              "Pledge: \"#{pledge.text}\"\n\nDoes this bill advance, contradict, or only loosely " <>
                "relate to the pledge, or is it unrelated? Answer in a few sentences and support " <>
                "every claim by citing the bill text. If it is unrelated, say so."
          }
        ]
      }
    ]

    with {:ok, body} <-
           Anthropic.chat(messages,
             model: Anthropic.sonnet(),
             system:
               "You compare campaign pledges to legislation. Only state what the bill text supports.",
             max_tokens: 1024,
             temperature: 0
           ) do
      Anthropic.verify_citations(body)
    end
  end

  # Step 2: Haiku, no documents, forced tool call.
  defp run_format(pledge, cited_blocks) do
    verdict = Enum.map_join(cited_blocks, "", & &1["text"])

    messages = [
      %{
        role: "user",
        content:
          "Pledge: \"#{pledge.text}\"\n\nVerified analysis:\n#{verdict}\n\nRecord the result."
      }
    ]

    result =
      Anthropic.chat(messages,
        model: Anthropic.haiku(),
        system:
          "Convert the analysis to structured data. relation: advances (bill carries out the pledge), " <>
            "contradicts (bill works against it), possibly_related (loosely related), unrelated. " <>
            "confidence is high only when the analysis is unambiguous. Do not add facts. " <>
            "Call record_match exactly once.",
        tools: [tool()],
        max_tokens: 512,
        temperature: 0
      )

    with {:ok, %{"content" => content}} <- result do
      case Enum.find(content, &(&1["type"] == "tool_use" and &1["name"] == "record_match")) do
        %{"input" => %{"relation" => rel, "confidence" => conf} = input}
        when rel in @relations and conf in @confidences ->
          {:ok,
           %{
             relation: rel,
             confidence: confidence_atom(conf),
             rationale: input["rationale"] || verdict,
             quote: input["quote"]
           }}

        _ ->
          {:error, :no_tool_output}
      end
    end
  end

  # Explicit map: String.to_existing_atom/1 fails in dev/mix tasks when the module
  # defining the atom hasn't been loaded yet.
  defp confidence_atom("high"), do: :high
  defp confidence_atom("medium"), do: :medium
  defp confidence_atom("low"), do: :low

  defp store(pledge, bill, cited_blocks, fmt, opts) do
    citations =
      cited_blocks |> Enum.flat_map(&(&1["citations"] || [])) |> Enum.map(&clean_citation/1)

    cited_texts = Enum.map(citations, & &1["cited_text"])

    # Keep Haiku's quote only if it is really inside a cited passage.
    quote =
      if is_binary(fmt.quote) and Enum.any?(cited_texts, &String.contains?(&1, fmt.quote)),
        do: fmt.quote,
        else: List.first(cited_texts)

    vote = latest_floor_vote(bill)
    position = vote && position_for(vote, pledge.candidate)
    track_record = !!vote and before_pledge?(vote, pledge, opts)

    outcome =
      if fmt.confidence == :high and fmt.relation in ["advances", "contradicts"],
        do: outcome(fmt.relation, position),
        else: :untested

    attrs = %{
      pledge_id: pledge.id,
      bill_id: bill.id,
      vote_id: vote && vote.id,
      outcome: outcome,
      confidence: fmt.confidence,
      rationale: fmt.rationale,
      citations: citations,
      # `verified` means a person hand-checked the receipt (shown as "Human-verified").
      # AI matches are citation-checked, not human-checked, so they start unverified.
      verified: false,
      track_record: track_record,
      quote: quote,
      source_url: bill.url,
      bill_title: "#{bill.number} #{bill.title}",
      vote_position: position,
      tally: vote && tally(vote),
      retrieved_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    Repo.delete_all(from r in Receipt, where: r.pledge_id == ^pledge.id and r.bill_id == ^bill.id)

    %Receipt{} |> Receipt.changeset(attrs) |> Repo.insert!()
  end

  defp outcome(_rel, nil), do: :untested
  defp outcome(_rel, :absent), do: :absent
  defp outcome("advances", :yea), do: :kept
  defp outcome("advances", :nay), do: :broken
  defp outcome("contradicts", :yea), do: :broken
  defp outcome("contradicts", :nay), do: :kept

  defp clean_citation(c) do
    Map.take(c, ~w(type cited_text document_title document_index start_char_index end_char_index))
  end

  defp bill_text(bill) do
    [
      "#{bill.number}: #{bill.title}",
      bill.prime_sponsor && "Prime sponsor: #{bill.prime_sponsor}",
      bill.provisions
    ]
    |> Enum.filter(& &1)
    |> Enum.join("\n\n")
  end

  defp latest_floor_vote(bill) do
    bill.votes
    |> Enum.filter(&(&1.kind == :floor))
    |> Enum.sort_by(&(&1.date && Date.to_gregorian_days(&1.date)), :desc)
    |> List.first()
  end

  defp position_for(%Vote{id: id}, %{le_code: code}) when is_binary(code) do
    Repo.one(
      from p in VotePosition,
        where: p.vote_id == ^id and p.legislator_code == ^code,
        select: p.position
    )
  end

  defp position_for(_, _), do: nil

  defp before_pledge?(%Vote{date: nil}, _, _), do: false

  defp before_pledge?(%Vote{date: date}, pledge, opts) do
    case Keyword.get_lazy(opts, :pledge_date, fn -> pledge_date(pledge) end) do
      nil -> false
      pd -> Date.compare(date, pd) == :lt
    end
  end

  defp pledge_date(%Pledge{quoted_at: %Date{} = d}), do: d
  defp pledge_date(%Pledge{retrieved_at: %DateTime{} = dt}), do: DateTime.to_date(dt)
  defp pledge_date(%Pledge{inserted_at: %DateTime{} = dt}), do: DateTime.to_date(dt)
  defp pledge_date(_), do: nil

  defp tally(%Vote{tally: t}) when map_size(t) > 0 do
    Enum.map_join(~w(yea nay absent), "-", &to_string(t[&1] || 0))
  end

  defp tally(_), do: nil

  defp tool do
    %{
      name: "record_match",
      description: "Record the structured match result.",
      input_schema: %{
        type: "object",
        required: ["relation", "confidence", "rationale", "quote"],
        properties: %{
          relation: %{type: "string", enum: @relations},
          confidence: %{type: "string", enum: @confidences},
          rationale: %{type: "string"},
          quote: %{type: "string", description: "A passage from the analysis, copied exactly."}
        }
      }
    }
  end
end

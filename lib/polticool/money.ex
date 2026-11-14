defmodule Polticool.Money do
  @moduledoc """
  Campaign-finance "money trail": facts about who funded a candidate.

  Pipeline: parse CSV (or hand-entered rows) -> normalize donor names -> tag
  industries with Claude Haiku (fixed list, batched) -> store -> aggregate.

  Presentation rule: these are disclosed facts only. Never describe a donation
  as a cause of, or reward for, any vote.

  ## Assumed export format

  disclosures.utah.gov (Advanced Search -> Download Data by Year) could not be
  confirmed programmatically (the site is a JS app; no stable export URL was
  discoverable). `parse_csv/1` therefore accepts a header-driven CSV and
  matches columns case-insensitively against aliases:

    * donor: `Contributor`, `Contributor Name`, `Name`, `Donor`
    * amount: `Amount`, `Transaction Amount`
    * date: `Date`, `Transaction Date`, `Contribution Date`
    * report: `Report`, `Report ID`, `Report Name`
    * external id: `TRAN_ID` (makes re-imports idempotent per candidate)
    * filer: `PCC` ("Last, First"); type: `TRAN_TYPE`; also `INKIND`, `LOAN`, `AMENDS`

  ## Real export (candidate committees, "Download Data by Year")

  Header: `FILED,PCC,REPORT,TRAN_ID,TRAN_TYPE,TRAN_DATE,TRAN_AMT,INKIND,LOAN,AMENDS,NAME,...`.
  Every file holds every Utah candidate, so pass `filer: "Thurston, Norman"`.
  When a `TRAN_TYPE` column exists:

    * only `Contribution` rows are kept (expenditures are dropped);
    * in-kind contributions (`INKIND` = X) are kept: they are disclosed gifts;
    * loans (`LOAN` = X) are dropped: a loan is repaid money, not a donation;
    * negative amounts (refunds) are kept as negative cents, so donor and
      industry totals are net of refunds;
    * a row whose `TRAN_ID` is named in another row's `AMENDS` is superseded
      and dropped.

  Dates may be `YYYY-MM-DD` or `M/D/YYYY`; amounts may include `$` and commas.
  If the real export differs, add aliases in `@aliases`.
  """

  import Ecto.Query

  alias Polticool.{Anthropic, Repo}
  alias Polticool.Ballot.Candidate
  alias Polticool.Money.Contribution

  @industries [
    "Real Estate & Construction",
    "Energy & Mining",
    "Healthcare",
    "Finance & Insurance",
    "Agriculture",
    "Technology",
    "Education",
    "Retail & Hospitality",
    "Legal",
    "Labor Unions",
    "Political Committees & Parties",
    "Transportation",
    "Telecom & Media",
    "Individual / Retired",
    "Other"
  ]

  @aliases %{
    donor: ~w(contributor contributorname contributor_name name donor donorname),
    amount: ~w(amount transactionamount tran_amt),
    date: ~w(date transactiondate contributiondate tran_date),
    report: ~w(report reportid reportname),
    external_id: ~w(tran_id),
    filer: ~w(pcc),
    type: ~w(tran_type),
    inkind: ~w(inkind),
    loan: ~w(loan),
    amends: ~w(amends)
  }

  @batch_size 40

  def industries, do: @industries

  # ---- parsing ----

  @doc """
  Parses CSV text into `[%{donor_name, amount_cents, date, report_id, external_id}]`.

  Option `:filer` keeps only rows whose `PCC` equals it (case-insensitive).
  See the moduledoc for the contribution-only filtering of the real export.
  """
  def parse_csv(text, opts \\ []) when is_binary(text) do
    filer = opts[:filer] && String.downcase(String.trim(opts[:filer]))

    case text |> String.trim_leading("﻿") |> csv_rows() do
      [] ->
        []

      [header | rows] ->
        idx = column_index(header)

        rows =
          for row <- rows,
              donor = cell(row, idx.donor),
              donor != "",
              keep_row?(row, idx, filer) do
            %{
              donor_name: donor,
              amount_cents: parse_amount(cell(row, idx.amount)),
              date: parse_date(cell(row, idx.date)),
              report_id: blank_nil(cell(row, idx.report)),
              external_id: blank_nil(cell(row, idx.external_id)),
              amends: blank_nil(cell(row, idx.amends))
            }
          end
          |> Enum.reject(&is_nil(&1.amount_cents))

        superseded = for %{amends: a} <- rows, a, into: MapSet.new(), do: a

        rows
        |> Enum.reject(&(&1.external_id && &1.external_id in superseded))
        |> Enum.map(&Map.delete(&1, :amends))
    end
  end

  defp keep_row?(row, idx, filer) do
    (is_nil(filer) or is_nil(idx.filer) or String.downcase(cell(row, idx.filer)) == filer) and
      (is_nil(idx.type) or
         (String.downcase(cell(row, idx.type)) == "contribution" and
            String.upcase(cell(row, idx.loan)) != "X"))
  end

  @doc """
  Guesses the export's `PCC` ("Last, First") from a candidate name:
  "Norman K. Thurston" -> "Thurston, Norman".
  """
  def filer_name(%Candidate{name: name}) do
    case String.split(name) do
      [only] -> only
      [first | rest] -> "#{List.last(rest)}, #{first}"
    end
  end

  defp column_index(header) do
    keys = Enum.map(header, &(&1 |> String.downcase() |> String.replace(~r/[^a-z_]/, "")))

    Map.new(@aliases, fn {field, names} ->
      {field, Enum.find_index(keys, &(&1 in names))}
    end)
  end

  defp cell(_row, nil), do: ""
  defp cell(row, i), do: row |> Enum.at(i, "") |> String.trim()

  defp blank_nil(""), do: nil
  defp blank_nil(s), do: s

  defp parse_amount(s) do
    clean = s |> String.replace(["$", ","], "") |> String.trim()

    {neg, clean} =
      case clean do
        "(" <> rest -> {true, String.trim_trailing(rest, ")")}
        "-" <> rest -> {true, rest}
        other -> {false, other}
      end

    case Decimal.parse(clean) do
      {d, ""} ->
        cents = d |> Decimal.mult(100) |> Decimal.round(0) |> Decimal.to_integer()
        if neg, do: -cents, else: cents

      _ ->
        nil
    end
  end

  defp parse_date(s) do
    case Date.from_iso8601(s) do
      {:ok, d} ->
        d

      _ ->
        with [m, d, y] <- String.split(String.slice(s, 0, 10), "/"),
             {mi, ""} <- Integer.parse(m),
             {di, ""} <- Integer.parse(d),
             {yi, ""} <- Integer.parse(y),
             {:ok, date} <- Date.new(yi, mi, di) do
          date
        else
          _ -> nil
        end
    end
  end

  # Minimal RFC 4180 parser (quoted fields, escaped quotes, embedded newlines).
  defp csv_rows(text) do
    text |> String.to_charlist() |> do_csv([], [], [], false) |> Enum.reverse()
  end

  defp do_csv([], field, row, rows, _q), do: finish_row(field, row, rows)
  defp do_csv([?", ?" | t], field, row, rows, true), do: do_csv(t, [?" | field], row, rows, true)
  defp do_csv([?" | t], field, row, rows, true), do: do_csv(t, field, row, rows, false)
  defp do_csv([?" | t], [], row, rows, false), do: do_csv(t, [], row, rows, true)
  defp do_csv([c | t], field, row, rows, true), do: do_csv(t, [c | field], row, rows, true)

  defp do_csv([?, | t], field, row, rows, false),
    do: do_csv(t, [], [field_s(field) | row], rows, false)

  defp do_csv([?\r | t], field, row, rows, false), do: do_csv(t, field, row, rows, false)

  defp do_csv([?\n | t], field, row, rows, false),
    do: do_csv(t, [], [], finish_row(field, row, rows), false)

  defp do_csv([c | t], field, row, rows, false), do: do_csv(t, [c | field], row, rows, false)

  defp finish_row([], [], rows), do: rows
  defp finish_row(field, row, rows), do: [Enum.reverse([field_s(field) | row]) | rows]

  defp field_s(field), do: field |> Enum.reverse() |> List.to_string()

  # ---- normalization ----

  @suffixes ~w(inc llc llp lp ltd co corp corporation company pllc pc)

  @doc """
  Normalizes a donor name for grouping: "Doe, Jane Q." -> "jane q doe";
  "Acme Homes, L.L.C." -> "acme homes".
  """
  def normalize_donor(name) when is_binary(name) do
    base =
      name
      |> String.downcase()
      |> String.replace(".", "")
      |> String.replace("&", " and ")
      |> String.replace(~r/[^a-z0-9,\s]/, " ")

    base =
      case String.split(base, ",", parts: 2) do
        [last, first] ->
          # "last, first" is a person unless the tail is just a company suffix
          if String.trim(first) in @suffixes, do: last, else: "#{first} #{last}"

        [only] ->
          only
      end

    base
    |> String.split()
    |> Enum.reject(&(&1 in @suffixes))
    |> Enum.join(" ")
  end

  # ---- industry tagging ----

  @doc """
  Tags each normalized donor name with an industry from `industries/0` via Haiku.
  Returns `%{normalized_donor => industry}`. Unknown/failed -> "Other".
  """
  def tag_industries(donors) when is_list(donors) do
    donors
    |> Enum.uniq()
    |> Enum.chunk_every(@batch_size)
    |> Enum.reduce(%{}, fn batch, acc -> Map.merge(acc, tag_batch(batch)) end)
  end

  defp tag_batch(batch) do
    tool = %{
      name: "record_industries",
      description: "Record the industry for each donor.",
      input_schema: %{
        type: "object",
        properties: %{
          tags: %{
            type: "array",
            items: %{
              type: "object",
              properties: %{
                donor: %{type: "string"},
                industry: %{type: "string", enum: @industries}
              },
              required: ["donor", "industry"]
            }
          }
        },
        required: ["tags"]
      }
    }

    prompt =
      "Classify each campaign donor into exactly one industry from the allowed list. " <>
        "Use \"Individual / Retired\" for private persons with no evident employer, " <>
        "and \"Other\" when unsure. Do not guess beyond the name.\n\nDonors:\n" <>
        Enum.map_join(batch, "\n", &"- #{&1}")

    result =
      Anthropic.chat([%{role: "user", content: prompt}],
        model: Anthropic.haiku(),
        tools: [tool],
        max_tokens: 4096,
        temperature: 0
      )

    tagged =
      case result do
        {:ok, %{"content" => content}} ->
          for %{"type" => "tool_use", "input" => %{"tags" => tags}} <- content,
              %{"donor" => d, "industry" => i} <- tags,
              i in @industries,
              into: %{},
              do: {d, i}

        _ ->
          %{}
      end

    Map.new(batch, &{&1, Map.get(tagged, &1, "Other")})
  end

  # ---- import ----

  @doc """
  Imports parsed rows (see `parse_csv/1`) for a candidate: normalizes, tags,
  and replaces that candidate's previous rows with the same `:source_url`
  (idempotent re-import). Options: `:source_url`. Returns `{:ok, count}`.
  """
  def import_rows(%Candidate{id: cid}, rows, opts \\ []) do
    source = Keyword.get(opts, :source_url)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows = Enum.map(rows, &Map.put(&1, :normalized_donor, normalize_donor(&1.donor_name)))
    tags = rows |> Enum.map(& &1.normalized_donor) |> tag_industries()

    entries =
      for r <- rows do
        %{
          candidate_id: cid,
          donor_name: r.donor_name,
          normalized_donor: r.normalized_donor,
          amount_cents: r.amount_cents,
          date: r[:date],
          industry: Map.fetch!(tags, r.normalized_donor),
          source_url: source,
          report_id: r[:report_id],
          external_id: r[:external_id],
          retrieved_at: now,
          inserted_at: now,
          updated_at: now
        }
      end

    Repo.transaction(fn ->
      if source do
        Repo.delete_all(
          from c in Contribution,
            where: c.candidate_id == ^cid and c.source_url == ^source and is_nil(c.external_id)
        )
      end

      # Rows with a TRAN_ID upsert on (candidate_id, external_id), so repeats within
      # or across files update in place; rows without one are plain inserts.
      {with_id, without_id} = Enum.split_with(entries, & &1.external_id)
      with_id = Enum.uniq_by(with_id, & &1.external_id)

      for chunk <- Enum.chunk_every(with_id, 500) do
        Repo.insert_all(Contribution, chunk,
          on_conflict:
            {:replace,
             ~w(donor_name normalized_donor amount_cents date industry source_url report_id retrieved_at updated_at)a},
          conflict_target: [:candidate_id, :external_id]
        )
      end

      without_id |> Enum.chunk_every(500) |> Enum.each(&Repo.insert_all(Contribution, &1))

      length(with_id) + length(without_id)
    end)
  end

  @doc "Imports CSV text. See `import_rows/3`."
  def import_csv(candidate, text, opts \\ []),
    do: import_rows(candidate, parse_csv(text, Keyword.take(opts, [:filer])), opts)

  @doc """
  Loads hand-entered fallback donors from JSON:
  `{"donors": [{"donor_name": "...", "amount": 500.0, "date": "2026-01-05",
  "report_id": "..."}]}`.
  """
  def import_json(candidate, json, opts \\ []) when is_binary(json) do
    %{"donors" => donors} = Jason.decode!(json)

    rows =
      for d <- donors do
        %{
          donor_name: d["donor_name"],
          amount_cents: d["amount"] |> to_string() |> parse_amount(),
          date: d["date"] && parse_date(d["date"]),
          report_id: d["report_id"]
        }
      end

    import_rows(candidate, rows, opts)
  end

  # ---- aggregation ----

  @doc "Net `%{count, cents}` of all contributions stored for the candidate."
  def total_cents(%Candidate{id: cid}) do
    {count, cents} =
      Repo.one(
        from c in Contribution,
          where: c.candidate_id == ^cid,
          select: {count(c.id), coalesce(sum(c.amount_cents), 0)}
      )

    %{count: count, cents: Decimal.to_integer(Decimal.new(cents))}
  end

  @doc """
  Top `n` industries by total contributed to the candidate.
  Returns `[%{industry, total, share}]`, `total` in dollars (float) and
  `share` a 0..1 fraction of all of the candidate's contributions.
  """
  def top_industries(%Candidate{id: cid}, n \\ 5) do
    rows =
      from(c in Contribution,
        where: c.candidate_id == ^cid,
        group_by: c.industry,
        select: {c.industry, sum(c.amount_cents)},
        order_by: [desc: sum(c.amount_cents), asc: c.industry]
      )
      |> Repo.all()
      |> Enum.map(fn {i, cents} -> {i || "Other", Decimal.to_integer(cents)} end)

    grand = rows |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    rows
    |> Enum.take(n)
    |> Enum.map(fn {industry, cents} ->
      %{
        industry: industry,
        total: cents / 100,
        share: if(grand > 0, do: cents / grand, else: 0.0)
      }
    end)
  end
end

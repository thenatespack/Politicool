defmodule Mix.Tasks.Polticool.ImportMoney do
  @shortdoc "Imports campaign contributions (CSV or hand-entered JSON) for a candidate"

  @moduledoc """
  Imports contributions for a candidate and tags donor industries with Haiku.

      mix polticool.import_money --candidate "Thurston" path/to/export.csv
      mix polticool.import_money --candidate "Chappell" priv/data/money_fallback.json
      mix polticool.import_money --candidate Thurston priv/data/PCC-2025.csv priv/data/PCC-2026.csv
      mix polticool.import_money --candidate Chappell "priv/data/PCC-202[56].csv"

  Several files and quoted globs are accepted. `.csv` files use the
  disclosures.utah.gov yearly export (see `Polticool.Money`); the real exports
  hold every Utah candidate, so rows are filtered to the candidate's `PCC`
  (derived from the name, e.g. "Thurston, Norman"; override with `--filer`) and
  to contributions (in-kind kept; loans and expenditures dropped; refunds kept
  as negatives). `.json` files use the hand-entered fallback format (see
  `priv/data/money_fallback.sample.json`).

  Options:

    * `--candidate` - substring of the candidate name (required, must match one)
    * `--filer` - the export's `PCC` value, e.g. "Thurston, Norman" (default: derived)
    * `--source-url` - provenance recorded on each row (default: disclosures.utah.gov)

  Needs `ANTHROPIC_API_KEY` for tagging; without it donors are tagged "Other"
  (re-run the same command later with the key set to tag them). Rows with a
  `TRAN_ID` are upserted per candidate, so re-imports are idempotent.
  """
  use Mix.Task

  import Ecto.Query

  @default_source "https://disclosures.utah.gov/Search/AdvancedSearch"

  @impl Mix.Task
  def run(argv) do
    {opts, args, _} =
      OptionParser.parse(argv,
        strict: [candidate: :string, source_url: :string, filer: :string]
      )

    {paths, needle} =
      case {args, opts[:candidate]} do
        {[_ | _], needle} when is_binary(needle) -> {expand(args), needle}
        _ -> Mix.raise("usage: mix polticool.import_money --candidate NAME FILE.(csv|json)...")
      end

    Mix.Task.run("app.start")

    candidate =
      case Polticool.Repo.all(
             from c in Polticool.Ballot.Candidate, where: ilike(c.name, ^"%#{needle}%")
           ) do
        [c] -> c
        [] -> Mix.raise("no candidate matches #{inspect(needle)}")
        many -> Mix.raise("ambiguous: #{Enum.map_join(many, ", ", & &1.name)}")
      end

    filer = opts[:filer] || Polticool.Money.filer_name(candidate)
    import_opts = [source_url: opts[:source_url] || @default_source, filer: filer]

    for path <- paths do
      text = File.read!(path)

      {:ok, count} =
        if Path.extname(path) == ".json",
          do: Polticool.Money.import_json(candidate, text, import_opts),
          else: Polticool.Money.import_csv(candidate, text, import_opts)

      Mix.shell().info("#{path}: #{count} contributions for #{candidate.name}")
    end

    total = Polticool.Money.total_cents(candidate)
    dollars = :erlang.float_to_binary(total.cents / 100, decimals: 2)
    Mix.shell().info("Total for #{candidate.name}: #{total.count} contributions, $#{dollars}")

    for %{industry: i, total: t, share: s} <- Polticool.Money.top_industries(candidate, 5) do
      Mix.shell().info("  #{i}: $#{:erlang.float_to_binary(t, decimals: 2)} (#{round(s * 100)}%)")
    end
  end

  defp expand(args) do
    args
    |> Enum.flat_map(fn a ->
      case Path.wildcard(a) do
        [] -> Mix.raise("no files match #{a}")
        files -> Enum.sort(files)
      end
    end)
    |> Enum.uniq()
  end
end

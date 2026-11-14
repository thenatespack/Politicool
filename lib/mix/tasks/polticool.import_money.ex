defmodule Mix.Tasks.Polticool.ImportMoney do
  @shortdoc "Imports campaign contributions (CSV or hand-entered JSON) for a candidate"

  @moduledoc """
  Imports contributions for a candidate and tags donor industries with Haiku.

      mix polticool.import_money --candidate "Thurston" path/to/export.csv
      mix polticool.import_money --candidate "Chappell" priv/data/money_fallback.json

  `.csv` files use the disclosures.utah.gov yearly export (see `Polticool.Money`);
  `.json` files use the hand-entered fallback format (see
  `priv/data/money_fallback.sample.json`).

  Options:

    * `--candidate` - substring of the candidate name (required, must match one)
    * `--source-url` - provenance recorded on each row (default: disclosures.utah.gov)

  Needs `ANTHROPIC_API_KEY` for tagging; without it donors are tagged "Other".
  Re-importing the same source URL replaces that candidate's rows from it.
  """
  use Mix.Task

  import Ecto.Query

  @default_source "https://disclosures.utah.gov/Search/AdvancedSearch"

  @impl Mix.Task
  def run(argv) do
    {opts, args, _} =
      OptionParser.parse(argv, strict: [candidate: :string, source_url: :string])

    {path, needle} =
      case {args, opts[:candidate]} do
        {[path], needle} when is_binary(needle) -> {path, needle}
        _ -> Mix.raise("usage: mix polticool.import_money --candidate NAME FILE.(csv|json)")
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

    text = File.read!(path)
    import_opts = [source_url: opts[:source_url] || @default_source]

    result =
      if Path.extname(path) == ".json",
        do: Polticool.Money.import_json(candidate, text, import_opts),
        else: Polticool.Money.import_csv(candidate, text, import_opts)

    {:ok, count} = result
    Mix.shell().info("Imported #{count} contributions for #{candidate.name}")

    for %{industry: i, total: t, share: s} <- Polticool.Money.top_industries(candidate, 5) do
      Mix.shell().info("  #{i}: $#{:erlang.float_to_binary(t, decimals: 2)} (#{round(s * 100)}%)")
    end
  end
end

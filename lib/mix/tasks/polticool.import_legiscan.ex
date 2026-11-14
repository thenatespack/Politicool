defmodule Mix.Tasks.Polticool.ImportLegiscan do
  @shortdoc "Imports Utah bills, roll calls and vote positions from LegiScan datasets"

  @moduledoc """
  Imports LegiScan weekly datasets into bills, votes and vote_positions.

      mix polticool.import_legiscan
      mix polticool.import_legiscan --session 2026GS --session 2025GS
      mix polticool.import_legiscan --zip path/to/dataset.zip
      mix polticool.import_legiscan --session 2026GS --force
      mix polticool.import_legiscan --strict
      mix polticool.import_legiscan --refresh-roster

  Without `--zip`, needs `LEGISCAN_API_KEY` and costs 1 query (getDatasetList)
  plus 1 per session whose dataset hash changed since the last import.
  `--zip` imports a manually downloaded dataset zip and makes no API calls.
  Default sessions: 2026GS and 2025GS.

  LegiScan people are mapped to legislator codes by chamber + district (confirmed
  by last name) using the committed roster snapshot `priv/data/legislators.json`;
  `--refresh-roster` tries live le.utah.gov first. Voters who cannot be mapped have
  their positions skipped; everything else is imported and the unmapped people are
  listed (fix them in `priv/data/legiscan_people.json`, then re-run). `--strict`
  aborts the whole import instead, importing nothing.

  Data: LegiScan API by LegiScan LLC, CC BY 4.0 (https://legiscan.com/legiscan).
  """
  use Mix.Task

  alias Polticool.LegiScan.ImportRunner

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [
          session: :keep,
          zip: :keep,
          force: :boolean,
          strict: :boolean,
          refresh_roster: :boolean
        ]
      )

    Mix.Task.run("app.start")

    ImportRunner.run(
      sessions: Keyword.get_values(opts, :session),
      zips: Keyword.get_values(opts, :zip),
      force: opts[:force] || false,
      strict: opts[:strict] || false,
      refresh_roster: opts[:refresh_roster] || false
    )
  end
end

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

  alias Polticool.LegiScan.Import

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

    sessions =
      case Keyword.get_values(opts, :session) do
        [] -> ["2026GS", "2025GS"]
        l -> l
      end

    case Keyword.get_values(opts, :zip) do
      [] ->
        report(Import.import_sessions(sessions, import_opts(opts)))

      zips ->
        for zip <- zips do
          Mix.shell().info("#{zip}:")
          report({:ok, [{"zip", Import.import_zip(zip, import_opts(opts)) |> unwrap()}]})
        end
    end
  end

  defp import_opts(opts),
    do: [
      force: opts[:force] || false,
      strict: opts[:strict] || false,
      refresh_roster: opts[:refresh_roster] || false
    ]

  defp unwrap({:ok, stats}), do: stats
  defp unwrap({:error, _} = err), do: err

  defp report({:ok, results}) do
    for {session, result} <- results do
      case result do
        {:error, reason} ->
          fail(reason)

        :unchanged ->
          Mix.shell().info("#{session}: unchanged (hash match), skipped download")

        stats ->
          {unmapped, stats} = Map.pop(stats, :unmapped, [])
          Mix.shell().info("#{session}: #{inspect(stats)}")
          report_unmapped(session, unmapped, stats)
      end
    end
  end

  defp report({:error, reason}), do: fail(reason)

  defp report_unmapped(_session, [], _stats), do: :ok

  defp report_unmapped(session, unmapped, stats) do
    if Enum.any?(unmapped, &(&1.name =~ "Thurston")) do
      Mix.shell().error(
        "!!! WARNING: THURSNK (Norman K. Thurston) could not be mapped. " <>
          "His votes were NOT imported. Add his people_id to priv/data/legiscan_people.json."
      )
    end

    Mix.shell().info(
      "#{session}: #{length(unmapped)} unmapped LegiScan people, " <>
        "#{stats.positions_skipped} vote positions skipped " <>
        "(add people_id => code to priv/data/legiscan_people.json and re-run):\n" <>
        format_people(unmapped)
    )
  end

  defp format_people(people),
    do: Enum.map_join(people, "\n", &"  #{&1.people_id} #{&1.name} (#{&1.role} #{&1.district})")

  defp fail({:unmapped_people, people}) do
    Mix.raise(
      "--strict: unmapped LegiScan people, nothing imported " <>
        "(add people_id => code to priv/data/legiscan_people.json):\n" <> format_people(people)
    )
  end

  defp fail(reason), do: Mix.raise("LegiScan import failed: #{inspect(reason)}")
end

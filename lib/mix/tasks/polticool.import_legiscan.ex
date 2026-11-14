defmodule Mix.Tasks.Polticool.ImportLegiscan do
  @shortdoc "Imports Utah bills, roll calls and vote positions from LegiScan datasets"

  @moduledoc """
  Imports LegiScan weekly datasets into bills, votes and vote_positions.

      mix polticool.import_legiscan
      mix polticool.import_legiscan --session 2026GS --session 2025GS
      mix polticool.import_legiscan --zip path/to/dataset.zip
      mix polticool.import_legiscan --session 2026GS --force

  Without `--zip`, needs `LEGISCAN_API_KEY` and costs 1 query (getDatasetList)
  plus 1 per session whose dataset hash changed since the last import.
  `--zip` imports a manually downloaded dataset zip and makes no API calls.
  Default sessions: 2026GS and 2025GS. Fails, listing them, if any voting
  person cannot be mapped to a legislator code (add them to
  `priv/data/legiscan_people.json`).

  Data: LegiScan API by LegiScan LLC, CC BY 4.0 (https://legiscan.com/legiscan).
  """
  use Mix.Task

  alias Polticool.LegiScan.Import

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv, strict: [session: :keep, zip: :keep, force: :boolean])

    Mix.Task.run("app.start")

    sessions =
      case Keyword.get_values(opts, :session) do
        [] -> ["2026GS", "2025GS"]
        l -> l
      end

    case Keyword.get_values(opts, :zip) do
      [] ->
        report(Import.import_sessions(sessions, force: opts[:force] || false))

      zips ->
        for zip <- zips do
          Mix.shell().info("#{zip}:")
          report({:ok, [{"zip", Import.import_zip(zip) |> unwrap()}]})
        end
    end
  end

  defp unwrap({:ok, stats}), do: stats
  defp unwrap({:error, _} = err), do: err

  defp report({:ok, results}) do
    for {session, result} <- results do
      case result do
        {:error, reason} -> fail(reason)
        :unchanged -> Mix.shell().info("#{session}: unchanged (hash match), skipped download")
        stats -> Mix.shell().info("#{session}: #{inspect(stats)}")
      end
    end
  end

  defp report({:error, reason}), do: fail(reason)

  defp fail({:unmapped_people, people}) do
    lines =
      Enum.map_join(people, "\n", &"  #{&1.people_id} #{&1.name} (#{&1.role} #{&1.district})")

    Mix.raise(
      "unmapped LegiScan people (add people_id => code to priv/data/legiscan_people.json):\n" <>
        lines
    )
  end

  defp fail(reason), do: Mix.raise("LegiScan import failed: #{inspect(reason)}")
end

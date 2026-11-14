defmodule Polticool.LegiScan.ImportRunner do
  @moduledoc """
  Runs a LegiScan import and prints a summary. Shared by `mix polticool.import_legiscan`
  and `Polticool.Release.import_legiscan/1`, so it must not depend on Mix.

  Options: `:sessions` (default 2026GS, 2025GS), `:zips`, `:force`, `:strict`,
  `:refresh_roster`. Raises when the import fails.
  """

  alias Polticool.LegiScan.Import

  @default_sessions ["2026GS", "2025GS"]

  def run(opts \\ []) do
    sessions =
      case Keyword.get(opts, :sessions, []) do
        [] -> @default_sessions
        l -> l
      end

    import_opts = [
      force: opts[:force] || false,
      strict: opts[:strict] || false,
      refresh_roster: opts[:refresh_roster] || false
    ]

    case Keyword.get(opts, :zips, []) do
      [] ->
        report(Import.import_sessions(sessions, import_opts))

      zips ->
        for zip <- zips do
          IO.puts("#{zip}:")
          report({:ok, [{"zip", Import.import_zip(zip, import_opts) |> unwrap()}]})
        end
    end

    :ok
  end

  defp unwrap({:ok, stats}), do: stats
  defp unwrap({:error, _} = err), do: err

  defp report({:ok, results}) do
    for {session, result} <- results do
      case result do
        {:error, reason} ->
          fail(reason)

        :unchanged ->
          IO.puts("#{session}: unchanged (hash match), skipped download")

        stats ->
          {unmapped, stats} = Map.pop(stats, :unmapped, [])
          IO.puts("#{session}: #{inspect(stats)}")
          report_unmapped(session, unmapped, stats)
      end
    end
  end

  defp report({:error, reason}), do: fail(reason)

  defp report_unmapped(_session, [], _stats), do: :ok

  defp report_unmapped(session, unmapped, stats) do
    if Enum.any?(unmapped, &(&1.name =~ "Thurston")) do
      IO.puts(
        :stderr,
        "!!! WARNING: THURSNK (Norman K. Thurston) could not be mapped. " <>
          "His votes were NOT imported. Add his people_id to priv/data/legiscan_people.json."
      )
    end

    IO.puts(
      "#{session}: #{length(unmapped)} unmapped LegiScan people, " <>
        "#{stats.positions_skipped} vote positions skipped " <>
        "(add people_id => code to priv/data/legiscan_people.json and re-run):\n" <>
        format_people(unmapped)
    )
  end

  defp format_people(people),
    do: Enum.map_join(people, "\n", &"  #{&1.people_id} #{&1.name} (#{&1.role} #{&1.district})")

  defp fail({:unmapped_people, people}) do
    raise "--strict: unmapped LegiScan people, nothing imported " <>
            "(add people_id => code to priv/data/legiscan_people.json):\n" <>
            format_people(people)
  end

  defp fail(reason), do: raise("LegiScan import failed: #{inspect(reason)}")
end

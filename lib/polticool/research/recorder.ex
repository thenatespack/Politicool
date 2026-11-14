defmodule Polticool.Research.Recorder do
  @moduledoc """
  Runs the live research pipeline for one legislator and saves the run to the cache
  dir (see `Polticool.Research.cache_path/1`). Shared by
  `mix polticool.record_research` and `Polticool.Release.record_research/2`; no Mix.

  Options: `:skip_ingest` uses the bills already in the database instead of
  re-fetching from le.utah.gov. Raises on failure.
  """

  import Ecto.Query

  alias Polticool.{Ballot, Repo, Research}

  def run(input, opts \\ []) do
    Application.put_env(:polticool, :research_mode, :live)

    research_opts =
      if opts[:skip_ingest], do: [ingest: &existing_bills/1], else: []

    case Research.record(input, research_opts) do
      {:ok, path, msgs} ->
        IO.puts("saved #{length(msgs)} messages to #{path}")
        summarize(List.last(msgs))
        {:ok, path, msgs}

      {:error, reason} ->
        raise "recording failed: #{inspect(reason)}"
    end
  end

  defp summarize({:done, sc}) do
    IO.puts(
      "#{sc.candidate.le_code}: grade #{inspect(sc.grade)}, score #{inspect(sc.score)}, " <>
        "bars #{inspect(sc.bars_used)}/#{inspect(sc.bars)}, " <>
        "receipts #{inspect(sc.receipts_count)}, pledges #{inspect(sc.pledges_count)}, " <>
        "absence rate #{inspect(sc.absence_rate)}"
    )
  end

  defp summarize(_), do: :ok

  defp existing_bills(candidate) do
    count =
      Repo.aggregate(
        from(b in Ballot.Bill, where: b.prime_sponsor == ^candidate.le_code),
        :count
      )

    {:ok, count}
  end
end

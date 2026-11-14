defmodule Mix.Tasks.Polticool.IngestLegislator do
  @shortdoc "Ingests a legislator's bills, votes and (optionally) roll calls from le.utah.gov"

  @moduledoc """
  Ingests every bill a legislator sponsored or floor sponsored, plus its votes.

      mix polticool.ingest_legislator THURSNK --session 2025GS --session 2026GS --roll-calls

  The code is the roster id from `https://le.utah.gov/data/legislators.json`.

  Options:

    * `--session` - session to ingest; repeatable (default `2026GS`)
    * `--roll-calls` - also scrape each vote's roll call into `vote_positions`
    * `--delay` - milliseconds to wait between requests (default `3000`). le.utah.gov
      rate-limits (429) and then drops connections after bursts, so keep this slow.

  Requests that hit a 429 or a timeout are retried with backoff (honoring
  `Retry-After`). The task is safe to re-run: bills are upserted and votes that
  already have roll-call positions are skipped.
  """
  use Mix.Task

  import Ecto.Query

  alias Polticool.{Legislators, Legislature, Repo}
  alias Polticool.Ballot.{RollCall, VotePosition}

  @retry [retry: :transient, max_retries: 4, retry_delay: &__MODULE__.backoff/1]

  @impl Mix.Task
  def run(argv) do
    {opts, args, _} =
      OptionParser.parse(argv,
        strict: [session: :keep, roll_calls: :boolean, delay: :integer]
      )

    code =
      case args do
        [code] -> String.upcase(code)
        _ -> Mix.raise("usage: mix polticool.ingest_legislator CODE [--session 2026GS]")
      end

    sessions =
      case Keyword.get_values(opts, :session) do
        [] -> ["2026GS"]
        list -> list
      end

    delay = Keyword.get(opts, :delay, 3000)

    Mix.Task.run("app.start")
    Logger.configure(level: :info)

    roster =
      case Legislators.fetch_roster(@retry) do
        {:ok, roster} -> roster
        {:error, reason} -> Mix.raise("roster fetch failed: #{inspect(reason)}")
      end

    unless code in Map.values(roster), do: Mix.shell().info("warning: #{code} not in roster")

    for session <- sessions do
      pause(delay)

      bills =
        case Legislature.sponsored_bills(session, code, @retry) do
          {:ok, bills} -> Enum.reject(bills, &(&1.role == :cosponsor))
          {:error, reason} -> Mix.raise("bill search failed: #{inspect(reason)}")
        end

      Mix.shell().info("#{session}: #{length(bills)} bills for #{code}")

      for %{number: number, role: role} <- bills do
        pause(delay)

        case Legislature.ingest_bill(session, number, @retry) do
          {:ok, bill} ->
            Mix.shell().info("  #{number} (#{role}) #{bill.title}: #{length(bill.votes)} votes")
            if opts[:roll_calls], do: sync_roll_calls(bill.votes, roster, delay)

          {:error, reason} ->
            Mix.shell().error("  #{number} failed: #{inspect(reason)}")
        end
      end
    end
  end

  defp sync_roll_calls(votes, roster, delay) do
    synced =
      VotePosition
      |> where([p], p.vote_id in ^Enum.map(votes, & &1.id))
      |> distinct(true)
      |> select([p], p.vote_id)
      |> Repo.all()
      |> MapSet.new()

    for vote <- votes, vote.id not in synced do
      pause(delay)

      case RollCall.sync_vote(vote, roster: roster, req_options: @retry) do
        {:ok, rows} -> Mix.shell().info("    vote #{vote.vote_id}: #{length(rows)} positions")
        {:error, reason} -> Mix.shell().error("    vote #{vote.vote_id}: #{inspect(reason)}")
      end
    end
  end

  @doc false
  def backoff(attempt), do: 5_000 * Integer.pow(2, attempt)

  defp pause(ms), do: Process.sleep(ms)
end

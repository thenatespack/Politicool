defmodule Mix.Tasks.Polticool.RecordResearch do
  @shortdoc "Runs the live research pipeline and saves it as the cached demo run"

  @moduledoc """
  Runs the live pipeline (needs ANTHROPIC_API_KEY, network and a database with the
  legislator) and saves the broadcast sequence to `priv/research_cache/<LE_CODE>.etf`,
  which `config :polticool, :research_mode, :cached` replays.

      ANTHROPIC_API_KEY=... mix polticool.record_research THURSNK
      ANTHROPIC_API_KEY=... mix polticool.record_research THURSNK --skip-ingest

  `--skip-ingest` uses the bills already in the database instead of re-fetching from
  le.utah.gov (useful when the site is rate-limiting or down).
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, rest, _} = OptionParser.parse(args, strict: [skip_ingest: :boolean])

    case rest do
      [input] -> record(input, opts)
      _ -> Mix.raise("usage: mix polticool.record_research LE_CODE_OR_NAME [--skip-ingest]")
    end
  end

  defp record(input, opts) do
    Mix.Task.run("app.start")
    Application.put_env(:polticool, :research_mode, :live)

    research_opts =
      if opts[:skip_ingest], do: [ingest: &existing_bills/1], else: []

    case Polticool.Research.record(input, research_opts) do
      {:ok, path, msgs} -> Mix.shell().info("saved #{length(msgs)} messages to #{path}")
      {:error, reason} -> Mix.raise("recording failed: #{inspect(reason)}")
    end
  end

  defp existing_bills(candidate) do
    import Ecto.Query

    count =
      Polticool.Repo.aggregate(
        from(b in Polticool.Ballot.Bill, where: b.prime_sponsor == ^candidate.le_code),
        :count
      )

    {:ok, count}
  end
end

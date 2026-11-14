defmodule Polticool.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :polticool

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
  LegiScan import for a release (no Mix). Options: `sessions:` (list, default
  2026GS + 2025GS), `zips:` (paths; no API calls), `force:`, `strict:`,
  `refresh_roster:`. Costs about 3 LegiScan queries without `zips:`.

      bin/polticool eval 'Polticool.Release.import_legiscan()'
  """
  def import_legiscan(opts \\ []) do
    start_app()
    Polticool.LegiScan.ImportRunner.run(opts)
  end

  @doc """
  Records a research run and saves it to the research cache dir
  (`RESEARCH_CACHE_DIR`). Option `skip_ingest:` uses bills already in the database.
  About 70 Anthropic calls.

      bin/polticool eval 'Polticool.Release.record_research("THURSNK", skip_ingest: true)'
  """
  def record_research(le_code, opts \\ []) do
    start_app()
    Polticool.Research.Recorder.run(le_code, opts)
    :ok
  end

  @doc """
  Fills in missing bill text from le.utah.gov for bills sponsored by `le_code`
  (LegiScan datasets have no text, and matching only runs on bills with text).
  Only updates text fields, never votes. One le.utah.gov request per bill, spaced
  by `delay_ms:` (default 2000). `all: true` refetches bills that already have text.

      bin/polticool eval 'Polticool.Release.backfill_bill_text("THURSNK")'
  """
  def backfill_bill_text(le_code, opts \\ []) do
    import Ecto.Query
    start_app()

    delay = Keyword.get(opts, :delay_ms, 2000)
    sessions = Keyword.get(opts, :sessions, ["2026GS", "2025GS"])

    query =
      from b in Polticool.Ballot.Bill,
        where: b.session in ^sessions,
        where: b.prime_sponsor == ^le_code or ^le_code in b.sponsors,
        order_by: [b.session, b.number]

    query =
      if opts[:all],
        do: query,
        else: where(query, [b], is_nil(b.provisions) or b.provisions == "")

    bills = Polticool.Repo.all(query)
    IO.puts("#{le_code}: #{length(bills)} bills need text")

    results =
      bills
      |> Enum.with_index()
      |> Enum.map(fn {bill, i} ->
        if i > 0, do: Process.sleep(delay)

        case Polticool.Legislature.backfill_text(bill, Keyword.take(opts, [:plug])) do
          {:ok, %{provisions: p}} when is_binary(p) and p != "" ->
            IO.puts("  ok    #{bill.session} #{bill.number}")
            :ok

          {:ok, _} ->
            IO.puts("  empty #{bill.session} #{bill.number} (no provisions in le.utah.gov JSON)")
            :empty

          {:error, reason} ->
            IO.puts("  FAIL  #{bill.session} #{bill.number}: #{inspect(reason)}")
            :error
        end
      end)

    summary = Enum.frequencies(results)
    IO.puts("#{le_code}: #{inspect(summary)}")
    summary
  end

  @doc """
  Extracts a candidate's pledges with Claude Haiku (about 1 Anthropic call per
  source). `candidate` is an id, le_code or name. `sources` are URLs and/or saved
  files (`.html`, `.txt`, `.md`); a file needs its original page URL as `{path, url}`
  or `source_url:` (single file), otherwise it is refused. Options: `dry_run: true`
  (writes nothing), `replace_seeded: true` (after success, deletes the candidate's
  seeded sample pledges and their receipts). Re-running is idempotent.

      bin/polticool eval 'Polticool.Release.extract_pledges("THURSNK", ["https://normthurston.com/issues"], replace_seeded: true)'
  """
  def extract_pledges(candidate, sources, opts \\ []) do
    start_app()
    Polticool.Pledges.Runner.run(candidate, sources, opts)
  end

  @doc """
  Runs the HD62 seeds (idempotent; also removes SAMPLE placeholder pledges).

      bin/polticool eval 'Polticool.Release.seed()'
  """
  def seed do
    start_app()
    Polticool.Seeds.hd62!()
    IO.puts("seeded")
    :ok
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  # `bin/polticool eval` does not start the app. Start it fully (Repo, PubSub,
  # Task.Supervisor, Finch) but never the web listener: the container env has
  # PHX_SERVER=true and the running app already owns the port.
  defp start_app do
    load_app()
    endpoint = Application.get_env(@app, PolticoolWeb.Endpoint, [])
    Application.put_env(@app, PolticoolWeb.Endpoint, Keyword.put(endpoint, :server, false))
    {:ok, _} = Application.ensure_all_started(@app)
    :ok
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end

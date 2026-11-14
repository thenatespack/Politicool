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

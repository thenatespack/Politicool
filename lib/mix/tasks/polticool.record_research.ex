defmodule Mix.Tasks.Polticool.RecordResearch do
  @shortdoc "Runs the live research pipeline and saves it as the cached demo run"

  @moduledoc """
  Runs the live pipeline (needs ANTHROPIC_API_KEY, network and a database with the
  legislator) and saves the broadcast sequence to `priv/research_cache/<LE_CODE>.etf`,
  which `config :polticool, :research_mode, :cached` replays.

      ANTHROPIC_API_KEY=... mix polticool.record_research THURSNK
  """
  use Mix.Task

  @impl Mix.Task
  def run([input]) do
    Mix.Task.run("app.start")
    Application.put_env(:polticool, :research_mode, :live)

    case Polticool.Research.record(input) do
      {:ok, path, msgs} -> Mix.shell().info("saved #{length(msgs)} messages to #{path}")
      {:error, reason} -> Mix.raise("recording failed: #{inspect(reason)}")
    end
  end

  def run(_), do: Mix.raise("usage: mix polticool.record_research LE_CODE_OR_NAME")
end

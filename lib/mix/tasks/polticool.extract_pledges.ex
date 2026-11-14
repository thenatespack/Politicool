defmodule Mix.Tasks.Polticool.ExtractPledges do
  @shortdoc "Extracts a candidate's pledges from campaign pages using Haiku"

  @moduledoc """
  Fetches campaign pages (or reads saved copies), extracts pledges with Claude Haiku,
  keeps only quotes found verbatim in the page, scores them on the specificity rubric
  and stores them. Thin wrapper over `Polticool.Pledges.Runner`.

      ANTHROPIC_API_KEY=... mix polticool.extract_pledges CANDIDATE SOURCE [SOURCE...]
          [--dry-run] [--replace-seeded] [--source-url URL]

  `CANDIDATE` is an id, an le_code (THURSNK) or a name. Each `SOURCE` is a URL or a
  local `.html`/`.txt`/`.md` file; a file needs its original page URL, as
  `PATH=URL` or `--source-url` (single file). Re-running is idempotent.
  """
  use Mix.Task

  alias Polticool.Pledges.Runner

  @impl Mix.Task
  def run(argv) do
    {flags, args, _} =
      OptionParser.parse(argv,
        strict: [dry_run: :boolean, replace_seeded: :boolean, source_url: :string]
      )

    case args do
      [candidate, _ | _] ->
        Mix.Task.run("app.start")
        sources = args |> tl() |> Enum.map(&parse_source/1)

        case Runner.run(candidate, sources, flags) do
          {:ok, %{failed: 0}} -> :ok
          _ -> Mix.raise("pledge extraction had errors")
        end

      _ ->
        Mix.raise(
          "usage: mix polticool.extract_pledges CANDIDATE SOURCE [SOURCE...] [--dry-run] [--replace-seeded] [--source-url URL]"
        )
    end
  end

  defp parse_source(arg) do
    with false <- String.starts_with?(arg, ["http://", "https://"]),
         [path, url] <- String.split(arg, "=", parts: 2) do
      {path, url}
    else
      _ -> arg
    end
  end
end

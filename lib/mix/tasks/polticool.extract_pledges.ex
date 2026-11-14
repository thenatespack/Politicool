defmodule Mix.Tasks.Polticool.ExtractPledges do
  @shortdoc "Extracts a candidate's pledges from campaign pages using Haiku"

  @moduledoc """
  Fetches campaign pages, extracts pledges with Claude Haiku, keeps only quotes
  found verbatim in the page, scores them on the specificity rubric and stores them.

      ANTHROPIC_API_KEY=... mix polticool.extract_pledges CANDIDATE_ID URL [URL...]

  Re-running for the same candidate and URL replaces that page's pledges.
  """
  use Mix.Task

  alias Polticool.Pledges

  @impl Mix.Task
  def run([id, _ | _] = argv) do
    candidate_id =
      case Integer.parse(id) do
        {n, ""} -> n
        _ -> usage()
      end

    Mix.Task.run("app.start")

    for url <- tl(argv) do
      case Pledges.extract_from_url(candidate_id, url) do
        {:ok, %{pledges: pledges, dropped: dropped, vague: vague}} ->
          Mix.shell().info(
            "#{url}: stored #{length(pledges)} pledges (#{vague} vague), dropped #{length(dropped)} unverifiable quotes"
          )

        {:error, reason} ->
          Mix.shell().error("#{url} failed: #{inspect(reason)}")
      end
    end
  end

  def run(_), do: usage()

  defp usage, do: Mix.raise("usage: mix polticool.extract_pledges CANDIDATE_ID URL [URL...]")
end

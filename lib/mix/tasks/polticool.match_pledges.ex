defmodule Mix.Tasks.Polticool.MatchPledges do
  @shortdoc "Matches a candidate's pledges to bills and stores cited receipts"

  @moduledoc """
  Matches each specific pledge to bills with Claude Sonnet (Citations) and formats
  verified verdicts with Haiku. Only cited, high-confidence matches are graded.

      ANTHROPIC_API_KEY=... mix polticool.match_pledges CANDIDATE_ID

  Requires bills (and votes) ingested and the candidate's `le_code` set.
  """
  use Mix.Task

  alias Polticool.{Matching, Repo}
  alias Polticool.Ballot.Candidate

  @impl Mix.Task
  def run([id]) do
    candidate_id =
      case Integer.parse(id) do
        {n, ""} -> n
        _ -> usage()
      end

    Mix.Task.run("app.start")
    candidate = Repo.get!(Candidate, candidate_id)

    {:ok, res} =
      Matching.match_candidate(candidate,
        on_progress: fn {:pledge, p, r} ->
          Mix.shell().info(
            "pledge #{p.id}: #{length(r.receipts)} receipts, #{length(r.rejected)} rejected"
          )
        end
      )

    Mix.shell().info("done: #{length(res.receipts)} receipts across #{res.pledges} pledges")
  end

  def run(_), do: usage()

  defp usage, do: Mix.raise("usage: mix polticool.match_pledges CANDIDATE_ID")
end

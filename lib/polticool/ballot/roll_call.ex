defmodule Polticool.Ballot.RollCall do
  @moduledoc """
  Scrapes le.utah.gov `DynaBill/svotes.jsp` roll calls into `vote_positions`.

  Votes come from card #902 (`actionHistoryList` entries carry `voteID`/`voteHouse`),
  stored as `%Vote{vote_id:, house:}` with a `bill` that has `session`. Committee votes
  have an empty house, which is sent blank.
  """

  import Ecto.Query

  alias Polticool.{Legislators, Repo}
  alias Polticool.Ballot.{Vote, VotePosition}

  @base "https://le.utah.gov/DynaBill/svotes.jsp"
  @sections [:yea, :nay, :absent]

  @doc "URL of the roll-call page."
  def url(session, vote_id, house),
    do: "#{@base}?" <> URI.encode_query(sessionid: session, voteid: vote_id, house: house || "")

  @doc """
  Parse an svotes.jsp HTML page into `[%{name:, position:}]`.

  The page has three tables, in order: Yeas, Nays, Absent or not voting.
  """
  def parse(html) when is_binary(html) do
    tables = html |> LazyHTML.from_document() |> LazyHTML.query("table") |> Enum.to_list()

    @sections
    |> Enum.zip(tables)
    |> Enum.flat_map(fn {position, table} ->
      table
      |> LazyHTML.query("td")
      |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&%{name: &1, position: position})
    end)
  end

  @doc """
  Fetch the roll-call HTML. `:req_options` are merged into the request (use `plug:`
  with `Req.Test` in tests).
  """
  def fetch(session, vote_id, house, opts \\ []) do
    req_opts = Keyword.get(opts, :req_options, [])

    case Req.get(url(session, vote_id, house), Keyword.merge([retry: false], req_opts)) do
      {:ok, %{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Convert parsed entries into position attrs with legislator codes.

  Options: `:roster` (from `Polticool.Legislators.fetch_roster/1`; without it codes
  fall back to a guess that is often wrong) and `:house` (`"H"`/`"S"`).
  """
  def to_positions(entries, opts \\ []) do
    roster = Keyword.get(opts, :roster, %{})
    house = Keyword.get(opts, :house)

    entries
    |> Enum.map(fn %{name: name, position: pos} ->
      %{
        legislator_code: Legislators.code_for(name, roster, house),
        legislator_name: name,
        position: pos
      }
    end)
    |> Enum.uniq_by(& &1.legislator_code)
  end

  @doc """
  Fetch + parse + store positions for a vote (idempotent: replaces existing rows) and
  refresh its tally. Returns `{:ok, [%VotePosition{}]}` or `{:error, reason}`.
  """
  def sync_vote(%Vote{} = vote, opts \\ []) do
    vote = Repo.preload(vote, :bill)

    with {:ok, html} <- fetch(vote.bill.session, vote.vote_id, vote.house, opts) do
      store(vote, html, opts)
    end
  end

  @doc "Store positions from already-fetched HTML for `vote`."
  def store(%Vote{} = vote, html, opts \\ []) do
    positions = html |> parse() |> to_positions(Keyword.put_new(opts, :house, vote.house))

    if positions == [] do
      {:error, :no_positions}
    else
      tally =
        positions
        |> Enum.frequencies_by(& &1.position)
        |> Map.new(fn {k, v} -> {to_string(k), v} end)

      Repo.transact(fn ->
        Repo.delete_all(from p in VotePosition, where: p.vote_id == ^vote.id)

        rows = Enum.map(positions, &Map.put(&1, :vote_id, vote.id))
        {_, inserted} = Repo.insert_all(VotePosition, rows, returning: true)

        vote
        |> Ecto.Changeset.change(tally: Map.merge(vote.tally || %{}, tally))
        |> Repo.update!()

        {:ok, inserted}
      end)
    end
  end
end

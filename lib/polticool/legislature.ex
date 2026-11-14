defmodule Polticool.Legislature do
  @moduledoc """
  Ingests bills from the le.utah.gov JSON feed
  (`https://le.utah.gov/data/{SESSION}/{BILL}.json`, no token) and persists
  floor + committee votes.
  """
  import Ecto.Query

  alias Polticool.Repo
  alias Polticool.Ballot.{Bill, Vote}

  @base_url "https://le.utah.gov/data"
  @skip_codes ~w(HCIRCLED HUNCIRCLED SCIRCLED SUNCIRCLED)

  @doc "URL of the bill JSON."
  def bill_json_url(session, number), do: "#{@base_url}/#{session}/#{number}.json"

  @doc "URL of the roll-call page for a floor vote."
  def roll_call_url(session, vote_id, house),
    do:
      "https://le.utah.gov/DynaBill/svotes.jsp?sessionid=#{session}&voteid=#{vote_id}&house=#{house}"

  @doc """
  Fetches the bill JSON and returns the decoded map. Extra `Req` options
  (e.g. `plug: {Req.Test, Polticool.Legislature}`) come from
  `config :polticool, :legislature_req_options` and `opts`.
  """
  def fetch_bill_json(session, number, opts \\ []) do
    req_opts =
      [
        url: bill_json_url(session, number),
        decode_body: false,
        retry: false,
        receive_timeout: 20_000
      ]
      |> Keyword.merge(Application.get_env(:polticool, :legislature_req_options, []))
      |> Keyword.merge(opts)

    case Req.get(req_opts) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, %{} = json} -> {:ok, json}
          _ -> {:error, :invalid_json}
        end

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Fetches, parses and stores a bill and its votes."
  def ingest_bill(session, number, opts \\ []) do
    with {:ok, json} <- fetch_bill_json(session, number, opts) do
      ingest_json(session, number, json)
    end
  end

  @doc "Stores an already-decoded bill JSON map. Idempotent (upserts)."
  def ingest_json(session, number, json) do
    attrs = parse_bill(session, number, json)
    votes = parse_votes(session, json)

    Repo.transaction(fn ->
      bill =
        Repo.insert!(Bill.changeset(%Bill{}, attrs),
          on_conflict: {:replace_all_except, [:id, :inserted_at]},
          conflict_target: [:session, :number],
          returning: true
        )

      stored =
        for v <- votes do
          Repo.insert!(Vote.changeset(%Vote{}, Map.put(v, :bill_id, bill.id)),
            on_conflict: {:replace_all_except, [:id, :bill_id, :inserted_at]},
            conflict_target: [:bill_id, :vote_id, :house],
            returning: true
          )
        end

      %{bill | votes: stored}
    end)
  end

  @doc "Returns the stored bill with votes, or nil."
  def get_bill(session, number) do
    Bill
    |> where([b], b.session == ^session and b.number == ^number)
    |> preload(:votes)
    |> Repo.one()
  end

  @doc "Maps bill JSON to `Bill` attrs."
  def parse_bill(session, number, json) do
    versions = list(json["billVersionList"])

    cosponsors =
      versions
      |> Enum.flat_map(&list(&1["coSponsorList"]))
      |> Enum.map(&cosponsor_code/1)

    sponsors =
      ([json["primeSponsor"], json["floorSponsor"]] ++ cosponsors)
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.uniq()

    %{
      session: session,
      number: number,
      title: json["shortTitle"],
      prime_sponsor: blank_to_nil(json["primeSponsor"]),
      floor_sponsor: blank_to_nil(json["floorSponsor"]),
      sponsors: sponsors,
      provisions: json["generalProvisions"],
      versions: Enum.filter(versions, &is_map/1),
      url: bill_json_url(session, number)
    }
  end

  @doc """
  Extracts floor and committee votes from `actionHistoryList`, skipping
  circled/uncircled actions and voice votes (`voiceVote == "1"`).
  """
  def parse_votes(session, json) do
    json["actionHistoryList"]
    |> list()
    |> Enum.filter(&countable_vote?/1)
    |> Enum.map(&to_vote_attrs(session, &1))
  end

  defp countable_vote?(%{"voteID" => id, "actionCode" => code} = a) do
    id not in [nil, ""] and code not in @skip_codes and a["voiceVote"] != "1"
  end

  defp countable_vote?(_), do: false

  defp to_vote_attrs(session, a) do
    floor? = a["voteHouse"] in ["H", "S"]
    house = if floor?, do: a["voteHouse"], else: code_house(a["actionCode"])

    %{
      vote_id: a["voteID"],
      house: house,
      kind: if(floor?, do: :floor, else: :committee),
      action_code: a["actionCode"],
      action: a["description"],
      tally: parse_tally(a["voteStr"]),
      date: parse_date(a["actionDate"]),
      url: if(floor? and house, do: roll_call_url(session, a["voteID"], house))
    }
  end

  defp code_house("H" <> _), do: "H"
  defp code_house("S" <> _), do: "S"
  defp code_house(_), do: nil

  @doc ~s|Parses "70-0-5" into %{"yea" => 70, "nay" => 0, "absent" => 5}.|
  def parse_tally(str) when is_binary(str) do
    with [y, n, a] <- String.split(str, "-"),
         {y, ""} <- Integer.parse(y),
         {n, ""} <- Integer.parse(n),
         {a, ""} <- Integer.parse(a) do
      %{"yea" => y, "nay" => n, "absent" => a}
    else
      _ -> %{}
    end
  end

  def parse_tally(_), do: %{}

  defp parse_date(<<date::binary-size(10), _::binary>>) do
    case Date.from_iso8601(date) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  defp parse_date(_), do: nil

  defp cosponsor_code(%{"sponsor" => c}), do: c
  defp cosponsor_code(%{"code" => c}), do: c
  defp cosponsor_code(c) when is_binary(c), do: c
  defp cosponsor_code(_), do: nil

  defp list(l) when is_list(l), do: l
  defp list(_), do: []

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v
end

defmodule Polticool.LegiScan.Import do
  @moduledoc """
  Imports LegiScan datasets (bills, roll calls, per-member positions) into the
  existing `bills`, `votes` and `vote_positions` tables, alongside the le.utah.gov
  ingest in `Polticool.Legislature`.

  Idempotent: bills are upserted by (session, number) (LegiScan `HB216` becomes
  `HB0216`), roll calls are matched to an existing floor/committee vote of the same
  bill, house and date (or inserted), and positions are upserted per
  (vote, legislator). LegiScan ids are stored so re-imports update in place.

  Special sessions are skipped (our session ids are `2026GS` style).
  """
  import Ecto.Query

  alias Polticool.{LegiScan, Repo}
  alias Polticool.LegiScan.People
  alias Polticool.Ballot.{Bill, LegiscanDataset, Vote, VotePosition}

  @doc """
  Imports from the API for the given session ids (e.g. `["2026GS"]`), skipping any
  whose dataset hash is unchanged. Options: `:roster`, `:overrides`, `:force`,
  `:strict` (abort if any voter is unmapped; default skips their positions and
  reports them in `stats.unmapped`) and `:refresh_roster` (try live le.utah.gov
  before the committed snapshot). The dataset hash is not recorded while voters
  are unmapped, so a re-run after fixing the override file re-imports.
  """
  def import_sessions(sessions, opts \\ []) do
    with {:ok, list} <- LegiScan.dataset_list("UT") do
      Enum.reduce_while(sessions, {:ok, []}, fn session, {:ok, acc} ->
        case Enum.find(list, &(session_id(&1) == session)) do
          nil ->
            {:halt, {:error, {:no_dataset, session}}}

          ds ->
            case import_dataset(session, ds, opts) do
              {:ok, result} -> {:cont, {:ok, acc ++ [{session, result}]}}
              {:error, _} = err -> {:halt, err}
            end
        end
      end)
    end
  end

  defp import_dataset(session, ds, opts) do
    stored = Repo.get_by(LegiscanDataset, session: session)

    if stored && stored.dataset_hash == ds["dataset_hash"] && !opts[:force] do
      {:ok, :unchanged}
    else
      with {:ok, zip} <- LegiScan.get_dataset(ds["session_id"], ds["access_key"]),
           {:ok, stats} <- import_zip(zip, opts) do
        if stats.unmapped == [], do: record_hash(session, ds)
        {:ok, stats}
      end
    end
  end

  defp record_hash(session, ds) do
    Repo.insert!(
      %LegiscanDataset{
        session: session,
        legiscan_session_id: ds["session_id"],
        dataset_hash: ds["dataset_hash"],
        dataset_date: ds["dataset_date"],
        imported_at: DateTime.utc_now() |> DateTime.truncate(:second)
      },
      on_conflict: {:replace_all_except, [:id, :session]},
      conflict_target: :session
    )
  end

  @doc "Our session id for a LegiScan session ('2026GS'), or nil for special sessions."
  def session_id(%{"special" => special}) when special not in [0, nil, "0"], do: nil

  def session_id(%{"year_start" => y}) when is_integer(y), do: "#{y}GS"
  def session_id(_), do: nil

  @doc """
  Normalizes to the le.utah.gov bill code: prefix + numerals is 6 characters.

  `HB216` -> `HB0216`, `HJR12` -> `HJR012`, `HJR0010` -> `HJR010`. Numbers whose
  natural form exceeds 6 characters are left unpadded (never truncated).
  """
  def normalize_number(number) when is_binary(number) do
    case Regex.run(~r/^([A-Za-z]+)\s*0*(\d+)$/, String.trim(number)) do
      [_, prefix, nums] ->
        prefix = String.upcase(prefix)
        prefix <> String.pad_leading(nums, max(6 - String.length(prefix), 1), "0")

      _ ->
        String.upcase(number)
    end
  end

  @doc "Imports a dataset zip (binary) or the path of one."
  def import_zip(zip, opts \\ []) do
    with {:ok, files} <- unzip(zip) do
      import_files(files, opts)
    end
  end

  defp unzip(path) when byte_size(path) < 1024 do
    if String.ends_with?(path, ".zip") and File.regular?(path),
      do: path |> File.read!() |> unzip(),
      else: unzip_binary(path)
  end

  defp unzip(bin), do: unzip_binary(bin)

  defp unzip_binary(bin) do
    case :zip.unzip(bin, [:memory]) do
      {:ok, entries} -> {:ok, for({name, data} <- entries, do: {to_string(name), data})}
      {:error, reason} -> {:error, {:bad_zip, reason}}
    end
  end

  defp import_files(files, opts) do
    bills = decode(files, "bill", "bill")
    roll_calls = decode(files, "vote", "roll_call")
    people = decode(files, "people", "person")

    roster =
      Keyword.get_lazy(opts, :roster, fn ->
        People.load_roster(refresh: opts[:refresh_roster] || false)
      end)

    overrides = Keyword.get_lazy(opts, :overrides, &People.overrides/0)
    {mapping, missing} = People.resolve(people, roster, overrides)
    people_by_id = Map.new(people, &{&1["people_id"], &1})

    voter_ids =
      roll_calls
      |> Enum.flat_map(&List.wrap(&1["votes"]))
      |> Enum.map(& &1["people_id"])
      |> Enum.uniq()

    by_id = Map.new(missing, &{&1.people_id, &1})

    unmapped =
      for id <- voter_ids,
          not Map.has_key?(mapping, id),
          do:
            Map.get(by_id, id) || People.describe(Map.get(people_by_id, id, %{"people_id" => id}))

    if unmapped != [] and opts[:strict] do
      {:error, {:unmapped_people, unmapped}}
    else
      Repo.transaction(
        fn -> do_import(bills, roll_calls, mapping) |> Map.put(:unmapped, unmapped) end,
        timeout: :infinity
      )
    end
  end

  defp decode(files, dir, key) do
    for {name, data} <- files,
        name |> Path.split() |> Enum.member?(dir),
        String.ends_with?(name, ".json"),
        {:ok, %{^key => obj}} <- [Jason.decode(data)],
        do: obj
  end

  defp do_import(bills, roll_calls, mapping) do
    bill_ids =
      for b <- bills, session = session_id(b["session"] || %{}), into: %{} do
        {b["bill_id"], upsert_bill(session, b, mapping).id}
      end

    stats =
      Enum.reduce(
        roll_calls,
        %{roll_calls: 0, positions: 0, positions_skipped: 0, skipped: 0},
        fn rc, acc ->
          case Map.get(bill_ids, rc["bill_id"]) || bill_id_from_db(rc["bill_id"]) do
            nil ->
              %{acc | skipped: acc.skipped + 1}

            bill_id ->
              vote = upsert_vote(bill_id, rc)
              {n, skipped} = upsert_positions(vote, rc, mapping)

              %{
                acc
                | roll_calls: acc.roll_calls + 1,
                  positions: acc.positions + n,
                  positions_skipped: acc.positions_skipped + skipped
              }
          end
        end
      )

    Map.put(stats, :bills, map_size(bill_ids))
  end

  defp bill_id_from_db(legiscan_id),
    do: Repo.one(from b in Bill, where: b.legiscan_bill_id == ^legiscan_id, select: b.id)

  defp upsert_bill(session, b, mapping) do
    number = normalize_number(b["bill_number"])

    existing =
      Repo.get_by(Bill, session: session, number: number) ||
        Repo.get_by(Bill, legiscan_bill_id: b["bill_id"])

    url = blank(b["state_link"]) || blank(b["url"])

    case existing do
      nil ->
        sponsors = for s <- List.wrap(b["sponsors"]), code = mapping[s["people_id"]], do: code

        prime =
          Enum.find_value(List.wrap(b["sponsors"]), fn
            %{"sponsor_type_id" => 1, "people_id" => id} -> mapping[id]
            _ -> nil
          end)

        Repo.insert!(
          Bill.changeset(%Bill{}, %{
            session: session,
            number: number,
            title: blank(b["title"]) || blank(b["description"]),
            prime_sponsor: prime,
            sponsors: Enum.uniq(sponsors),
            url: url,
            legiscan_bill_id: b["bill_id"]
          })
        )

      bill ->
        bill
        |> Bill.changeset(%{
          legiscan_bill_id: b["bill_id"],
          title: bill.title || blank(b["title"]),
          url: bill.url || url
        })
        |> Repo.update!()
    end
  end

  defp upsert_vote(bill_id, rc) do
    house = rc["chamber"]
    date = parse_date(rc["date"])
    desc = rc["desc"]

    tally = %{
      "yea" => rc["yea"],
      "nay" => rc["nay"],
      "absent" => (rc["nv"] || 0) + (rc["absent"] || 0)
    }

    kind = if is_binary(desc) and desc =~ ~r/committee/i, do: :committee, else: :floor

    existing =
      Repo.get_by(Vote, legiscan_roll_call_id: rc["roll_call_id"]) ||
        match_existing(bill_id, house, date, kind)

    attrs = %{legiscan_roll_call_id: rc["roll_call_id"], tally: tally}

    case existing do
      nil ->
        Repo.insert!(
          Vote.changeset(
            %Vote{},
            Map.merge(attrs, %{
              bill_id: bill_id,
              vote_id: "ls-#{rc["roll_call_id"]}",
              house: house,
              kind: kind,
              action: desc,
              date: date
            })
          )
        )

      vote ->
        vote |> Vote.changeset(attrs) |> Repo.update!()
    end
  end

  defp match_existing(bill_id, house, date, kind) do
    candidates =
      Repo.all(
        from v in Vote,
          where:
            v.bill_id == ^bill_id and v.house == ^house and v.date == ^date and v.kind == ^kind and
              is_nil(v.legiscan_roll_call_id),
          order_by: v.id
      )

    case candidates do
      [one] -> one
      _ -> nil
    end
  end

  defp upsert_positions(vote, rc, mapping) do
    {mapped, unmapped} =
      rc["votes"] |> List.wrap() |> Enum.split_with(&Map.has_key?(mapping, &1["people_id"]))

    rows =
      for v <- mapped, into: %{} do
        code = Map.fetch!(mapping, v["people_id"])

        {code,
         %{
           vote_id: vote.id,
           legislator_code: code,
           legiscan_people_id: v["people_id"],
           position: position(v["vote_id"])
         }}
      end

    for {_code, attrs} <- rows do
      Repo.insert!(VotePosition.changeset(%VotePosition{}, attrs),
        on_conflict: {:replace, [:position, :legiscan_people_id]},
        conflict_target: [:vote_id, :legislator_code]
      )
    end

    {map_size(rows), length(unmapped)}
  end

  defp position(1), do: :yea
  defp position(2), do: :nay
  defp position(_), do: :absent

  defp parse_date(s) when is_binary(s) do
    case Date.from_iso8601(s) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  defp parse_date(_), do: nil

  defp blank(""), do: nil
  defp blank(v), do: v
end

defmodule Polticool.Legislators do
  @moduledoc """
  Maps legislator names to le.utah.gov legislator codes using the official roster at
  `https://le.utah.gov/data/legislators.json` (no token).

  Codes can't be derived reliably from names: Thurston, Norman K is `THURSNK`,
  Whyte, Stephen L. is `WHYTESL`, Thompson, Jason E. is `THOMJA` and
  Miller, Grant is `MILLGR`. Always resolve through a roster from `fetch_roster/1`
  or `build_roster/1`. `derive_code/1` is only a last-resort fallback for names
  missing from the roster (e.g. former members on an old roll call).

  A roster is a map keyed by `{house, normalized_name}` (house `"H"` or `"S"`) and,
  when unambiguous across both chambers, by `normalized_name` alone. When the source
  has districts it also holds `{:district, house, "62"}` => `{code, last_name_key}`
  (see `lookup_district/3`).

  ## Snapshot

  `priv/data/legislators.json` is a committed snapshot of
  `https://le.utah.gov/data/legislators.json` taken 2026-11-14 (103 members), for
  when le.utah.gov blocks or times out. See `snapshot_roster/0`.
  """

  @roster_url "https://le.utah.gov/data/legislators.json"

  @doc "URL of the official roster JSON."
  def roster_url, do: @roster_url

  @doc """
  Fetches the roster and returns `{:ok, roster}`. Extra `Req` options come from
  `config :polticool, :legislature_req_options` and `opts`.
  """
  def fetch_roster(opts \\ []) do
    req_opts =
      [url: @roster_url, decode_body: false, retry: false, receive_timeout: 20_000]
      |> Keyword.merge(Application.get_env(:polticool, :legislature_req_options, []))
      |> Keyword.merge(opts)

    case Req.get(req_opts) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, %{"legislators" => list}} when is_list(list) -> {:ok, build_roster(list)}
          _ -> {:error, :invalid_json}
        end

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Path of the committed roster snapshot."
  def snapshot_path, do: Application.app_dir(:polticool, "priv/data/legislators.json")

  @doc "Roster built from the committed snapshot (`{:ok, roster}` or `{:error, reason}`)."
  def snapshot_roster do
    with {:ok, text} <- File.read(snapshot_path()),
         {:ok, %{"legislators" => list}} when is_list(list) <- Jason.decode(text) do
      {:ok, build_roster(list)}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_json}
    end
  end

  @doc """
  Looks up a member by chamber and district number (`"H"`, `"62"`), returning
  `{code, last_name_key}` or `nil`.
  """
  def lookup_district(roster, house, district), do: roster[{:district, house, district}]

  @doc "Normalized last-name key: `\"Thurston, Norman K.\"` becomes `\"thurston\"`."
  def last_name_key(name) when is_binary(name),
    do: name |> String.split(",", parts: 2) |> hd() |> clean()

  @doc "Builds a roster from the `legislators` list of the roster JSON."
  def build_roster(legislators) when is_list(legislators) do
    entries =
      for %{"fullName" => full, "id" => id, "house" => house} <- legislators,
          is_binary(full) and is_binary(id),
          do: {house, normalize(full), id}

    by_house = Map.new(entries, fn {house, key, id} -> {{house, key}, id} end)

    by_name =
      entries
      |> Enum.group_by(fn {_, key, _} -> key end, fn {_, _, id} -> id end)
      |> Enum.flat_map(fn
        {key, [id]} -> [{key, id}]
        _ambiguous -> []
      end)
      |> Map.new()

    by_district =
      for %{"fullName" => full, "id" => id, "house" => house, "district" => d}
          when is_binary(full) and is_binary(id) and is_binary(d) <- legislators,
          into: %{},
          do: {{:district, house, d}, {id, last_name_key(full)}}

    by_name |> Map.merge(by_house) |> Map.merge(by_district)
  end

  @doc """
  Normalized lookup key: lowercase last name plus first initial, e.g.
  `"Miller, G."` and `"Miller, Grant Amjad"` both become `"miller, g"`.
  """
  def normalize(name) when is_binary(name) do
    case String.split(name, ",", parts: 2) do
      [last, first] -> clean(last) <> ", " <> String.slice(clean(first), 0, 1)
      [last] -> clean(last)
    end
  end

  @doc """
  Resolves a name to a legislator code: the roster entry for `house`, then the
  chamber-independent entry, then `derive_code/1`.
  """
  def code_for(name, roster \\ %{}, house \\ nil) when is_binary(name) do
    key = normalize(name)
    roster[{house, key}] || roster[key] || derive_code(name)
  end

  @doc "Fallback guess (first five letters of the last name + first initial)."
  def derive_code(name) when is_binary(name) do
    case String.split(name, ",", parts: 2) do
      [last, first] -> letters(last, 5) <> letters(first, 1)
      [last] -> letters(last, 6)
    end
  end

  defp letters(s, n),
    do: s |> String.upcase() |> String.replace(~r/[^A-Z]/, "") |> String.slice(0, n)

  defp clean(s), do: s |> String.downcase() |> String.replace(~r/[^a-z]/, "")
end

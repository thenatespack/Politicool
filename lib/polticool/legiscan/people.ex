defmodule Polticool.LegiScan.People do
  @moduledoc """
  Maps LegiScan people to le.utah.gov legislator codes (e.g. `THURSNK`).

  Resolution order:

    1. committed override file `priv/data/legiscan_people.json` (people_id -> code);
    2. chamber + district: `role` "Rep"/"Sen" is house "H"/"S", `district`
       "HD-062"/"SD-012" is "62"/"12". The member's last name must also match
       (normalized); a district hit with a different last name (e.g. a member
       replaced mid-term) is left unmapped rather than guessed;
    3. only when LegiScan gives no district: chamber + "last, first initial".

  The roster comes from the committed snapshot `priv/data/legislators.json`
  (le.utah.gov/data/legislators.json, snapshot 2026-11-14) by default, because
  le.utah.gov blocks and times out. `load_roster(refresh: true)` tries the live
  roster first and falls back to the snapshot.
  """
  alias Polticool.Legislators

  def overrides_path, do: Application.app_dir(:polticool, "priv/data/legiscan_people.json")

  def overrides do
    with {:ok, text} <- File.read(overrides_path()),
         {:ok, %{"people" => map}} <- Jason.decode(text) do
      map
    else
      _ -> %{}
    end
  end

  @doc """
  Roster for mapping. Uses the committed snapshot; with `refresh: true` tries live
  le.utah.gov first (`:fetch` overrides the fetch function, for tests) and falls
  back to the snapshot. Returns `%{}` only if the snapshot is unreadable too.
  """
  def load_roster(opts \\ []) do
    fetch = Keyword.get(opts, :fetch, &Legislators.fetch_roster/0)
    live = if opts[:refresh], do: fetch.(), else: :skip

    case live do
      {:ok, roster} ->
        roster

      _ ->
        case Legislators.snapshot_roster() do
          {:ok, roster} -> roster
          _ -> %{}
        end
    end
  end

  @doc """
  Returns `{mapping, unmapped}`: `mapping` is `%{people_id => code}`, `unmapped` a list
  of `%{people_id:, name:, role:, district:}`.
  """
  def resolve(people, roster, overrides \\ %{}) do
    {map, missing} =
      Enum.reduce(people, {%{}, []}, fn p, {map, missing} ->
        case code_for(p, roster, overrides) do
          nil -> {map, [describe(p) | missing]}
          code -> {Map.put(map, p["people_id"], code), missing}
        end
      end)

    {map, Enum.reverse(missing)}
  end

  defp code_for(p, roster, overrides) do
    overrides[to_string(p["people_id"])] || from_roster(p, roster)
  end

  defp from_roster(p, roster) do
    house = house(p["role"])

    cond do
      is_nil(house) ->
        nil

      district = district(p["district"]) ->
        case Legislators.lookup_district(roster, house, district) do
          {code, last} ->
            if last == Legislators.last_name_key("#{p["last_name"]},"), do: code

          nil ->
            nil
        end

      true ->
        roster[{house, Legislators.normalize("#{p["last_name"]}, #{p["first_name"]}")}]
    end
  end

  defp house("Rep"), do: "H"
  defp house("Sen"), do: "S"
  defp house(_), do: nil

  # "HD-062" -> "62", "SD-012" -> "12"; nil when there is no numeric district.
  defp district(d) when is_binary(d) do
    case Regex.run(~r/(\d+)\s*$/, d) do
      [_, digits] -> digits |> String.to_integer() |> Integer.to_string()
      _ -> nil
    end
  end

  defp district(_), do: nil

  @doc false
  def describe(p),
    do: %{people_id: p["people_id"], name: p["name"], role: p["role"], district: p["district"]}
end

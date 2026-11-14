defmodule Polticool.LegiScan.People do
  @moduledoc """
  Maps LegiScan people to le.utah.gov legislator codes (e.g. `THURSNK`).

  Resolution order: committed override file `priv/data/legiscan_people.json`
  (people_id -> code), then the le.utah.gov roster by chamber + normalized
  "last, first initial" (see `Polticool.Legislators`). Nothing is guessed:
  people that don't resolve are returned as unmapped.
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

  @doc "Roster from le.utah.gov, or `%{}` if unreachable (overrides still apply)."
  def fetch_roster do
    case Legislators.fetch_roster() do
      {:ok, roster} -> roster
      _ -> %{}
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
    house = house(p["role"])
    name = "#{p["last_name"]}, #{p["first_name"]}"

    overrides[to_string(p["people_id"])] ||
      (house && roster[{house, Legislators.normalize(name)}])
  end

  defp house("Rep"), do: "H"
  defp house("Sen"), do: "S"
  defp house(_), do: nil

  defp describe(p),
    do: %{people_id: p["people_id"], name: p["name"], role: p["role"], district: p["district"]}
end

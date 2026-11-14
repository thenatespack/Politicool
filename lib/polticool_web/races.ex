defmodule PolticoolWeb.Races do
  @moduledoc "Display names for races (`Polticool.Ballot.Race`)."

  @doc ~s|Full title, e.g. "House District 62".|
  def title(%{office: office, district: district}) when is_binary(district) do
    cond do
      (office || "") =~ "House" -> "House District #{district}"
      (office || "") =~ "Senate" -> "Senate District #{district}"
      true -> "#{office} · #{district}"
    end
  end

  def title(race), do: race.office || race.key

  @doc ~s|Short label for kickers, e.g. "HD62"; falls back to the title.|
  def short(%{key: "hd" <> digits} = race) do
    if digits =~ ~r/^\d+$/, do: "HD" <> digits, else: title(race)
  end

  def short(%{key: "sd" <> digits} = race) do
    if digits =~ ~r/^\d+$/, do: "SD" <> digits, else: title(race)
  end

  def short(race), do: title(race)
end

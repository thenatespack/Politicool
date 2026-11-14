defmodule Polticool.Legislators do
  @moduledoc """
  Maps roll-call names (`"Last, F."`) to le.utah.gov legislator codes.

  Utah codes are the first five letters of the last name followed by the first
  initial (e.g. Loubet, A. -> `LOUBEA`, McCay, D. -> `MCCAYD`). The initial is what
  separates same-surname members such as `Miller, G.` (`MILLEG`) and
  `Miller, T.` (`MILLET`). Pass a `roster` (a map of normalized name => code, see
  `normalize/1`) to override the derived code, e.g. from the official API roster.
  """

  @doc "Normalized lookup key for a roll-call name, e.g. `\"miller, g\"`."
  def normalize(name) when is_binary(name) do
    case String.split(name, ",", parts: 2) do
      [last, first] -> clean(last) <> ", " <> String.slice(clean(first), 0, 1)
      [last] -> clean(last)
    end
  end

  @doc "Resolve a roll-call name to a legislator code."
  def code_for(name, roster \\ %{}) when is_binary(name) do
    Map.get_lazy(roster, normalize(name), fn -> derive_code(name) end)
  end

  defp derive_code(name) do
    case String.split(name, ",", parts: 2) do
      [last, first] -> letters(last, 5) <> letters(first, 1)
      [last] -> letters(last, 6)
    end
  end

  defp letters(s, n),
    do: s |> String.upcase() |> String.replace(~r/[^A-Z]/, "") |> String.slice(0, n)

  defp clean(s), do: s |> String.downcase() |> String.replace(~r/[^a-z]/, "")
end

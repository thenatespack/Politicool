defmodule Polticool.Ballot.Race do
  @moduledoc "A contest on the ballot with its candidates."
  defstruct [:key, :office, :district, candidates: []]
end

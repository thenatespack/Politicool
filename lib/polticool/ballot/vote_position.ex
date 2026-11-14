defmodule Polticool.Ballot.VotePosition do
  use Ecto.Schema
  import Ecto.Changeset

  schema "vote_positions" do
    field :legislator_code, :string
    field :legislator_name, :string
    field :position, Ecto.Enum, values: [:yea, :nay, :absent]
    field :legiscan_people_id, :integer

    belongs_to :vote, Polticool.Ballot.Vote
  end

  def changeset(position, attrs) do
    position
    |> cast(attrs, [:vote_id, :legislator_code, :legislator_name, :position, :legiscan_people_id])
    |> validate_required([:vote_id, :legislator_code, :position])
    |> assoc_constraint(:vote)
    |> unique_constraint([:vote_id, :legislator_code])
  end
end

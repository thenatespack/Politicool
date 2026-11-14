defmodule Polticool.Ballot.Vote do
  use Ecto.Schema
  import Ecto.Changeset

  schema "votes" do
    field :vote_id, :string
    field :house, :string
    field :kind, Ecto.Enum, values: [:floor, :committee]
    field :action_code, :string
    field :action, :string
    field :tally, :map, default: %{}
    field :date, :date
    field :url, :string

    belongs_to :bill, Polticool.Ballot.Bill
    has_many :positions, Polticool.Ballot.VotePosition

    timestamps(type: :utc_datetime)
  end

  @fields ~w(bill_id vote_id house kind action_code action tally date url)a

  def changeset(vote, attrs) do
    vote
    |> cast(attrs, @fields)
    |> validate_required([:bill_id, :vote_id, :kind])
    |> assoc_constraint(:bill)
    |> unique_constraint([:bill_id, :vote_id, :house])
  end
end

defmodule Polticool.Ballot.Bill do
  use Ecto.Schema
  import Ecto.Changeset

  schema "bills" do
    field :session, :string
    field :number, :string
    field :title, :string
    field :prime_sponsor, :string
    field :floor_sponsor, :string
    field :sponsors, {:array, :string}, default: []
    field :provisions, :string
    field :versions, {:array, :map}, default: []
    field :url, :string

    has_many :votes, Polticool.Ballot.Vote

    timestamps(type: :utc_datetime)
  end

  @fields ~w(session number title prime_sponsor floor_sponsor sponsors provisions versions url)a

  def changeset(bill, attrs) do
    bill
    |> cast(attrs, @fields)
    |> validate_required([:session, :number])
    |> unique_constraint([:session, :number])
  end
end

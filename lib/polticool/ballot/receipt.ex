defmodule Polticool.Ballot.Receipt do
  use Ecto.Schema
  import Ecto.Changeset

  @outcomes [:kept, :partial, :broken, :untested, :absent]

  schema "receipts" do
    field :outcome, Ecto.Enum, values: @outcomes, default: :untested
    field :confidence, Ecto.Enum, values: [:high, :medium, :low]
    field :trap, :boolean, default: false
    field :rationale, :string
    field :citations, {:array, :map}, default: []
    field :verified, :boolean, default: false
    field :track_record, :boolean, default: false
    field :quote, :string
    field :source_url, :string
    field :bill_title, :string
    field :bill_summary, :string
    field :vote_position, Ecto.Enum, values: [:yea, :nay, :absent]
    field :tally, :string
    field :retrieved_at, :utc_datetime

    belongs_to :pledge, Polticool.Ballot.Pledge
    belongs_to :bill, Polticool.Ballot.Bill
    belongs_to :vote, Polticool.Ballot.Vote

    timestamps(type: :utc_datetime)
  end

  def outcomes, do: @outcomes

  @fields ~w(pledge_id bill_id vote_id outcome confidence trap rationale citations verified track_record quote source_url bill_title bill_summary vote_position tally retrieved_at)a

  def changeset(receipt, attrs) do
    receipt
    |> cast(attrs, @fields)
    |> validate_required([:pledge_id, :outcome])
    |> assoc_constraint(:pledge)
  end
end

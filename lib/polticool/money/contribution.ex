defmodule Polticool.Money.Contribution do
  @moduledoc "One campaign contribution (a disclosed fact) to a candidate."
  use Ecto.Schema
  import Ecto.Changeset

  schema "contributions" do
    belongs_to :candidate, Polticool.Ballot.Candidate
    field :donor_name, :string
    field :normalized_donor, :string
    field :amount_cents, :integer
    field :date, :date
    field :industry, :string
    field :source_url, :string
    field :report_id, :string
    field :retrieved_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @fields ~w(candidate_id donor_name normalized_donor amount_cents date industry source_url report_id retrieved_at)a

  def changeset(contribution, attrs) do
    contribution
    |> cast(attrs, @fields)
    |> validate_required([:candidate_id, :donor_name, :normalized_donor, :amount_cents])
  end
end

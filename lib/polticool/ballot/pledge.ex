defmodule Polticool.Ballot.Pledge do
  use Ecto.Schema
  import Ecto.Changeset

  schema "pledges" do
    field :text, :string
    field :source_url, :string
    field :source_kind, Ecto.Enum, values: [:site, :filing, :news]
    field :quoted_at, :date
    field :issue, :string
    field :specific, :boolean, default: false
    field :rubric_hits, :map, default: %{}
    field :archive_url, :string
    field :retrieved_at, :utc_datetime

    belongs_to :candidate, Polticool.Ballot.Candidate
    has_many :receipts, Polticool.Ballot.Receipt

    timestamps(type: :utc_datetime)
  end

  @fields ~w(candidate_id text source_url source_kind quoted_at issue specific rubric_hits archive_url retrieved_at)a

  def changeset(pledge, attrs) do
    pledge
    |> cast(attrs, @fields)
    |> validate_required([:candidate_id, :text])
    |> assoc_constraint(:candidate)
  end
end

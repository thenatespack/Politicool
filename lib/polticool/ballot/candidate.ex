defmodule Polticool.Ballot.Candidate do
  use Ecto.Schema
  import Ecto.Changeset

  schema "candidates" do
    field :name, :string
    field :party, :string
    field :office, :string
    field :district, :string
    field :race_key, :string
    field :incumbent, :boolean, default: false
    field :result, :string
    field :result_status, :string
    field :site_url, :string
    field :le_code, :string

    has_many :pledges, Polticool.Ballot.Pledge

    timestamps(type: :utc_datetime)
  end

  @fields ~w(name party office district race_key incumbent result result_status site_url le_code)a

  def changeset(candidate, attrs) do
    candidate
    |> cast(attrs, @fields)
    |> validate_required([:name])
  end
end

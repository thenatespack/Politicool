defmodule Polticool.Ballot.LegiscanDataset do
  @moduledoc "Hash of the last imported LegiScan dataset per session (query-budget cache)."
  use Ecto.Schema

  schema "legiscan_datasets" do
    field :session, :string
    field :legiscan_session_id, :integer
    field :dataset_hash, :string
    field :dataset_date, :string
    field :imported_at, :utc_datetime
  end
end

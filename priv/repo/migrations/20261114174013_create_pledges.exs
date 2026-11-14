defmodule Polticool.Repo.Migrations.CreatePledges do
  use Ecto.Migration

  def change do
    create table(:pledges) do
      add :candidate_id, references(:candidates, on_delete: :delete_all), null: false
      add :text, :text, null: false
      add :source_url, :string
      add :source_kind, :string
      add :quoted_at, :date
      add :issue, :string
      add :specific, :boolean, null: false, default: false
      add :rubric_hits, :map, null: false, default: %{}
      add :archive_url, :string
      add :retrieved_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:pledges, [:candidate_id])
    create index(:pledges, [:issue])
  end
end

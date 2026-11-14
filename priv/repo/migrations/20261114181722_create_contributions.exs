defmodule Polticool.Repo.Migrations.CreateContributions do
  use Ecto.Migration

  def change do
    create table(:contributions) do
      add :candidate_id, references(:candidates, on_delete: :delete_all), null: false
      add :donor_name, :string, null: false
      add :normalized_donor, :string, null: false
      add :amount_cents, :bigint, null: false
      add :date, :date
      add :industry, :string
      add :source_url, :string
      add :report_id, :string
      add :retrieved_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:contributions, [:candidate_id])
    create index(:contributions, [:candidate_id, :industry])
    create index(:contributions, [:normalized_donor])
  end
end

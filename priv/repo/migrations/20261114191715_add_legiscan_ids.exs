defmodule Polticool.Repo.Migrations.AddLegiscanIds do
  use Ecto.Migration

  def change do
    alter table(:bills) do
      add :legiscan_bill_id, :integer
    end

    create unique_index(:bills, [:legiscan_bill_id])

    alter table(:votes) do
      add :legiscan_roll_call_id, :integer
    end

    create unique_index(:votes, [:legiscan_roll_call_id])

    alter table(:vote_positions) do
      add :legiscan_people_id, :integer
    end

    create table(:legiscan_datasets) do
      add :session, :string, null: false
      add :legiscan_session_id, :integer
      add :dataset_hash, :string, null: false
      add :dataset_date, :string
      add :imported_at, :utc_datetime, null: false
    end

    create unique_index(:legiscan_datasets, [:session])
  end
end

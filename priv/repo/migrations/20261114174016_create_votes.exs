defmodule Polticool.Repo.Migrations.CreateVotes do
  use Ecto.Migration

  def change do
    create table(:votes) do
      add :bill_id, references(:bills, on_delete: :delete_all), null: false
      add :vote_id, :string, null: false
      add :house, :string
      add :kind, :string, null: false
      add :action_code, :string
      add :action, :string
      add :tally, :map, null: false, default: %{}
      add :date, :date
      add :url, :string

      timestamps(type: :utc_datetime)
    end

    create index(:votes, [:bill_id])
    create unique_index(:votes, [:bill_id, :vote_id, :house])
  end
end

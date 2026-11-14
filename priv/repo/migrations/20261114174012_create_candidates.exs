defmodule Polticool.Repo.Migrations.CreateCandidates do
  use Ecto.Migration

  def change do
    create table(:candidates) do
      add :name, :string, null: false
      add :party, :string
      add :office, :string
      add :district, :string
      add :race_key, :string
      add :incumbent, :boolean, null: false, default: false
      add :result, :string
      add :result_status, :string
      add :site_url, :string
      add :le_code, :string

      timestamps(type: :utc_datetime)
    end

    create index(:candidates, [:race_key])
    create index(:candidates, [:le_code])
  end
end

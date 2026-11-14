defmodule Polticool.Repo.Migrations.AddExternalIdToContributions do
  use Ecto.Migration

  def change do
    alter table(:contributions) do
      add :external_id, :string
    end

    # NULLs are distinct in Postgres, so hand-entered rows without an id are unaffected.
    create unique_index(:contributions, [:candidate_id, :external_id])
  end
end

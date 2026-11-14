defmodule Polticool.Repo.Migrations.CreateVotePositions do
  use Ecto.Migration

  def change do
    create table(:vote_positions) do
      add :vote_id, references(:votes, on_delete: :delete_all), null: false
      add :legislator_code, :string, null: false
      add :legislator_name, :string
      add :position, :string, null: false
    end

    create unique_index(:vote_positions, [:vote_id, :legislator_code])
    create index(:vote_positions, [:legislator_code])
  end
end

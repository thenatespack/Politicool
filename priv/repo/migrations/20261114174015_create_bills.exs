defmodule Polticool.Repo.Migrations.CreateBills do
  use Ecto.Migration

  def change do
    create table(:bills) do
      add :session, :string, null: false
      add :number, :string, null: false
      add :title, :text
      add :prime_sponsor, :string
      add :floor_sponsor, :string
      add :sponsors, {:array, :string}, null: false, default: []
      add :provisions, :text
      add :versions, {:array, :map}, null: false, default: []
      add :url, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:bills, [:session, :number])
  end
end

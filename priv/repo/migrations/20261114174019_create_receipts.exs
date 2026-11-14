defmodule Polticool.Repo.Migrations.CreateReceipts do
  use Ecto.Migration

  def change do
    create table(:receipts) do
      add :pledge_id, references(:pledges, on_delete: :delete_all), null: false
      add :bill_id, references(:bills, on_delete: :nilify_all)
      add :vote_id, references(:votes, on_delete: :nilify_all)
      add :outcome, :string, null: false, default: "untested"
      add :confidence, :string
      add :trap, :boolean, null: false, default: false
      add :rationale, :text
      add :citations, {:array, :map}, null: false, default: []
      add :verified, :boolean, null: false, default: false
      add :track_record, :boolean, null: false, default: false
      add :quote, :text
      add :source_url, :string
      add :bill_title, :text
      add :bill_summary, :text
      add :vote_position, :string
      add :tally, :string
      add :retrieved_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:receipts, [:pledge_id])
    create index(:receipts, [:bill_id])
    create index(:receipts, [:vote_id])
  end
end

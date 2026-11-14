defmodule Polticool.Repo.Migrations.UnverifyAiMatchedReceipts do
  use Ecto.Migration

  # Matching used to store AI-matched receipts with verified: true, which the UI
  # renders as "Human-verified". No receipt has been hand-checked yet (#911), so
  # clear the flag everywhere. Human verification sets it again later.
  def up do
    execute("UPDATE receipts SET verified = false WHERE verified = true")
  end

  def down, do: :ok
end

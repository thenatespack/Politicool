defmodule Polticool.Repo.Migrations.FixResolutionNumbers do
  use Ecto.Migration

  # HJR0010 -> HJR010 etc. (le.utah.gov codes are 6 characters). Merges into an
  # existing correctly numbered bill when there is one. See LegiScan.Repair.
  def up do
    flush()
    Polticool.LegiScan.Repair.fix_resolution_numbers(repo())
  end

  def down, do: :ok
end

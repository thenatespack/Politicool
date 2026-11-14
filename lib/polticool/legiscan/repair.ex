defmodule Polticool.LegiScan.Repair do
  @moduledoc """
  Data repairs for rows created by earlier LegiScan imports.

  Schemaless on purpose (raw SQL) so it keeps working as app schemas change.
  """

  @doc """
  le.utah.gov codes are 6 characters (`HJR010`), but the first import padded
  3-letter prefixes to 4 numerals (`HJR0010`). Renames those bills, or merges them
  into the correctly numbered bill when one already exists (votes, vote
  positions and receipts are re-pointed, then the bad row is deleted).

  Idempotent. Takes a repo module so it can run from a migration.
  """
  def fix_resolution_numbers(repo) do
    %{rows: rows} =
      repo.query!(
        "SELECT id, session, number FROM bills WHERE number ~ '^[A-Z]{3}0[0-9]{3}$' ORDER BY id"
      )

    Enum.each(rows, fn [id, session, number] ->
      <<prefix::binary-size(3), "0", rest::binary>> = number
      correct = prefix <> rest

      case repo.query!("SELECT id FROM bills WHERE session = $1 AND number = $2", [
             session,
             correct
           ]) do
        %{rows: []} ->
          repo.query!("UPDATE bills SET number = $1 WHERE id = $2", [correct, id])

        %{rows: [[keep_id]]} ->
          merge(repo, id, keep_id)
      end
    end)

    :ok
  end

  defp merge(repo, old_id, keep_id) do
    %{rows: votes} =
      repo.query!("SELECT id, vote_id, house FROM votes WHERE bill_id = $1 ORDER BY id", [old_id])

    Enum.each(votes, fn [vote_pk, vote_id, house] ->
      conflict =
        if house do
          repo.query!(
            "SELECT id FROM votes WHERE bill_id = $1 AND vote_id = $2 AND house = $3",
            [keep_id, vote_id, house]
          ).rows
        else
          []
        end

      case conflict do
        [] ->
          repo.query!("UPDATE votes SET bill_id = $1 WHERE id = $2", [keep_id, vote_pk])

        [[keep_vote]] ->
          merge_vote(repo, vote_pk, keep_vote)
      end
    end)

    repo.query!("UPDATE receipts SET bill_id = $1 WHERE bill_id = $2", [keep_id, old_id])

    # Capture, clear (unique index), then fill blanks on the kept row.
    %{rows: [[legiscan_id, title, provisions, url]]} =
      repo.query!("SELECT legiscan_bill_id, title, provisions, url FROM bills WHERE id = $1", [
        old_id
      ])

    repo.query!("UPDATE bills SET legiscan_bill_id = NULL WHERE id = $1", [old_id])

    repo.query!(
      """
      UPDATE bills SET
        legiscan_bill_id = COALESCE(legiscan_bill_id, $2),
        title = CASE WHEN title IS NULL OR title = '' THEN $3 ELSE title END,
        provisions = CASE WHEN provisions IS NULL OR provisions = '' THEN $4 ELSE provisions END,
        url = CASE WHEN url IS NULL OR url = '' THEN $5 ELSE url END
      WHERE id = $1
      """,
      [keep_id, legiscan_id, title, provisions, url]
    )

    repo.query!("DELETE FROM bills WHERE id = $1", [old_id])
  end

  defp merge_vote(repo, old_vote, keep_vote) do
    repo.query!(
      """
      UPDATE vote_positions SET vote_id = $1
      WHERE vote_id = $2
        AND legislator_code NOT IN (SELECT legislator_code FROM vote_positions WHERE vote_id = $1)
      """,
      [keep_vote, old_vote]
    )

    repo.query!("UPDATE receipts SET vote_id = $1 WHERE vote_id = $2", [keep_vote, old_vote])

    %{rows: [[roll_call_id]]} =
      repo.query!("SELECT legiscan_roll_call_id FROM votes WHERE id = $1", [old_vote])

    repo.query!("UPDATE votes SET legiscan_roll_call_id = NULL WHERE id = $1", [old_vote])

    repo.query!(
      "UPDATE votes SET legiscan_roll_call_id = COALESCE(legiscan_roll_call_id, $2) WHERE id = $1",
      [keep_vote, roll_call_id]
    )

    # Remaining (duplicate) positions go with the old vote via on_delete: :delete_all.
    repo.query!("DELETE FROM votes WHERE id = $1", [old_vote])
  end
end

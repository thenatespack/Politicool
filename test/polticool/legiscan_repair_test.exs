defmodule Polticool.LegiScan.RepairTest do
  use Polticool.DataCase, async: true

  alias Polticool.LegiScan.Repair
  alias Polticool.Repo

  defp q(sql, params \\ []), do: Repo.query!(sql, params).rows

  defp bill(session, number, extra \\ []) do
    [[id]] =
      q(
        """
        INSERT INTO bills (session, number, title, legiscan_bill_id, inserted_at, updated_at)
        VALUES ($1, $2, $3, $4, now(), now()) RETURNING id
        """,
        [session, number, extra[:title], extra[:legiscan_id]]
      )

    id
  end

  defp vote(bill_id, vote_id, roll_call_id \\ nil) do
    [[id]] =
      q(
        """
        INSERT INTO votes (bill_id, vote_id, house, kind, tally, legiscan_roll_call_id, inserted_at, updated_at)
        VALUES ($1, $2, 'H', 'floor', '{}', $3, now(), now()) RETURNING id
        """,
        [bill_id, vote_id, roll_call_id]
      )

    id
  end

  defp position(vote_id, code),
    do:
      q(
        "INSERT INTO vote_positions (vote_id, legislator_code, position) VALUES ($1, $2, 'yea')",
        [
          vote_id,
          code
        ]
      )

  defp receipt(bill_id, vote_id) do
    [[cand]] =
      q(
        "INSERT INTO candidates (name, inserted_at, updated_at) VALUES ('X', now(), now()) RETURNING id"
      )

    [[pledge_id]] =
      q(
        "INSERT INTO pledges (candidate_id, text, inserted_at, updated_at) VALUES ($1, 't', now(), now()) RETURNING id",
        [cand]
      )

    [[id]] =
      q(
        """
        INSERT INTO receipts (pledge_id, bill_id, vote_id, inserted_at, updated_at)
        VALUES ($1, $2, $3, now(), now()) RETURNING id
        """,
        [pledge_id, bill_id, vote_id]
      )

    id
  end

  test "renames when no correctly numbered bill exists, and is idempotent" do
    id = bill("2026GS", "SJR0007")
    ok = bill("2026GS", "HB0216")

    assert :ok = Repair.fix_resolution_numbers(Repo)
    assert :ok = Repair.fix_resolution_numbers(Repo)

    assert [["SJR007"]] = q("SELECT number FROM bills WHERE id = $1", [id])
    assert [["HB0216"]] = q("SELECT number FROM bills WHERE id = $1", [ok])
  end

  test "merges into the existing bill, moving votes, positions and receipts" do
    keep = bill("2025GS", "HJR010", title: "Amendment A")
    old = bill("2025GS", "HJR0010", title: "other", legiscan_id: 555)

    # Non-conflicting vote moves over.
    moved = vote(old, "ROLL1", 11)
    position(moved, "AAA")

    # Conflicting vote (same vote_id + house) is merged into the kept one.
    kept_vote = vote(keep, "ROLL2")
    dup_vote = vote(old, "ROLL2", 22)
    position(kept_vote, "BBB")
    position(dup_vote, "BBB")
    position(dup_vote, "CCC")

    r1 = receipt(old, dup_vote)
    r2 = receipt(old, nil)

    assert :ok = Repair.fix_resolution_numbers(Repo)

    assert [] = q("SELECT 1 FROM bills WHERE id = $1", [old])

    assert [[555, "Amendment A"]] =
             q("SELECT legiscan_bill_id, title FROM bills WHERE id = $1", [keep])

    assert [[^keep]] = q("SELECT bill_id FROM votes WHERE id = $1", [moved])
    assert [["AAA"]] = q("SELECT legislator_code FROM vote_positions WHERE vote_id = $1", [moved])
    assert [] = q("SELECT 1 FROM votes WHERE id = $1", [dup_vote])

    assert [["BBB"], ["CCC"]] =
             q(
               "SELECT legislator_code FROM vote_positions WHERE vote_id = $1 ORDER BY 1",
               [kept_vote]
             )

    assert [[22]] = q("SELECT legiscan_roll_call_id FROM votes WHERE id = $1", [kept_vote])

    assert [[^keep, ^kept_vote]] = q("SELECT bill_id, vote_id FROM receipts WHERE id = $1", [r1])
    assert [[^keep, nil]] = q("SELECT bill_id, vote_id FROM receipts WHERE id = $1", [r2])
  end

  test "is a no-op with nothing to fix" do
    assert :ok = Repair.fix_resolution_numbers(Repo)
  end
end

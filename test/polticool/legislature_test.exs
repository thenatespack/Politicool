defmodule Polticool.LegislatureTest do
  use Polticool.DataCase, async: true

  alias Polticool.Legislature

  @fixtures Path.expand("../support/fixtures", __DIR__)

  defp fixture(name), do: @fixtures |> Path.join(name) |> File.read!()
  defp fixture_json(name), do: name |> fixture() |> Jason.decode!()

  test "parse_votes keeps real votes and skips circled/uncircled and voice votes" do
    votes = Legislature.parse_votes("2026GS", fixture_json("2026GS_HB0001.json"))

    assert [
             %{
               vote_id: "81",
               house: "H",
               kind: :floor,
               tally: %{"yea" => 71, "nay" => 0, "absent" => 4}
             },
             %{vote_id: "127", house: "S", kind: :floor}
           ] = votes
  end

  test "parse_votes classifies committee votes" do
    votes = Legislature.parse_votes("2026GS", fixture_json("2026GS_HB0023.json"))
    committee = Enum.filter(votes, &(&1.kind == :committee))

    assert Enum.map(committee, & &1.action_code) == ["HCASUB", "HCAFAV", "SCAFAV"]
    assert Enum.all?(committee, &(&1.house in ["H", "S"]))
    assert %{"yea" => 8, "nay" => 0, "absent" => 3} = hd(committee).tally
    assert length(votes) == 6
  end

  test "ingest_bill fetches via stub and stores bill, sponsors, versions and votes" do
    Req.Test.stub(Legislature, fn conn ->
      assert conn.request_path == "/data/2026GS/HB0023.json"
      Plug.Conn.send_resp(conn, 200, fixture("2026GS_HB0023.json"))
    end)

    assert {:ok, bill} =
             Legislature.ingest_bill("2026GS", "HB0023", plug: {Req.Test, Legislature})

    assert bill.title == "Service Animal Amendments"
    assert bill.prime_sponsor == "LISONK"
    assert bill.floor_sponsor == "WEILET"
    assert bill.sponsors == ["LISONK", "WEILET"]
    assert bill.provisions =~ "service animals"
    assert length(bill.versions) == 2
    assert length(bill.votes) == 6
    assert Enum.any?(bill.votes, fn v -> v.kind == :floor and v.url =~ "svotes.jsp" end)
  end

  test "backfill_text fills text on an existing bill without touching votes or LegiScan ids" do
    bill =
      Polticool.Repo.insert!(%Polticool.Ballot.Bill{
        session: "2026GS",
        number: "HB0023",
        title: "From LegiScan",
        prime_sponsor: "LISONK",
        legiscan_bill_id: 999
      })

    Req.Test.stub(Legislature, fn conn ->
      Plug.Conn.send_resp(conn, 200, fixture("2026GS_HB0023.json"))
    end)

    assert {:ok, updated} = Legislature.backfill_text(bill, plug: {Req.Test, Legislature})
    assert updated.provisions =~ "service animals"
    assert length(updated.versions) == 2
    assert updated.legiscan_bill_id == 999
    assert updated.title == "From LegiScan"
    assert updated.floor_sponsor == "WEILET"
    assert Polticool.Repo.aggregate(Polticool.Ballot.Vote, :count) == 0
  end

  test "Release.backfill_bill_text only fetches the sponsor's bills that lack text" do
    Polticool.Repo.insert!(%Polticool.Ballot.Bill{
      session: "2026GS",
      number: "HB0023",
      prime_sponsor: "LISONK"
    })

    Polticool.Repo.insert!(%Polticool.Ballot.Bill{
      session: "2026GS",
      number: "HB0099",
      prime_sponsor: "LISONK",
      provisions: "already has text"
    })

    Polticool.Repo.insert!(%Polticool.Ballot.Bill{
      session: "2026GS",
      number: "HB0100",
      prime_sponsor: "OTHERX"
    })

    Req.Test.stub(Legislature, fn conn ->
      assert conn.request_path == "/data/2026GS/HB0023.json"
      Plug.Conn.send_resp(conn, 200, fixture("2026GS_HB0023.json"))
    end)

    ExUnit.CaptureIO.capture_io(fn ->
      assert %{ok: 1} =
               Polticool.Release.backfill_bill_text("LISONK",
                 delay_ms: 0,
                 plug: {Req.Test, Legislature}
               )
    end)

    assert Legislature.get_bill("2026GS", "HB0023").provisions =~ "service animals"
  end

  test "ingest is idempotent" do
    json = fixture_json("2026GS_HB0023.json")
    {:ok, _} = Legislature.ingest_json("2026GS", "HB0023", json)
    {:ok, _} = Legislature.ingest_json("2026GS", "HB0023", json)

    bill = Legislature.get_bill("2026GS", "HB0023")
    assert length(bill.votes) == 6
  end

  test "http errors are returned" do
    Req.Test.stub(Legislature, &Plug.Conn.send_resp(&1, 404, "nope"))

    assert {:error, {:http_status, 404}} =
             Legislature.ingest_bill("2026GS", "HB9999", plug: {Req.Test, Legislature})
  end

  test "parse_bill_search splits sponsored and floor-sponsored bills, skips unnumbered" do
    bills = Legislature.parse_bill_search(fixture("billsearch_2026GS_THURSNK.html"))
    by_role = Enum.group_by(bills, & &1.role, & &1.number)

    assert length(by_role[:sponsor]) == 10
    assert "HB0022" in by_role[:sponsor]
    assert "HJR010" in by_role[:sponsor]
    assert by_role[:floor_sponsor] == ~w(SJR007 SB0229 SB0175 SB0154 SB0147 SB0005)
    refute Map.has_key?(by_role, :cosponsor)

    assert %{title: "Vintage Vehicle Amendments"} = Enum.find(bills, &(&1.number == "HB0022"))
  end

  test "sponsored_bills fetches the legislator's bill search page" do
    html = fixture("billsearch_2026GS_THURSNK.html")

    Req.Test.stub(Legislature, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.params["rep"] == "THURSNK"
      assert conn.params["sess"] == "2026GS"
      Plug.Conn.send_resp(conn, 200, html)
    end)

    assert {:ok, bills} =
             Legislature.sponsored_bills("2026GS", "THURSNK", plug: {Req.Test, Legislature})

    assert length(bills) == 16
  end
end

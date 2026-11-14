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
end

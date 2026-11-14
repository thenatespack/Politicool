defmodule Polticool.Ballot.RollCallTest do
  use Polticool.DataCase, async: true

  alias Polticool.{Legislators, Repo}
  alias Polticool.Ballot.{Bill, RollCall, Vote, VotePosition}

  @fixture Path.expand("../../support/fixtures/svotes_2025GS_852_H.html", __DIR__)
  @roster_fixture Path.expand("../../support/fixtures/legislators.json", __DIR__)

  setup do
    bill = Repo.insert!(%Bill{session: "2025GS", number: "HJR010"})
    vote = Repo.insert!(%Vote{bill_id: bill.id, vote_id: "852", house: "H", kind: :floor})

    roster =
      @roster_fixture
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("legislators")
      |> Legislators.build_roster()

    %{vote: vote, html: File.read!(@fixture), roster: roster}
  end

  test "parse extracts yea/nay/absent lists", %{html: html} do
    entries = RollCall.parse(html)
    assert Enum.frequencies_by(entries, & &1.position) == %{yea: 70, absent: 5}
    assert %{name: "Thompson, J.", position: :yea} in entries
    assert %{name: "Thurston, N.", position: :absent} in entries
  end

  test "roster maps roll-call names to real codes", %{roster: roster} do
    assert Legislators.code_for("Thurston, N.", roster, "H") == "THURSNK"
    assert Legislators.code_for("Thompson, J.", roster, "H") == "THOMJA"
    assert Legislators.code_for("Miller, G.", roster, "H") == "MILLGR"
    assert Legislators.code_for("Miller, T.", roster, "H") == "MILLET"
    assert Legislators.code_for("Whyte, S.", roster, "H") == "WHYTESL"
    assert Legislators.code_for("Loubet, A.", roster) == "LOUBEA"
  end

  test "store writes positions per legislator and tally", %{
    vote: vote,
    html: html,
    roster: roster
  } do
    assert {:ok, rows} = RollCall.store(vote, html, roster: roster)
    assert length(rows) == 75

    pos = fn code ->
      Repo.get_by!(VotePosition, vote_id: vote.id, legislator_code: code).position
    end

    assert pos.("THOMJA") == :yea
    assert pos.("THURSNK") == :absent
    assert pos.("MILLGR") == :yea
    assert pos.("MILLET") == :yea
    assert Repo.reload!(vote).tally == %{"yea" => 70, "absent" => 5}

    assert {:ok, _} = RollCall.store(vote, html, roster: roster)
    assert Repo.aggregate(VotePosition, :count) == 75
  end

  test "sync_vote fetches via Req.Test stub", %{vote: vote, html: html} do
    Req.Test.stub(__MODULE__, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.params["sessionid"] == "2025GS"
      assert conn.params["voteid"] == "852"
      assert conn.params["house"] == "H"
      Plug.Conn.send_resp(conn, 200, html)
    end)

    assert {:ok, rows} = RollCall.sync_vote(vote, req_options: [plug: {Req.Test, __MODULE__}])
    assert length(rows) == 75
  end

  test "sync_vote surfaces http errors", %{vote: vote} do
    Req.Test.stub(__MODULE__, &Plug.Conn.send_resp(&1, 500, "boom"))

    assert {:error, {:http, 500}} =
             RollCall.sync_vote(vote, req_options: [plug: {Req.Test, __MODULE__}])
  end
end

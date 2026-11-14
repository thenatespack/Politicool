defmodule Polticool.LegislatorsTest do
  use ExUnit.Case, async: true

  alias Polticool.Legislators

  @fixture Path.expand("../support/fixtures/legislators.json", __DIR__)

  setup do
    %{body: File.read!(@fixture)}
  end

  test "build_roster keys by chamber and by unambiguous name", %{body: body} do
    roster = body |> Jason.decode!() |> Map.fetch!("legislators") |> Legislators.build_roster()

    assert roster[{"H", "thurston, n"}] == "THURSNK"
    assert roster["thurston, n"] == "THURSNK"
    assert Legislators.code_for("Thurston, Norman K", roster) == "THURSNK"
  end

  test "code_for falls back to a derived guess for unknown names" do
    assert Legislators.code_for("Nobody, X.", %{}) == "NOBODX"
    assert Legislators.code_for("Miller, G.", %{"miller, g" => "XX"}) == "XX"
  end

  test "fetch_roster via Req.Test stub", %{body: body} do
    Req.Test.stub(__MODULE__, &Plug.Conn.send_resp(&1, 200, body))

    assert {:ok, roster} = Legislators.fetch_roster(plug: {Req.Test, __MODULE__})
    assert roster[{"H", "whyte, s"}] == "WHYTESL"
  end

  test "fetch_roster surfaces http errors" do
    Req.Test.stub(__MODULE__, &Plug.Conn.send_resp(&1, 503, "down"))

    assert {:error, {:http_status, 503}} =
             Legislators.fetch_roster(plug: {Req.Test, __MODULE__})
  end
end

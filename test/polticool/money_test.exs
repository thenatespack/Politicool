defmodule Polticool.MoneyTest do
  use Polticool.DataCase, async: true

  alias Polticool.{Anthropic, Money, Repo}
  alias Polticool.Ballot.Candidate

  @csv File.read!("test/support/fixtures/money_contributions.csv")

  defp stub_tags do
    Req.Test.stub(Anthropic, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      body = Jason.decode!(raw)
      assert body["model"] == "claude-haiku-5-5"

      tags =
        for "- " <> d <- String.split(hd(body["messages"])["content"], "\n") do
          industry =
            cond do
              d =~ "acme" -> "Real Estate & Construction"
              d =~ "medical" -> "Healthcare"
              true -> "Individual / Retired"
            end

          %{donor: d, industry: industry}
        end

      Req.Test.json(conn, %{
        "content" => [%{"type" => "tool_use", "input" => %{"tags" => tags}}]
      })
    end)
  end

  test "normalize_donor/1" do
    assert Money.normalize_donor("ACME HOMES, L.L.C.") == "acme homes"
    assert Money.normalize_donor("Doe, Jane Q.") == "jane q doe"
  end

  test "parse_csv/1 handles quotes, dates, amounts and skips bad amounts" do
    rows = Money.parse_csv(@csv)
    assert length(rows) == 4
    assert [%{amount_cents: 100_000, date: ~D[2026-05-01], report_id: "2026 Primary"} | _] = rows
    assert Enum.any?(rows, &(&1.donor_name == ~s(Utah Medical "Group", Inc.)))
  end

  test "import and top_industries aggregate by industry" do
    stub_tags()
    {:ok, c} = %Candidate{} |> Candidate.changeset(%{name: "Test Candidate"}) |> Repo.insert()

    assert {:ok, 4} = Money.import_csv(c, @csv, source_url: "test://csv")
    # idempotent re-import
    assert {:ok, 4} = Money.import_csv(c, @csv, source_url: "test://csv")

    assert [
             %{industry: "Healthcare", total: 2000.0, share: hs},
             %{industry: "Real Estate & Construction", total: 1500.0},
             %{industry: "Individual / Retired", total: 250.0}
           ] = Money.top_industries(c, 5)

    assert_in_delta hs, 2000 / 3750, 1.0e-9
    assert length(Money.top_industries(c, 1)) == 1
  end

  describe "real PCC export format" do
    @pcc File.read!("test/support/fixtures/pcc_export.csv")

    test "parse_csv/2 keeps one filer's contributions only" do
      rows = Money.parse_csv(@pcc, filer: "Doe, Jane")
      ids = rows |> Enum.map(& &1.external_id) |> Enum.sort()
      # drops: expenditure 1005, loan 1006, other filer 2001, amended-away 1003
      assert ids == ~w(1001 1002 1004 1007 1008)
      assert Enum.find(rows, &(&1.external_id == "1004")).amount_cents == -10_000
      assert Enum.find(rows, &(&1.external_id == "1001")).date == ~D[2026-01-11]
      assert Money.parse_csv(@pcc, filer: "Roe, Rick") |> length() == 1
    end

    test "filer_name/1 derives Last, First" do
      assert Money.filer_name(%Candidate{name: "Norman K. Thurston"}) == "Thurston, Norman"
    end

    test "import is idempotent and nets refunds" do
      stub_tags()
      {:ok, c} = %Candidate{} |> Candidate.changeset(%{name: "Jane Doe"}) |> Repo.insert()
      opts = [source_url: "test://pcc", filer: Money.filer_name(c)]

      assert {:ok, 5} = Money.import_csv(c, @pcc, opts)
      assert {:ok, 5} = Money.import_csv(c, @pcc, opts)
      # a second file under the same source must not wipe the first
      assert {:ok, 1} = Money.import_csv(c, @pcc, Keyword.put(opts, :filer, "Roe, Rick"))

      assert %{count: 6, cents: 1_189_900} = Money.total_cents(c)

      tops = Money.top_industries(c, 5)
      assert Enum.find(tops, &(&1.industry == "Real Estate & Construction")).total == 1200.0
      assert Enum.find(tops, &(&1.industry == "Healthcare")).total == 400.0
    end
  end

  test "import_json fallback goes through the same pipeline" do
    stub_tags()
    {:ok, c} = %Candidate{} |> Candidate.changeset(%{name: "Fallback"}) |> Repo.insert()

    json = ~s({"donors":[{"donor_name":"Acme Homes","amount":300,"date":"2026-01-02"}]})
    assert {:ok, 1} = Money.import_json(c, json)

    assert [%{industry: "Real Estate & Construction", total: 300.0, share: 1.0}] =
             Money.top_industries(c)
  end
end

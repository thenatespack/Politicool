defmodule Polticool.LegiScanTest do
  use Polticool.DataCase, async: true

  alias Polticool.LegiScan
  alias Polticool.LegiScan.{Import, People}
  alias Polticool.Ballot.{Bill, LegiscanDataset, Vote, VotePosition}

  @roster Polticool.Legislators.build_roster([
            %{"fullName" => "Thurston, Norman K.", "id" => "THURSNK", "house" => "H"},
            %{"fullName" => "Whyte, Stephen L.", "id" => "WHYTESL", "house" => "H"},
            %{"fullName" => "Adams, Jake", "id" => "ADAMSJ", "house" => "S"}
          ])

  defp person(id, last, first, role, district),
    do: %{
      "person" => %{
        "people_id" => id,
        "name" => "#{first} #{last}",
        "first_name" => first,
        "last_name" => last,
        "role" => role,
        "district" => district
      }
    }

  defp bill(id, number, sponsors \\ []),
    do: %{
      "bill" => %{
        "bill_id" => id,
        "bill_number" => number,
        "title" => "Title of #{number}",
        "state_link" => "https://le.utah.gov/#{number}",
        "session" => %{"session_name" => "2026 General Session", "year_start" => 2026},
        "sponsors" => sponsors
      }
    }

  defp roll_call(id, bill_id, chamber, date, desc, votes),
    do: %{
      "roll_call" => %{
        "roll_call_id" => id,
        "bill_id" => bill_id,
        "date" => date,
        "desc" => desc,
        "yea" => Enum.count(votes, &(elem(&1, 1) == 1)),
        "nay" => Enum.count(votes, &(elem(&1, 1) == 2)),
        "nv" => 0,
        "absent" => Enum.count(votes, &(elem(&1, 1) == 4)),
        "chamber" => chamber,
        "votes" => for({p, v} <- votes, do: %{"people_id" => p, "vote_id" => v})
      }
    }

  defp dataset_zip(extra_people \\ []) do
    files = [
      {"UT/2026_General_Session/people/thurston.json",
       person(100, "Thurston", "Norman", "Rep", "HD-062")},
      {"UT/2026_General_Session/people/whyte.json",
       person(101, "Whyte", "Stephen", "Rep", "HD-066")},
      {"UT/2026_General_Session/bill/hb216.json",
       bill(5001, "HB216", [%{"people_id" => 100, "sponsor_type_id" => 1}])},
      {"UT/2026_General_Session/bill/sb7.json", bill(5002, "SB7")},
      {"UT/2026_General_Session/vote/1.json",
       roll_call(9001, 5001, "H", "2026-02-10", "House Third Reading", [{100, 1}, {101, 2}])},
      {"UT/2026_General_Session/vote/2.json",
       roll_call(9002, 5002, "S", "2026-02-11", "Senate Third Reading", [{100, 4}])}
    ]

    {:ok, {_, bin}} =
      :zip.create(
        ~c"ds.zip",
        for({n, m} <- files ++ extra_people, do: {String.to_charlist(n), Jason.encode!(m)}),
        [:memory]
      )

    bin
  end

  defp opts, do: [roster: @roster, overrides: %{}]

  test "normalize_number pads to 4 digits" do
    assert Import.normalize_number("HB216") == "HB0216"
    assert Import.normalize_number("SB7") == "SB0007"
    assert Import.normalize_number("HJR12") == "HJR0012"
    assert Import.normalize_number("HB0216") == "HB0216"
  end

  test "people map via roster by chamber and name; unmapped are listed" do
    people = [
      person(100, "Thurston", "Norman", "Rep", "HD-062")["person"],
      person(102, "Nobody", "Some", "Sen", "SD-001")["person"]
    ]

    assert {%{100 => "THURSNK"}, [%{people_id: 102, name: "Some Nobody"}]} =
             People.resolve(people, @roster)

    assert {%{102 => "ZZZ"}, []} = People.resolve(tl(people), @roster, %{"102" => "ZZZ"})
  end

  test "imports onto an existing bill, matches an existing vote, inserts the rest" do
    bill = Repo.insert!(%Bill{session: "2026GS", number: "HB0216", title: "Existing"})

    existing =
      Repo.insert!(%Vote{
        bill_id: bill.id,
        vote_id: "81",
        house: "H",
        kind: :floor,
        date: ~D[2026-02-10]
      })

    assert {:ok, %{bills: 2, roll_calls: 2, positions: 3}} =
             Import.import_zip(dataset_zip(), opts())

    assert %Bill{legiscan_bill_id: 5001, title: "Existing"} = Repo.get!(Bill, bill.id)
    assert Repo.get_by!(Bill, session: "2026GS", number: "SB0007").legiscan_bill_id == 5002
    assert Repo.aggregate(Bill, :count) == 2

    matched = Repo.get!(Vote, existing.id)
    assert matched.legiscan_roll_call_id == 9001
    assert matched.tally["yea"] == 1

    inserted = Repo.get_by!(Vote, legiscan_roll_call_id: 9002)
    assert inserted.house == "S" and inserted.kind == :floor

    assert %{position: :yea, legiscan_people_id: 100} =
             Repo.get_by!(VotePosition, vote_id: existing.id, legislator_code: "THURSNK")

    assert Repo.get_by!(VotePosition, vote_id: existing.id, legislator_code: "WHYTESL").position ==
             :nay

    assert Repo.get_by!(VotePosition, vote_id: inserted.id, legislator_code: "THURSNK").position ==
             :absent
  end

  test "re-import is idempotent" do
    assert {:ok, _} = Import.import_zip(dataset_zip(), opts())
    counts = fn -> Enum.map([Bill, Vote, VotePosition], &Repo.aggregate(&1, :count)) end
    first = counts.()
    assert {:ok, %{roll_calls: 2}} = Import.import_zip(dataset_zip(), opts())
    assert counts.() == first
    assert first == [2, 2, 3]
  end

  test "unmapped voters fail loudly and write nothing" do
    zip =
      dataset_zip([
        {"UT/x/vote/3.json", roll_call(9003, 5001, "H", "2026-02-12", "x", [{999, 1}])}
      ])

    assert {:error, {:unmapped_people, [%{people_id: 999}]}} = Import.import_zip(zip, opts())
    assert Repo.aggregate(Bill, :count) == 0
  end

  describe "API" do
    setup do
      {:ok, calls: :counters.new(1, [])}
    end

    defp stub_api(calls, hash) do
      Req.Test.stub(LegiScan, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)

        case conn.params["op"] do
          "getDatasetList" ->
            Req.Test.json(conn, %{
              "status" => "OK",
              "datasetlist" => [
                %{
                  "session_id" => 2214,
                  "special" => 0,
                  "year_start" => 2026,
                  "dataset_hash" => hash,
                  "dataset_date" => "2026-11-10",
                  "access_key" => "abc"
                },
                %{"session_id" => 2228, "special" => 1, "year_start" => 2025}
              ]
            })

          "getDataset" ->
            :counters.add(calls, 1, 1)
            assert conn.params["id"] == "2214" and conn.params["access_key"] == "abc"

            Req.Test.json(conn, %{
              "status" => "OK",
              "dataset" => %{"zip" => Base.encode64(dataset_zip())}
            })
        end
      end)
    end

    test "downloads once, then skips while the hash is unchanged", %{calls: calls} do
      stub_api(calls, "h1")
      assert {:ok, [{"2026GS", %{roll_calls: 2}}]} = Import.import_sessions(["2026GS"], opts())

      assert %LegiscanDataset{dataset_hash: "h1"} =
               Repo.get_by!(LegiscanDataset, session: "2026GS")

      assert {:ok, [{"2026GS", :unchanged}]} = Import.import_sessions(["2026GS"], opts())
      assert :counters.get(calls, 1) == 1

      stub_api(calls, "h2")
      assert {:ok, [{"2026GS", %{roll_calls: 2}}]} = Import.import_sessions(["2026GS"], opts())
      assert :counters.get(calls, 1) == 2
    end

    test "API errors and unknown sessions are reported", %{calls: calls} do
      stub_api(calls, "h1")
      assert {:error, {:no_dataset, "2019GS"}} = Import.import_sessions(["2019GS"], opts())

      Req.Test.stub(LegiScan, fn conn ->
        Req.Test.json(conn, %{"status" => "ERROR", "alert" => %{"message" => "Invalid API key"}})
      end)

      assert {:error, {:api, "Invalid API key"}} = LegiScan.dataset_list("UT")
    end
  end
end

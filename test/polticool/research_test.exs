defmodule Polticool.ResearchTest do
  use Polticool.DataCase, async: false

  alias Polticool.{Anthropic, Research}
  alias Polticool.Ballot.{Bill, Candidate, Pledge, Vote, VotePosition}

  @provision "Directs counties to approve residential building permits within 60 days."

  setup do
    Req.Test.set_req_test_to_shared()

    dir = Path.join(System.tmp_dir!(), "research_cache_#{System.unique_integer([:positive])}")
    old = Application.get_env(:polticool, :research_cache_dir)
    Application.put_env(:polticool, :research_cache_dir, dir)

    on_exit(fn ->
      Application.put_env(:polticool, :research_cache_dir, old)
      Application.put_env(:polticool, :research_mode, :live)
      File.rm_rf(dir)
    end)

    {:ok, c} =
      %Candidate{}
      |> Candidate.changeset(%{name: "Norman Thurston", le_code: "THURSNK"})
      |> Repo.insert()

    {:ok, _} =
      %Pledge{}
      |> Pledge.changeset(%{
        candidate_id: c.id,
        text: "Cut permit waits to 60 days.",
        specific: true,
        quoted_at: ~D[2026-06-01]
      })
      |> Repo.insert()

    {:ok, bill} =
      %Bill{}
      |> Bill.changeset(%{
        session: "2025GS",
        number: "HB1",
        title: "Permits",
        provisions: @provision,
        url: "https://le.utah.gov/HB1"
      })
      |> Repo.insert()

    {:ok, v} =
      %Vote{}
      |> Vote.changeset(%{
        bill_id: bill.id,
        vote_id: "V1",
        kind: :floor,
        date: ~D[2026-09-01],
        tally: %{"yea" => 50, "nay" => 20}
      })
      |> Repo.insert()

    Repo.insert!(%VotePosition{vote_id: v.id, legislator_code: "THURSNK", position: :yea})

    Req.Test.stub(Anthropic, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)

      if Jason.decode!(raw)["model"] == Anthropic.sonnet() do
        Req.Test.json(conn, %{
          "content" => [
            %{
              "type" => "text",
              "text" => "It advances.",
              "citations" => [
                %{
                  "type" => "char_location",
                  "cited_text" => @provision,
                  "document_title" => "HB1",
                  "document_index" => 0,
                  "start_char_index" => 10,
                  "end_char_index" => 80
                }
              ]
            }
          ]
        })
      else
        Req.Test.json(conn, %{
          "content" => [
            %{
              "type" => "tool_use",
              "name" => "record_match",
              "input" => %{
                "relation" => "advances",
                "confidence" => "high",
                "rationale" => "Because.",
                "quote" => @provision
              }
            }
          ]
        })
      end
    end)

    %{c: c}
  end

  defp live_opts, do: [ingest: fn _ -> {:ok, 1} end]

  defp drain(acc \\ []) do
    receive do
      {tag, _} = m when tag in [:step, :receipt] -> drain([m | acc])
      {:done, _} = m -> Enum.reverse([m | acc])
      {:failed, _} = m -> Enum.reverse([m | acc])
    after
      5_000 -> flunk("no terminal message, got #{inspect(Enum.reverse(acc))}")
    end
  end

  test "live run broadcasts steps, receipts and a graded scorecard", %{c: c} do
    assert {:ok, run_id} = Research.start("Thurston", live_opts())
    assert is_binary(run_id)

    msgs = drain()
    labels = for {:step, %{label: l, status: :ok}} <- msgs, do: l

    assert labels == [
             "Finding legislator",
             "Pulling bills & votes",
             "Reading campaign pledges",
             "Matching pledge → bill",
             "Following the money",
             "Grading"
           ]

    assert {:step, %{id: "find", status: :running}} = hd(msgs)
    assert [{:receipt, r}] = for({:receipt, _} = m <- msgs, do: m)
    assert r.outcome == :kept and r.vote_position == :yea and r.kind == :voted

    assert {:done, card} = List.last(msgs)
    assert card.grade == "A"
    assert card.candidate.id == c.id
    assert card.receipts_count == 1
  end

  test "step errors broadcast an error step then :failed" do
    assert {:ok, _} = Research.start("THURSNK", ingest: fn _ -> {:error, :timeout} end)
    msgs = drain()

    assert {:step, %{id: "ingest", status: :error}} =
             Enum.find(msgs, &match?({:step, %{status: :error}}, &1))

    assert {:failed, %{reason: ":timeout"}} = List.last(msgs)
  end

  test "ambiguous names return candidates and start nothing", %{c: c} do
    {:ok, other} = %Candidate{} |> Candidate.changeset(%{name: "Nora Thurston"}) |> Repo.insert()

    assert {:ambiguous, list} = Research.start("Thurston", live_opts())
    assert Enum.map(list, & &1.id) == [c.id, other.id]
    refute_receive {:step, _}

    assert {:ok, _} = Research.start(c.id, live_opts())
    assert {:done, _} = List.last(drain())
  end

  test "unknown names are an error" do
    assert {:error, :not_found} = Research.start("Nobody Atall", live_opts())
  end

  test "cached mode replays a recorded run without calling Anthropic" do
    assert {:ok, path, recorded} = Research.record("THURSNK", live_opts())
    assert path == Research.cache_path("THURSNK")

    Application.put_env(:polticool, :research_mode, :cached)
    Req.Test.stub(Anthropic, fn _ -> flunk("cached mode must not call Anthropic") end)

    assert {:ok, _} = Research.start("THURSNK")
    assert drain() == recorded
  end

  test "cached mode without a saved run fails cleanly" do
    Application.put_env(:polticool, :research_mode, :cached)
    assert {:error, :not_found} = Research.start("NOPE")

    assert {:ok, _} = Research.start("THURSNK")
    assert {:failed, %{reason: "no cached run"}} = List.last(drain())
  end
end

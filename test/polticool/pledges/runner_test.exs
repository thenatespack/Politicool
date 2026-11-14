defmodule Polticool.Pledges.RunnerTest do
  use Polticool.DataCase, async: false

  import ExUnit.CaptureIO

  alias Polticool.{Anthropic, Pledges, Repo}
  alias Polticool.Ballot.{Candidate, Pledge, Receipt}
  alias Polticool.Pledges.Runner

  @url "https://example.com/issues"
  @good "I will cut the Utah median home permit wait to 60 days by 2027 by streamlining county review."

  @html """
  <html><head><script>var a = 1;</script></head><body>
  <p>#{@good}</p><p>Other text.</p></body></html>
  """

  setup do
    {:ok, c} =
      %Candidate{}
      |> Candidate.changeset(%{name: "Pat Runner", le_code: "RUNNERP"})
      |> Repo.insert()

    Application.put_env(:polticool, :pledges_req_options, plug: {Req.Test, Pledges})
    on_exit(fn -> Application.delete_env(:polticool, :pledges_req_options) end)

    Req.Test.stub(Pledges, fn conn -> Plug.Conn.send_resp(conn, 200, @html) end)

    Req.Test.stub(Anthropic, fn conn ->
      item = %{
        "quote" => @good,
        "issue" => "housing",
        "rubric" => %{
          "measurable_outcome" => true,
          "mechanism" => true,
          "timeframe" => true,
          "within_office_power" => false
        }
      }

      Req.Test.json(conn, %{
        "content" => [
          %{"type" => "tool_use", "name" => "record_pledges", "input" => %{"pledges" => [item]}}
        ]
      })
    end)

    dir = Path.join(System.tmp_dir!(), "runner_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{candidate: c, dir: dir}
  end

  defp run(c, sources, opts \\ []) do
    {result, out} = with_io(fn -> Runner.run(c, sources, opts) end)
    {result, out}
  end

  test "URL source stores a pledge, resolving by le_code, name and id", %{candidate: c} do
    {{:ok, %{total: 1, failed: 0}}, out} = run("runnerp", [@url])
    assert out =~ "#{@url}: 1 pledges"
    assert out =~ "specific"
    assert [%Pledge{source_url: @url, source_kind: :site}] = Repo.all(Pledge)

    assert {:ok, %{id: id}} = Runner.resolve_candidate("pat runner")
    assert id == c.id
    assert {:ok, _} = Runner.resolve_candidate(Integer.to_string(c.id))
  end

  test "ambiguous and unknown candidates fail clearly", %{candidate: c} do
    {:ok, _} = %Candidate{} |> Candidate.changeset(%{name: "Pat Other"}) |> Repo.insert()
    assert {{:error, {:ambiguous_candidate, "pat", _}}, out} = run("pat", [@url])
    assert out =~ "ambiguous"
    assert {{:error, {:candidate_not_found, "nobody"}}, _} = run("nobody", [@url])
    assert c.id
  end

  test "file source with {path, url} stores the original page URL", %{candidate: c, dir: dir} do
    path = Path.join(dir, "issues.html")
    File.write!(path, @html)

    {{:ok, %{total: 1}}, _} = run(c.id, [{path, @url}])
    assert [%Pledge{source_url: @url}] = Repo.all(Pledge)

    txt = Path.join(dir, "issues.txt")
    File.write!(txt, @good)
    {{:ok, %{total: 1}}, _} = run(c.id, [txt], source_url: "https://example.com/other")
    assert Repo.aggregate(Pledge, :count) == 2
  end

  test "a file without a source URL is refused", %{candidate: c, dir: dir} do
    path = Path.join(dir, "issues.html")
    File.write!(path, @html)

    {{:ok, %{total: 0, failed: 1}}, out} = run(c.id, [path])
    assert out =~ "no source, no claim"
    assert Repo.aggregate(Pledge, :count) == 0
  end

  test "pdf files get a convert-to-text message", %{candidate: c, dir: dir} do
    path = Path.join(dir, "plan.pdf")
    File.write!(path, "%PDF")
    {{:ok, %{failed: 1}}, out} = run(c.id, [{path, @url}])
    assert out =~ "convert it to .txt"
  end

  test "dry run writes nothing", %{candidate: c} do
    {{:ok, %{total: 1}}, out} = run(c.id, [@url], dry_run: true)
    assert out =~ "dry run"
    assert Repo.aggregate(Pledge, :count) == 0
  end

  test "re-running is idempotent and keeps receipts", %{candidate: c} do
    {{:ok, _}, _} = run(c.id, [@url])
    [pledge] = Repo.all(Pledge)
    Repo.insert!(%Receipt{pledge_id: pledge.id, outcome: :kept, rationale: "x"})

    {{:ok, %{total: 1}}, _} = run(c.id, [@url])
    assert [%Pledge{id: id}] = Repo.all(Pledge)
    assert id == pledge.id
    assert Repo.aggregate(Receipt, :count) == 1
  end

  test "replace_seeded removes seeded pledges and receipts after success", %{candidate: c} do
    seeded =
      Repo.insert!(%Pledge{
        candidate_id: c.id,
        text: "Seeded sample",
        rubric_hits: %{"sample" => true}
      })

    Repo.insert!(%Receipt{pledge_id: seeded.id, outcome: :broken, rationale: "SAMPLE"})

    {{:ok, %{removed_seeded: 0}}, _} = run(c.id, [@url], dry_run: true, replace_seeded: true)
    assert Repo.aggregate(Pledge, :count) == 1

    {{:ok, %{removed_seeded: 1}}, out} = run(c.id, [@url], replace_seeded: true)
    assert out =~ "removed 1 seeded pledges and 1 receipts"
    assert [%Pledge{text: @good}] = Repo.all(Pledge)
    assert Repo.aggregate(Receipt, :count) == 0
  end

  test "replace_seeded keeps seeded pledges when extraction fails", %{candidate: c} do
    Repo.insert!(%Pledge{candidate_id: c.id, text: "Seeded", rubric_hits: %{"sample" => true}})
    Req.Test.stub(Pledges, fn conn -> Plug.Conn.send_resp(conn, 500, "no") end)

    {{:ok, %{failed: 1, removed_seeded: 0}}, _} = run(c.id, [@url], replace_seeded: true)
    assert Repo.aggregate(Pledge, :count) == 1
  end
end

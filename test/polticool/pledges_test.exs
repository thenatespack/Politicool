defmodule Polticool.PledgesTest do
  use Polticool.DataCase, async: false

  alias Polticool.{Anthropic, Ballot, Pledges, Repo}
  alias Polticool.Ballot.{Candidate, Pledge}

  @url "https://example.com/issues"
  @good "I will cut the Utah median home permit wait to 60 days by 2027 by streamlining county review."
  @fluff "We'll make Utah a better place for everyone."

  @html """
  <html><head><style>.x{}</style><script>var a = 1;</script></head><body>
  <h1>Issues</h1>
  <p>#{@good}</p>
  <p>We&rsquo;ll make Utah a better place for everyone.</p>
  </body></html>
  """

  defp stub_all(pledges) do
    Req.Test.stub(Pledges, fn conn -> Plug.Conn.send_resp(conn, 200, @html) end)

    Req.Test.stub(Anthropic, fn conn ->
      Req.Test.json(conn, %{
        "content" => [
          %{"type" => "tool_use", "name" => "record_pledges", "input" => %{"pledges" => pledges}}
        ]
      })
    end)
  end

  defp item(quote, issue, hits) do
    %{
      "quote" => quote,
      "issue" => issue,
      "rubric" => Map.new(Pledges.rubric_keys(), &{&1, &1 in hits})
    }
  end

  setup do
    {:ok, c} = %Candidate{} |> Candidate.changeset(%{name: "Test Candidate"}) |> Repo.insert()
    Application.put_env(:polticool, :pledges_req_options, plug: {Req.Test, Pledges})
    on_exit(fn -> Application.delete_env(:polticool, :pledges_req_options) end)
    %{candidate: c}
  end

  test "stores verified pledges, drops hallucinated quotes, flags vague", %{candidate: c} do
    stub_all([
      item(@good, "housing", ~w(measurable_outcome mechanism timeframe)),
      item(@fluff, "other", ~w(within_office_power)),
      item("I will abolish property tax entirely.", "taxes", Pledges.rubric_keys())
    ])

    assert {:ok, %{pledges: [specific, vague], dropped: dropped, vague: 1}} =
             Pledges.extract_from_url(c.id, @url)

    assert dropped == ["I will abolish property tax entirely."]
    assert specific.specific and specific.issue == "housing"
    assert specific.source_url == @url and specific.retrieved_at
    assert specific.rubric_hits["timeframe"] == true
    refute vague.specific

    assert Repo.aggregate(Pledge, :count) == 2
    assert Ballot.scorecard(c).promised == 50.0
  end

  test "rerun replaces earlier pledges for the url; unknown issue becomes other", %{
    candidate: c
  } do
    stub_all([item(@fluff, "bogus", [])])
    assert {:ok, %{pledges: [%{issue: "other"}]}} = Pledges.extract_from_url(c.id, @url)
    assert {:ok, _} = Pledges.extract_from_url(c.id, @url)
    assert Repo.aggregate(Pledge, :count) == 1
  end

  test "http errors are returned", %{candidate: c} do
    Req.Test.stub(Pledges, fn conn -> Plug.Conn.send_resp(conn, 404, "no") end)
    assert {:error, {:http_status, 404}} = Pledges.extract_from_url(c.id, @url)
  end

  test "vague?/1 threshold" do
    assert Pledges.vague?(%{"mechanism" => true})
    refute Pledges.vague?(%{"mechanism" => true, "timeframe" => true})
  end
end

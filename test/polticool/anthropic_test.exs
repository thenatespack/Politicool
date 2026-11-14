defmodule Polticool.AnthropicTest do
  use ExUnit.Case, async: true

  alias Polticool.Anthropic

  test "chat/2 sends documents with citations and cache_control" do
    test_pid = self()

    Req.Test.stub(Anthropic, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:body, Jason.decode!(raw)})
      assert Plug.Conn.get_req_header(conn, "x-api-key") == ["test-key"]
      Req.Test.json(conn, %{"content" => [%{"type" => "text", "text" => "hi"}]})
    end)

    msgs = [
      %{
        role: "user",
        content: [Anthropic.document("bill text", title: "HB1"), %{type: "text", text: "q"}]
      }
    ]

    assert {:ok, %{"content" => _}} =
             Anthropic.chat(msgs, system: "sys", model: Anthropic.haiku(), tools: [%{name: "t"}])

    assert_received {:body, body}
    assert body["model"] == "claude-haiku-5-5"
    assert body["system"] == "sys"
    assert [%{"name" => "t"}] = body["tools"]
    [doc | _] = hd(body["messages"])["content"]
    assert doc["citations"] == %{"enabled" => true}
    assert doc["cache_control"] == %{"type" => "ephemeral"}
  end

  test "chat/2 never sends temperature (current models reject it with a 400)" do
    test_pid = self()

    Req.Test.stub(Anthropic, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:body, Jason.decode!(raw)})
      Req.Test.json(conn, %{"content" => []})
    end)

    assert {:ok, _} = Anthropic.chat([%{role: "user", content: "x"}], temperature: 0)
    assert_received {:body, body}
    refute Map.has_key?(body, "temperature")
  end

  test "chat/2 returns http errors" do
    Req.Test.stub(Anthropic, fn conn ->
      conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"error" => "bad"})
    end)

    assert {:error, {:http, 400, _}} = Anthropic.chat([%{role: "user", content: "x"}])
  end

  test "verify_citations/1" do
    cited = %{"type" => "text", "text" => "a", "citations" => [%{"cited_text" => "x"}]}
    bare = %{"type" => "text", "text" => "b"}
    assert {:ok, [^cited]} = Anthropic.verify_citations(%{"content" => [cited]})
    # Real replies interleave uncited connector text with cited spans.
    assert {:ok, [^bare, ^cited, ^bare]} = Anthropic.verify_citations([bare, cited, bare])
    assert {:error, :uncited, [^bare]} = Anthropic.verify_citations([bare])
  end
end

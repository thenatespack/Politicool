defmodule Polticool.Pledges do
  @moduledoc """
  Extracts campaign pledges from candidate web pages.

  Pipeline: fetch page (Req) -> strip to text -> ask Haiku (forced tool call, JSON)
  for pledges -> **drop any quote that does not appear verbatim in the page text**
  -> score against the specificity rubric -> store.

  ## Rubric

  Each pledge gets four booleans (`rubric_hits`): `measurable_outcome`, `mechanism`,
  `timeframe`, `within_office_power`. A pledge is vague when it hits fewer than
  `vague_threshold/0` (2) of them. The `pledges.specific` column is the inverse of
  vague, and `Polticool.Ballot.scorecard/1` builds the Promised bar from `specific`
  (so vague pledges lower it and are excluded from the testable set).

  Req options for the page fetch come from `config :polticool, :pledges_req_options`
  and the `:req_options` opt (tests use `plug: {Req.Test, Polticool.Pledges}`).
  """

  import Ecto.Query

  alias Polticool.{Anthropic, Repo}
  alias Polticool.Ballot.Pledge

  @issues ~w(housing taxes education healthcare transportation environment public_safety
             economy government_reform immigration other)
  @rubric ~w(measurable_outcome mechanism timeframe within_office_power)
  @vague_threshold 2
  @max_chars 60_000

  def issues, do: @issues
  def rubric_keys, do: @rubric
  def vague_threshold, do: @vague_threshold

  @doc """
  Fetches `url`, extracts and stores pledges for `candidate_id`.

  Returns `{:ok, %{pledges: [%Pledge{}], dropped: [quote], vague: n}}` or `{:error, reason}`.
  Re-running for the same candidate and URL replaces that page's earlier pledges.
  """
  def extract_from_url(candidate_id, url, opts \\ []) do
    with {:ok, html} <- fetch(url, opts),
         text = html_to_text(html),
         {:ok, found} <- extract(text, url) do
      retrieved_at = DateTime.utc_now() |> DateTime.truncate(:second)
      {kept, dropped} = Enum.split_with(found, &verbatim?(&1.quote, text))

      Repo.transaction(fn ->
        Repo.delete_all(
          from p in Pledge, where: p.candidate_id == ^candidate_id and p.source_url == ^url
        )

        pledges = Enum.map(kept, &insert_pledge!(&1, candidate_id, url, retrieved_at))

        %{
          pledges: pledges,
          dropped: Enum.map(dropped, & &1.quote),
          vague: Enum.count(pledges, &(not &1.specific))
        }
      end)
    end
  end

  defp insert_pledge!(item, candidate_id, url, retrieved_at) do
    %Pledge{}
    |> Pledge.changeset(%{
      candidate_id: candidate_id,
      text: item.quote,
      source_url: url,
      source_kind: :site,
      issue: item.issue,
      rubric_hits: item.rubric,
      specific: not vague?(item.rubric),
      retrieved_at: retrieved_at
    })
    |> Repo.insert!()
  end

  @doc "True when fewer than `vague_threshold/0` rubric criteria are hit."
  def vague?(hits), do: Enum.count(hits, fn {_k, v} -> v == true end) < @vague_threshold

  @doc """
  True if `quote` appears in `text` verbatim, ignoring only whitespace runs and
  curly-vs-straight quote/apostrophe differences.
  """
  def verbatim?(quote, text) when is_binary(quote) do
    n = normalize(quote)
    n != "" and String.contains?(normalize(text), n)
  end

  def verbatim?(_, _), do: false

  defp normalize(s) do
    s
    |> String.replace(["‘", "’"], "'")
    |> String.replace(["“", "”"], "\"")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  @doc "Strips scripts, styles and tags from HTML, decoding common entities."
  def html_to_text(html) do
    html
    |> String.replace(~r/<(script|style|noscript|svg)\b.*?<\/\1>/is, " ")
    |> String.replace(~r/<!--.*?-->/s, " ")
    |> String.replace(~r/<\/(p|div|li|h[1-6]|section|tr)>|<br\s*\/?>/i, "\n")
    |> String.replace(~r/<[^>]+>/, " ")
    |> decode_entities()
    |> String.replace(~r/[ \t\r\f]+/, " ")
    |> String.replace(~r/ ?\n ?/, "\n")
    |> String.replace(~r/\n{2,}/, "\n")
    |> String.trim()
  end

  defp decode_entities(s) do
    s
    |> String.replace("&nbsp;", " ")
    |> String.replace(
      ["&rsquo;", "&lsquo;", "&#8217;", "&#8216;", "&#039;", "&#x27;", "&apos;"],
      "'"
    )
    |> String.replace(["&ldquo;", "&rdquo;", "&#8220;", "&#8221;", "&quot;"], "\"")
    |> String.replace(["&ndash;", "&#8211;", "&mdash;", "&#8212;"], "-")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&amp;", "&")
  end

  defp fetch(url, opts) do
    req_opts =
      [url: url, retry: false, receive_timeout: 20_000, decode_body: false]
      |> Keyword.merge(Application.get_env(:polticool, :pledges_req_options, []))
      |> Keyword.merge(Keyword.get(opts, :req_options, []))

    case Req.get(req_opts) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract(text, url) do
    text = String.slice(text, 0, @max_chars)

    messages = [
      %{
        role: "user",
        content:
          "Page URL: #{url}\n\n<page>\n#{text}\n</page>\n\nExtract the candidate's pledges."
      }
    ]

    result =
      Anthropic.chat(messages,
        model: Anthropic.haiku(),
        system: system_prompt(),
        tools: [tool()],
        max_tokens: 4096,
        temperature: 0
      )

    with {:ok, %{"content" => content}} <- result do
      case Enum.find(content, &(&1["type"] == "tool_use" and &1["name"] == "record_pledges")) do
        %{"input" => %{"pledges" => list}} when is_list(list) ->
          {:ok, list |> Enum.map(&parse_item/1) |> Enum.reject(&is_nil/1)}

        _ ->
          {:error, :no_tool_output}
      end
    end
  end

  defp parse_item(%{"quote" => quote} = item) when is_binary(quote) do
    rubric = item["rubric"] || %{}

    %{
      quote: quote,
      issue: if(item["issue"] in @issues, do: item["issue"], else: "other"),
      rubric: Map.new(@rubric, &{&1, rubric[&1] == true})
    }
  end

  defp parse_item(_), do: nil

  defp system_prompt do
    """
    You extract campaign pledges from a candidate's web page. A pledge is a forward-looking
    commitment about what the candidate will do if elected. Ignore biography, endorsements,
    and statements about the opponent.

    Rules:
    - "quote" MUST be copied character-for-character from the page, as one contiguous span. Never paraphrase, merge, or fix typos.
    - "issue" must be one of: #{Enum.join(@issues, ", ")}.
    - "rubric" booleans, true only if the quoted text itself shows it:
      measurable_outcome (a number or checkable result), mechanism (how: a bill, funding source, policy tool),
      timeframe (a date or deadline), within_office_power (the office being sought can actually do this).
    Call record_pledges exactly once.
    """
  end

  defp tool do
    %{
      name: "record_pledges",
      description: "Record the pledges found on the page.",
      input_schema: %{
        type: "object",
        required: ["pledges"],
        properties: %{
          pledges: %{
            type: "array",
            items: %{
              type: "object",
              required: ["quote", "issue", "rubric"],
              properties: %{
                quote: %{type: "string"},
                issue: %{type: "string", enum: @issues},
                rubric: %{
                  type: "object",
                  required: @rubric,
                  properties: Map.new(@rubric, &{&1, %{type: "boolean"}})
                }
              }
            }
          }
        }
      }
    }
  end
end

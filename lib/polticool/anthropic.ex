defmodule Polticool.Anthropic do
  @moduledoc """
  Minimal Req client for the Anthropic Messages API with Citations support.

  Configure via `config :polticool, Polticool.Anthropic, ...` (see runtime.exs):
  `:api_key`, `:base_url`, `:version`, `:req_options` (tests inject
  `plug: {Req.Test, Polticool.Anthropic}`).

  Note: citations on document blocks are incompatible with structured output
  (`output_config.format`); the API returns 400. Tool use is accepted.
  """

  @default_url "https://api.anthropic.com"
  @default_version "2023-06-01"

  def haiku, do: "claude-haiku-5-5"
  def sonnet, do: "claude-sonnet-5-5"

  @doc """
  Builds a document block with citations enabled and prompt caching.

  Options: `:title`, `:context`, `:cache` (default true).
  """
  def document(text, opts \\ []) when is_binary(text) do
    block =
      %{
        type: "document",
        source: %{type: "text", media_type: "text/plain", data: text},
        citations: %{enabled: true}
      }
      |> put_if(:title, opts[:title])
      |> put_if(:context, opts[:context])

    if Keyword.get(opts, :cache, true),
      do: Map.put(block, :cache_control, %{type: "ephemeral"}),
      else: block
  end

  @doc """
  Calls POST /v1/messages.

  `messages` is a list of `%{role:, content:}` (content may be a string or a block list;
  put `document/2` blocks first in the user content). Opts: `:model` (default sonnet),
  `:system` (string or blocks), `:tools`, `:max_tokens`, `:temperature`.
  Returns `{:ok, body}` or `{:error, reason}`.
  """
  def chat(messages, opts \\ []) when is_list(messages) do
    body =
      %{
        model: Keyword.get(opts, :model, sonnet()),
        max_tokens: Keyword.get(opts, :max_tokens, 4096),
        messages: messages
      }
      |> put_if(:system, opts[:system])
      |> put_if(:tools, opts[:tools])
      |> put_if(:temperature, opts[:temperature])

    case config(:api_key, nil) do
      nil -> {:error, :missing_api_key}
      key -> post(body, key)
    end
  end

  defp post(body, key) do
    req =
      Req.new(
        [
          base_url: config(:base_url, @default_url),
          url: "/v1/messages",
          json: body,
          headers: [
            {"x-api-key", key},
            {"anthropic-version", config(:version, @default_version)}
          ],
          receive_timeout: 120_000
        ] ++ config(:req_options, [])
      )

    case Req.post(req) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {:http, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Checks that every non-empty text block carries at least one citation.

  Returns `{:ok, cited_blocks}` or `{:error, :uncited, uncited_blocks}`.
  Accepts a response body or a list of content blocks.
  """
  def verify_citations(%{"content" => content}), do: verify_citations(content)

  def verify_citations(content) when is_list(content) do
    texts =
      Enum.filter(content, fn
        %{"type" => "text", "text" => t} -> String.trim(t) != ""
        _ -> false
      end)

    case Enum.split_with(texts, &(Map.get(&1, "citations") not in [nil, []])) do
      {cited, []} -> {:ok, cited}
      {_cited, uncited} -> {:error, :uncited, uncited}
    end
  end

  defp config(key, default),
    do: :polticool |> Application.get_env(__MODULE__, []) |> Keyword.get(key, default)

  defp put_if(map, _k, nil), do: map
  defp put_if(map, k, v), do: Map.put(map, k, v)
end

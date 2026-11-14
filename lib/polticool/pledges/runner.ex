defmodule Polticool.Pledges.Runner do
  @moduledoc """
  Shared logic for pledge extraction, used by `Polticool.Release.extract_pledges/3`
  (production, no Mix) and `mix polticool.extract_pledges`. Prints with `IO.puts`.

  `candidate` is an id, an `le_code` ("THURSNK") or a name. `sources` is a list of:

    * a URL (`"https://..."`), fetched
    * a local file path (`.html`, `.htm`, `.txt`, `.md`), which also needs the original
      page URL, given as `{path, url}` or via the `source_url:` option (single file only)
    * `{path, url}`

  A file without a source URL is refused: no source means no claim. PDFs are not
  supported (no PDF text library); convert them to text first.

  Options: `dry_run:` (extract and print, write nothing), `replace_seeded:` (after a
  successful extraction, delete the candidate's seeded sample pledges and their
  receipts), `source_url:`, `req_options:`.

  Seeded pledges are the ones `Polticool.Seeds` creates: their `rubric_hits` is
  `%{"sample" => true}`. Extracted pledges always carry the four rubric keys.
  """

  import Ecto.Query

  alias Polticool.{Pledges, Repo}
  alias Polticool.Ballot.{Candidate, Pledge, Receipt}

  @text_exts ~w(.txt .md .markdown)
  @html_exts ~w(.html .htm)

  @doc "Returns `{:ok, summary}` or `{:error, reason}` (also printed)."
  def run(candidate, sources, opts \\ []) do
    with {:ok, cand} <- resolve_candidate(candidate),
         {:ok, sources} <- normalize_sources(List.wrap(sources), opts) do
      dry = opts[:dry_run] == true
      IO.puts("#{cand.name} (id #{cand.id})#{if dry, do: " [dry run: nothing written]"}")

      results = Enum.map(sources, &run_source(cand, &1, opts))

      pledges =
        Enum.flat_map(results, fn
          {:ok, r} -> r.pledges
          _ -> []
        end)

      failed = Enum.count(results, &match?({:error, _}, &1))

      IO.puts("")

      for p <- pledges do
        IO.puts("  #{if p.specific, do: "specific", else: "vague   "}  #{truncate(p.text)}")
      end

      IO.puts(
        "total: #{length(pledges)} pledges from #{length(sources)} sources (#{failed} failed)"
      )

      removed = maybe_remove_seeded(cand, opts, dry, failed, pledges)
      {:ok, %{candidate: cand, total: length(pledges), failed: failed, removed_seeded: removed}}
    else
      {:error, reason} = err ->
        IO.puts("error: #{format_error(reason)}")
        err
    end
  end

  defp maybe_remove_seeded(_cand, opts, _dry, _failed, _pledges) when opts == [], do: 0

  defp maybe_remove_seeded(cand, opts, dry, failed, pledges) do
    cond do
      not Keyword.get(opts, :replace_seeded, false) ->
        0

      dry or failed > 0 or pledges == [] ->
        IO.puts(
          "seeded pledges kept (replace_seeded needs a fully successful, non-dry-run extraction)"
        )

        0

      true ->
        remove_seeded(cand)
    end
  end

  @doc "Resolves an id, le_code or name to a candidate."
  def resolve_candidate(id) when is_integer(id) do
    case Repo.get(Candidate, id) do
      nil -> {:error, {:candidate_not_found, id}}
      c -> {:ok, c}
    end
  end

  def resolve_candidate(ref) when is_binary(ref) do
    ref = String.trim(ref)

    case Integer.parse(ref) do
      {n, ""} -> resolve_candidate(n)
      _ -> by_code_or_name(ref)
    end
  end

  defp by_code_or_name(ref) do
    down = String.downcase(ref)

    exact =
      Repo.all(
        from c in Candidate,
          where: fragment("lower(?)", c.le_code) == ^down or fragment("lower(?)", c.name) == ^down
      )

    matches =
      case exact do
        [] ->
          pattern = "%" <> String.replace(down, ~r/([%_\\])/, "\\\\\\1") <> "%"
          Repo.all(from c in Candidate, where: like(fragment("lower(?)", c.name), ^pattern))

        found ->
          found
      end

    case matches do
      [c] -> {:ok, c}
      [] -> {:error, {:candidate_not_found, ref}}
      many -> {:error, {:ambiguous_candidate, ref, Enum.map(many, &{&1.id, &1.name})}}
    end
  end

  defp normalize_sources([], _), do: {:error, :no_sources}

  defp normalize_sources(sources, opts) do
    files = Enum.count(sources, &(is_binary(&1) and not url?(&1)))

    if opts[:source_url] && files > 1 do
      {:error, :source_url_needs_single_file}
    else
      {:ok, Enum.map(sources, &normalize_source(&1, opts[:source_url]))}
    end
  end

  defp normalize_source({path, url}, _), do: {:file, path, url}
  defp normalize_source(s, url), do: if(url?(s), do: {:url, s}, else: {:file, s, url})

  defp url?(s), do: String.starts_with?(s, ["http://", "https://"])

  defp run_source(cand, {:url, url} = src, opts) do
    report(src, Pledges.extract_from_url(cand.id, url, pass_opts(opts)))
  end

  defp run_source(cand, {:file, path, url} = src, opts) do
    result =
      with :ok <- require_url(path, url),
           {:ok, text} <- read_file(path) do
        Pledges.extract_from_text(cand.id, text, url, pass_opts(opts))
      end

    report(src, result)
  end

  defp pass_opts(opts), do: Keyword.take(opts, [:dry_run, :req_options])

  defp require_url(path, url) when url in [nil, ""], do: {:error, {:missing_source_url, path}}
  defp require_url(_, url), do: if(url?(url), do: :ok, else: {:error, {:bad_source_url, url}})

  defp read_file(path) do
    ext = path |> Path.extname() |> String.downcase()

    cond do
      ext == ".pdf" ->
        {:error, {:pdf_unsupported, path}}

      ext not in (@html_exts ++ @text_exts) ->
        {:error, {:unsupported_file_type, path}}

      true ->
        case File.read(path) do
          {:ok, body} when ext in @html_exts -> {:ok, Pledges.html_to_text(body)}
          {:ok, body} -> {:ok, body}
          {:error, reason} -> {:error, {:file_read, path, reason}}
        end
    end
  end

  defp report(src, result) do
    case result do
      {:ok, %{pledges: p, dropped: d, vague: v}} ->
        IO.puts(
          "#{label(src)}: #{length(p)} pledges (#{v} vague), dropped #{length(d)} unverifiable quotes"
        )

      {:error, reason} ->
        IO.puts("#{label(src)}: FAILED #{format_error(reason)}")
    end

    result
  end

  defp label({:url, url}), do: url
  defp label({:file, path, nil}), do: path
  defp label({:file, path, url}), do: "#{path} (as #{url})"

  defp remove_seeded(cand) do
    seeded =
      from(p in Pledge, where: p.candidate_id == ^cand.id)
      |> Repo.all()
      |> Enum.filter(&Map.has_key?(&1.rubric_hits || %{}, "sample"))

    ids = Enum.map(seeded, & &1.id)
    {receipts, _} = Repo.delete_all(from r in Receipt, where: r.pledge_id in ^ids)
    Repo.delete_all(from p in Pledge, where: p.id in ^ids)

    IO.puts("removed #{length(ids)} seeded pledges and #{receipts} receipts:")
    for p <- seeded, do: IO.puts("  - #{truncate(p.text)}")
    length(ids)
  end

  defp truncate(text) do
    if String.length(text) > 100, do: String.slice(text, 0, 97) <> "...", else: text
  end

  defp format_error({:candidate_not_found, ref}), do: "no candidate matches #{inspect(ref)}"

  defp format_error({:ambiguous_candidate, ref, list}),
    do: "#{inspect(ref)} is ambiguous, use an id or le_code: #{inspect(list)}"

  defp format_error(:no_sources), do: "no sources given"

  defp format_error(:source_url_needs_single_file),
    do: "source_url: only works with one file; use {path, url} tuples"

  defp format_error({:missing_source_url, path}),
    do: "#{path} needs its original page URL ({path, url} or source_url:); no source, no claim"

  defp format_error({:bad_source_url, url}), do: "source URL must be http(s): #{inspect(url)}"

  defp format_error({:pdf_unsupported, path}),
    do: "#{path} is a PDF and no PDF text library is available; convert it to .txt first"

  defp format_error({:unsupported_file_type, path}),
    do: "#{path}: unsupported file type (use .html, .txt or .md)"

  defp format_error({:file_read, path, reason}), do: "cannot read #{path}: #{inspect(reason)}"
  defp format_error(other), do: inspect(other)
end

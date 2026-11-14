defmodule Polticool.Research do
  @moduledoc """
  The live research pipeline: name -> bills & votes -> pledges -> receipts -> grade.
  Progress is broadcast on PubSub topic `"research:RUN_ID"` (see `topic/1`).

  ## API

    * `start(name_or_id, opts \\\\ [])` returns `{:ok, run_id}`,
      `{:ambiguous, [candidate_map]}` or `{:error, reason}`. `name_or_id` is a
      candidate id (integer or digit string), an `le_code` (e.g. `"THURSNK"`) or a
      name fragment. Candidates are `%{id, name, party, office, district, le_code}`;
      when several match, nothing runs and the UI shows a picker, then calls
      `start(candidate.id)`.
    * `subscribe(run_id)` / `topic(run_id)`. `start/2` already subscribes the calling
      process before the work begins (so no message is missed). Pass `subscribe: false`
      to opt out.

  ## Messages (plain tuples sent to the subscriber)

    * `{:step, %{id, label, detail, status}}` where `status` is `:running | :ok | :error`.
      `id` is stable per step, so a step re-sent with `:ok` replaces its `:running` row
      (use it as the stream DOM id).
    * `{:receipt, map}` with `id, pledge_id, pledge_text, bill_title, kind, outcome,
      confidence, possibly_related, track_record, quote, rationale, citations,
      source_url, vote_position, tally`.
    * `{:done, scorecard}` where scorecard is `%{candidate, bars, bars_used, score,
      grade, absence_rate, receipts_count, pledges_count, industries}`.
    * `{:failed, %{reason: string}}` sent last when a step errored (after its `:error`
      step). Exactly one of `:done` / `:failed` ends every run.

  ## Modes

  `config :polticool, :research_mode, :live | :cached`. Cached replays
  `<cache_dir>/<LE_CODE>.etf` (see `mix polticool.record_research`) with
  `config :polticool, :research_replay_delay_ms` between messages (default 700, 0 in test).
  The cache directory is `:research_cache_dir` (default `priv/research_cache`; in
  production set from `RESEARCH_CACHE_DIR`, a persistent volume). Recordings are written
  there. Replay reads it first and falls back to the copy committed under
  `priv/research_cache`.

  Receipts are scored by `Polticool.Scoring`: receipts tied to a floor vote count on the
  Voted bar; track-record (pre-pledge) and possibly-related receipts are untested and
  excluded.
  """

  import Ecto.Query

  alias Polticool.{Legislators, Legislature, Matching, Money, Pledges, Repo, Scoring}
  alias Polticool.Ballot
  alias Polticool.Ballot.{Candidate, Pledge, RollCall}

  @sessions ["2026GS"]

  def topic(run_id), do: "research:#{run_id}"

  def subscribe(run_id), do: Phoenix.PubSub.subscribe(Polticool.PubSub, topic(run_id))

  def mode, do: Application.get_env(:polticool, :research_mode, :live)

  def cache_dir do
    Application.get_env(:polticool, :research_cache_dir) ||
      Application.app_dir(:polticool, "priv/research_cache")
  end

  @doc "The committed fallback directory shipped inside the release."
  def bundled_cache_dir, do: Application.app_dir(:polticool, "priv/research_cache")

  @doc "Where `record/2` writes a run."
  def cache_path(le_code), do: Path.join(cache_dir(), "#{String.upcase(le_code)}.etf")

  @doc "Where replay reads a run: the cache dir first, then the committed copy."
  def read_path(le_code) do
    name = "#{String.upcase(le_code)}.etf"
    primary = Path.join(cache_dir(), name)

    if File.exists?(primary), do: primary, else: Path.join(bundled_cache_dir(), name)
  end

  @doc "Starts a run. See the moduledoc."
  def start(input, opts \\ []) do
    with {:ok, resolved} <- resolve(input) do
      case resolved do
        {:many, list} ->
          {:ambiguous, Enum.map(list, &candidate_map/1)}

        {:one, target} ->
          run_id = Ecto.UUID.generate()
          if Keyword.get(opts, :subscribe, true), do: subscribe(run_id)

          {:ok, _} =
            Task.Supervisor.start_child(Polticool.Research.TaskSupervisor, fn ->
              run(run_id, target, opts)
            end)

          {:ok, run_id}
      end
    end
  end

  # ---- resolution ----

  defp resolve(input) when is_integer(input), do: by_id(input)

  defp resolve(input) when is_binary(input) do
    input = String.trim(input)

    cond do
      input == "" ->
        {:error, :not_found}

      Regex.match?(~r/^\d+$/, input) ->
        by_id(String.to_integer(input))

      true ->
        like = "%" <> String.replace(input, ~r/[%_\\]/, "\\\\\\0") <> "%"

        found =
          Repo.all(
            from c in Candidate,
              where: ilike(c.name, ^like) or c.le_code == ^String.upcase(input),
              order_by: c.id
          )

        case found do
          [one] -> {:ok, {:one, one}}
          [_ | _] = many -> {:ok, {:many, many}}
          [] -> from_cache_or_missing(input)
        end
    end
  end

  defp by_id(id) do
    case Repo.get(Candidate, id) do
      nil -> {:error, :not_found}
      c -> {:ok, {:one, c}}
    end
  end

  # In cached mode a code with a saved run works even with an empty database.
  defp from_cache_or_missing(input) do
    if mode() == :cached and File.exists?(read_path(input)),
      do: {:ok, {:one, String.upcase(input)}},
      else: {:error, :not_found}
  end

  def candidate_map(%Candidate{} = c),
    do: Map.take(c, [:id, :name, :party, :office, :district, :le_code])

  # ---- run ----

  defp run(run_id, target, opts) do
    case mode() do
      :cached -> replay(run_id, target)
      _ -> live(run_id, target, opts)
    end
  rescue
    e ->
      broadcast(run_id, {:step, step("fatal", "Research failed", Exception.message(e), :error)})
      broadcast(run_id, {:failed, %{reason: Exception.message(e)}})
  end

  defp replay(run_id, target) do
    code = if is_binary(target), do: target, else: target.le_code

    with code when is_binary(code) <- code,
         {:ok, bin} <- File.read(read_path(code)) do
      delay = Application.get_env(:polticool, :research_replay_delay_ms, 700)

      # `:safe` only accepts atoms that already exist. Dev and test load modules
      # lazily, so a cached scorecard's atoms (e.g. Scoring's :absence_rate) can be
      # missing and the replay fails. Releases preload modules; do the same here.
      for mod <- Application.spec(:polticool, :modules) || [], do: Code.ensure_loaded(mod)

      for msg <- :erlang.binary_to_term(bin, [:safe]) do
        if delay > 0, do: Process.sleep(delay)
        broadcast(run_id, msg)
      end
    else
      _ ->
        broadcast(
          run_id,
          {:step, step("cache", "Cached run", "No saved run for this legislator", :error)}
        )

        broadcast(run_id, {:failed, %{reason: "no cached run"}})
    end
  end

  defp live(run_id, target, opts) do
    emit = fn msg -> broadcast(run_id, msg) end

    try do
      candidate = find_step(emit, target)
      ingest_step(emit, candidate, opts)
      candidate = pledges_step(emit, candidate, opts)
      receipts = match_step(emit, candidate)
      industries = money_step(emit, candidate)
      grade_step(emit, candidate, receipts, industries)
    catch
      {:step_failed, reason} -> emit.({:failed, %{reason: reason}})
    end
  end

  # Runs `fun` as a step: :running, then :ok (detail from the result) or :error (throws).
  defp step(emit, id, label, running_detail, fun) do
    emit.({:step, step(id, label, running_detail, :running)})

    try do
      case fun.() do
        {:ok, detail, value} ->
          emit.({:step, step(id, label, detail, :ok)})
          value

        {:error, reason} ->
          fail(emit, id, label, reason)
      end
    rescue
      e -> fail(emit, id, label, Exception.message(e))
    end
  end

  defp fail(emit, id, label, reason) do
    reason = if is_binary(reason), do: reason, else: inspect(reason)
    emit.({:step, step(id, label, reason, :error)})
    throw({:step_failed, reason})
  end

  defp step(id, label, detail, status),
    do: %{id: id, label: label, detail: detail, status: status}

  defp find_step(emit, target) do
    step(emit, "find", "Finding legislator", "Looking up the roster", fn ->
      candidate =
        case target do
          %Candidate{} = c -> ensure_le_code(c)
          code -> Repo.get_by(Candidate, le_code: code)
        end

      cond do
        is_nil(candidate) -> {:error, "Legislator not found"}
        is_nil(candidate.le_code) -> {:error, "No legislator code for #{candidate.name}"}
        true -> {:ok, "#{candidate.name} (#{candidate.le_code})", candidate}
      end
    end)
  end

  defp ensure_le_code(%Candidate{le_code: nil} = c) do
    with {:ok, roster} <- Legislators.fetch_roster(),
         code when is_binary(code) <- Legislators.code_for(c.name, roster),
         {:ok, c} <- c |> Candidate.changeset(%{le_code: code}) |> Repo.update() do
      c
    else
      _ -> c
    end
  end

  defp ensure_le_code(c), do: c

  defp ingest_step(emit, candidate, opts) do
    ingest = Keyword.get(opts, :ingest) || (&default_ingest/1)

    step(emit, "ingest", "Pulling bills & votes", "From le.utah.gov", fn ->
      case ingest.(candidate) do
        {:ok, n} -> {:ok, "#{n} bills with votes", :ok}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  # Sequential with a short delay; see `mix polticool.ingest_legislator` for the slow,
  # rate-limit-friendly version.
  defp default_ingest(candidate) do
    delay = Application.get_env(:polticool, :research_ingest_delay_ms, 1000)

    with {:ok, roster} <- Legislators.fetch_roster() do
      bills =
        for session <- @sessions,
            {:ok, sponsored} <- [Legislature.sponsored_bills(session, candidate.le_code)],
            %{number: number, role: role} <- sponsored,
            role != :cosponsor,
            Process.sleep(delay) == :ok,
            {:ok, bill} <- [Legislature.ingest_bill(session, number)],
            do: bill

      for bill <- bills, vote <- bill.votes do
        Process.sleep(delay)
        RollCall.sync_vote(vote, roster: roster)
      end

      {:ok, length(bills)}
    end
  end

  defp pledges_step(emit, candidate, opts) do
    extract = Keyword.get(opts, :extract) || (&default_extract/1)

    step(
      emit,
      "pledges",
      "Reading campaign pledges",
      candidate.site_url || "Stored pledges",
      fn ->
        with :ok <- extract.(candidate) do
          base = from(p in Pledge, where: p.candidate_id == ^candidate.id)
          total = Repo.aggregate(base, :count)
          n = Repo.aggregate(from(p in base, where: p.specific), :count)

          if n == 0,
            do: {:error, "No specific pledges found"},
            else: {:ok, "#{n} specific of #{total} pledges", candidate}
        end
      end
    )
  end

  # Reads the campaign site only when no pledges are stored yet.
  defp default_extract(candidate) do
    cond do
      Repo.exists?(from p in Pledge, where: p.candidate_id == ^candidate.id) -> :ok
      is_nil(candidate.site_url) -> :ok
      true -> with {:ok, _} <- Pledges.extract_from_url(candidate.id, candidate.site_url), do: :ok
    end
  end

  defp match_step(emit, candidate) do
    pledges =
      Repo.all(
        from p in Pledge, where: p.candidate_id == ^candidate.id and p.specific, order_by: p.id
      )

    label = "Matching pledge → bill"
    id_for = fn p -> "match-#{p.id}" end
    counter = :counters.new(1, [])
    announce = fn p -> emit.({:step, step(id_for.(p), label, quote_text(p), :running)}) end

    if first = List.first(pledges), do: announce.(first)

    result =
      try do
        Matching.match_candidate(candidate,
          on_progress: fn {:pledge, p, res} ->
            :counters.add(counter, 1, 1)

            detail =
              "#{quote_text(p)} · #{length(res.receipts)} receipts, #{length(res.rejected)} rejected"

            emit.({:step, step(id_for.(p), label, detail, :ok)})
            for r <- res.receipts, do: emit.({:receipt, receipt_map(r, p)})

            if nxt = Enum.at(pledges, :counters.get(counter, 1)), do: announce.(nxt)
          end
        )
      rescue
        e ->
          if p = Enum.at(pledges, :counters.get(counter, 1)),
            do: emit.({:step, step(id_for.(p), label, Exception.message(e), :error)})

          throw({:step_failed, Exception.message(e)})
      end

    {:ok, %{receipts: receipts}} = result
    receipts
  end

  defp quote_text(p), do: String.slice(p.text, 0, 120)

  defp money_step(emit, candidate) do
    step(emit, "money", "Following the money", "Top donor industries", fn ->
      case Money.top_industries(candidate) do
        [] -> {:ok, "No contribution data", []}
        list -> {:ok, "#{length(list)} industries", list}
      end
    end)
  end

  defp grade_step(emit, candidate, receipts, industries) do
    scorecard =
      step(emit, "grade", "Grading", "Weighing receipts", fn ->
        # Same scorecard as the candidate page, read from what the run persisted.
        sc = Ballot.scorecard(candidate)

        pledges_count =
          Repo.aggregate(from(p in Pledge, where: p.candidate_id == ^candidate.id), :count)

        absence =
          receipts |> Enum.map(&scorable/1) |> Scoring.score() |> Map.fetch!(:absence_rate)

        card = %{
          bars: Map.take(sc, [:voted, :proposed, :promised]),
          bars_used: for(k <- [:voted, :proposed, :promised], sc[k] != nil, do: k),
          score: sc.score,
          grade: sc.grade,
          absence_rate: absence,
          candidate: candidate_map(candidate),
          receipts_count: length(receipts),
          pledges_count: pledges_count,
          industries: industries
        }

        {:ok, "Grade #{card.grade || "n/a"}", card}
      end)

    emit.({:done, scorecard})
  end

  defp scorable(r) do
    kind = if r.vote_id && not r.track_record, do: :voted, else: :proposed
    outcome = if r.track_record, do: :untested, else: r.outcome
    %{kind: kind, outcome: outcome}
  end

  defp receipt_map(r, pledge) do
    %{
      id: r.id,
      pledge_id: r.pledge_id,
      pledge_text: pledge.text,
      bill_title: r.bill_title,
      kind: if(r.vote_id, do: :voted, else: :proposed),
      outcome: r.outcome,
      confidence: r.confidence,
      possibly_related: r.confidence != :high,
      track_record: r.track_record,
      quote: r.quote,
      rationale: r.rationale,
      citations: r.citations,
      source_url: r.source_url,
      vote_position: r.vote_position,
      tally: r.tally
    }
  end

  defp broadcast(run_id, msg), do: Phoenix.PubSub.broadcast(Polticool.PubSub, topic(run_id), msg)

  @doc """
  Runs a pipeline for `input` (call with `:research_mode` `:live`), collects the
  broadcast sequence and writes it to the cache file for its le_code. Returns
  `{:ok, path, messages}` or `{:error, reason}`. A run that ended in `{:failed, _}`
  is not saved.
  """
  def record(input, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 1_800_000)

    case start(input, opts) do
      {:ok, run_id} ->
        msgs = collect(timeout, [])

        case List.last(msgs) do
          {:done, %{candidate: %{le_code: code}}} ->
            path = cache_path(code)
            File.mkdir_p!(Path.dirname(path))
            File.write!(path, :erlang.term_to_binary(msgs))
            {:ok, path, msgs}

          {:failed, %{reason: reason}} ->
            {:error, reason}

          _ ->
            {:error, {:timeout, run_id}}
        end

      {:ambiguous, c} ->
        {:error, {:ambiguous, c}}

      other ->
        other
    end
  end

  defp collect(timeout, acc) do
    receive do
      {:done, _} = m -> Enum.reverse([m | acc])
      {:failed, _} = m -> Enum.reverse([m | acc])
      {tag, _} = m when tag in [:step, :receipt] -> collect(timeout, [m | acc])
    after
      timeout -> Enum.reverse(acc)
    end
  end
end

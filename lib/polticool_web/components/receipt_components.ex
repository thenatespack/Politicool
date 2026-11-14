defmodule PolticoolWeb.ReceiptComponents do
  @moduledoc """
  The receipt card: one pledge traced in three steps, Quote → Bill → Vote
  (UI Views sketch, pages 5a/5b/5c).

  All three steps are rendered on the server. `show_receipt_step/3` switches between them
  in the browser with `Phoenix.LiveView.JS`, so flipping needs no server
  round-trip (it keeps working if the connection drops mid-demo) and works
  on LiveView and controller-rendered pages alike.

  Agreed DOM hooks (the demo test relies on them): the buttons
  "See the bill" and "See the vote", and the outcome badge
  `[data-role=outcome]` shown on the vote step.

  Pledge `rubric_hits` keys are `Polticool.Pledges.rubric_keys/0`
  (`measurable_outcome`, `mechanism`, `timeframe`, `within_office_power`;
  string or atom keys). Missing or unknown keys are left out.
  """
  use Phoenix.Component

  import PolticoolWeb.BadgeComponents

  alias Phoenix.LiveView.JS

  @steps %{1 => "What they said", 2 => "What the bill did", 3 => "How they voted"}

  # Keys match Polticool.Pledges.rubric_keys/0 (a test guards against drift).
  @rubric [
    {"measurable_outcome", :measurable_outcome, "Measurable outcome"},
    {"mechanism", :mechanism, "Mechanism"},
    {"timeframe", :timeframe, "Timeframe"},
    {"within_office_power", :within_office_power, "In office's power"}
  ]

  # Page-turn swing for the step coming into view; skipped for reduced motion.
  @enter {"motion-safe:transition motion-safe:duration-300 motion-safe:ease-out",
          "opacity-0 motion-safe:[transform:rotateY(-14deg)_translateX(12px)]",
          "opacity-100 [transform:none]"}

  @doc """
  Renders a receipt card.

  `receipt` is a `%Polticool.Ballot.Receipt{}`; its `bill` and `vote` are used
  when preloaded, otherwise the receipt's own `bill_title`, `bill_summary`,
  `vote_position` and `tally` fields fill in. `pledge` and `candidate`
  default to the preloaded associations.

  ## Examples

      <.receipt_card id={"receipt-\#{r.id}"} receipt={r} pledge={p} candidate={c} label="HD62 · Water" />
  """
  attr :id, :string, required: true
  attr :receipt, :map, required: true
  attr :pledge, :map, default: nil, doc: "defaults to receipt.pledge when preloaded"
  attr :candidate, :map, default: nil, doc: "defaults to pledge.candidate when preloaded"
  attr :label, :string, default: nil, doc: ~s|context line, e.g. "HD62 · Water"|
  attr :class, :any, default: nil

  def receipt_card(assigns) do
    receipt = assigns.receipt
    pledge = assigns.pledge || loaded(Map.get(receipt, :pledge))
    candidate = assigns.candidate || (pledge && loaded(Map.get(pledge, :candidate)))
    bill = loaded(Map.get(receipt, :bill))
    vote = loaded(Map.get(receipt, :vote))

    assigns =
      assign(assigns,
        pledge: pledge,
        candidate: candidate,
        bill: bill,
        vote: vote,
        quote: receipt.quote || (pledge && pledge.text),
        source: quote_source(pledge),
        rubric: rubric(pledge),
        bill_title: (bill && bill.title) || receipt.bill_title,
        bill_number: bill_number_label(bill),
        bill_url: bill_page_url(bill),
        sponsor_role: sponsor_role(bill, candidate),
        versions: version_labels(bill),
        summary: receipt.bill_summary || (bill && bill.provisions),
        position: position_label(receipt.vote_position),
        vote_kind: vote_kind_label(vote),
        tally: tally_label(receipt, vote),
        vote_date: format_date(vote && vote.date),
        # Seeds keep the roll-call link on the receipt when the vote has none.
        vote_url: safe_url(vote && vote.url) || safe_url(receipt.source_url),
        citations: citation_links(receipt.citations),
        retrieved: format_date(receipt.retrieved_at)
      )

    ~H"""
    <article
      id={@id}
      data-role="receipt"
      aria-roledescription="receipt"
      aria-label={if @label, do: "Receipt: #{@label}", else: "Receipt"}
      class={[
        "rounded-[18px] border border-rule bg-paper p-[22px] text-ink shadow-[0_20px_40px_-12px_rgba(28,27,25,0.35)] [perspective:1200px] motion-safe:animate-[fade-in_250ms_ease-out]",
        @class
      ]}
    >
      <p
        :if={@label}
        class="mb-3 text-[11px] font-medium uppercase tracking-[0.12em] text-faint"
      >
        Receipt · {@label}
      </p>

      <%!-- ① Quote --%>
      <div id={step_id(@id, 1)} role="group" aria-labelledby={heading_id(@id, 1)} class="origin-left">
        <.step_heading id={@id} n={1} />
        <p class="mt-1 text-[12.5px] text-muted">
          <span :if={@candidate}>
            {@candidate.name} <.party_label :if={@candidate.party} party={@candidate.party} />
          </span>
          <span :if={@candidate && @source.phrase} aria-hidden="true">·</span>
          {@source.phrase}
        </p>

        <blockquote
          :if={@quote}
          class="my-4 border-l-[3px] border-accent pl-3.5 font-serif text-[22px] leading-[1.3]"
        >
          “{@quote}”
        </blockquote>

        <ul
          :if={@rubric != []}
          id={"#{@id}-rubric"}
          aria-label="Specificity rubric"
          class="flex flex-wrap gap-1.5"
        >
          <li
            :for={{key, label, hit} <- @rubric}
            data-rubric={key}
            data-hit={to_string(hit)}
            class={[
              "rounded-full border px-2 py-0.5 text-[10.5px]",
              if(hit, do: "border-accent text-accent", else: "border-rule text-ink-soft")
            ]}
          >
            <span aria-hidden="true">{if hit, do: "✓", else: "✗"}</span>
            {label}<span class="sr-only">{if hit, do: ": met", else: ": not met"}</span>
          </li>
        </ul>

        <.secondary_source_badge :if={@source.secondary?} class="mt-2.5" />

        <.source_line :if={@source.url || @source.date || @source.archive_url || @source.retrieved}>
          <span :if={@source.url}><.ext_link href={@source.url}>{@source.host}</.ext_link></span>
          <span :if={@source.date}>{@source.date}</span>
          <span :if={@source.archive_url}>
            <.ext_link href={@source.archive_url}>archived</.ext_link>
          </span>
          <span :if={@source.retrieved}>retrieved {@source.retrieved}</span>
        </.source_line>

        <.step_nav id={@id} n={1} />
      </div>

      <%!-- ② Bill --%>
      <div
        id={step_id(@id, 2)}
        role="group"
        aria-labelledby={heading_id(@id, 2)}
        class="origin-left"
        hidden
      >
        <.step_heading id={@id} n={2} />

        <%= if @bill_title || @bill do %>
          <h3 class="mt-2.5 font-serif text-[21px] leading-[1.2]">{@bill_title}</h3>
          <p :if={@bill_number} class="mt-0.5 text-[12px] text-muted">{@bill_number}</p>
          <span
            :if={@sponsor_role}
            id={"#{@id}-sponsor-role"}
            class="mt-2.5 inline-block rounded-[3px] bg-accent px-1.5 py-0.5 text-[10.5px] font-bold uppercase tracking-[0.04em] text-white"
          >
            {@sponsor_role}
          </span>

          <div
            :if={@summary}
            class="mt-2.5 rounded-[10px] border border-rule bg-surface p-3 text-[13.5px] text-ink"
          >
            <p class="mb-1 text-[10.5px] font-semibold uppercase tracking-[0.1em] text-faint">
              Plain-English summary
            </p>
            {@summary}
          </div>

          <p :if={@versions != []} class="mt-2.5 text-[12px] text-ink-soft">
            Versions: {Enum.join(@versions, " → ")}
          </p>
          <p
            :if={@receipt.trap}
            id={"#{@id}-trap"}
            class="mt-2 inline-block rounded-[3px] bg-notice-tint px-1.5 py-0.5 text-[11px] font-semibold text-notice"
          >
            <span aria-hidden="true">⚠</span>
            A substitute or amendment changed this bill · weighted down
          </p>

          <.source_line :if={@bill_url || @retrieved}>
            <span :if={@bill_url}><.ext_link href={@bill_url}>le.utah.gov bill page</.ext_link></span>
            <span :if={@retrieved}>retrieved {@retrieved}</span>
          </.source_line>
        <% else %>
          <p
            id={"#{@id}-no-bill"}
            class="mt-3 rounded-[10px] border border-dashed border-rule-strong p-3 text-[13.5px] text-muted"
          >
            No related bill on record.
          </p>
        <% end %>

        <.step_nav id={@id} n={2} />
      </div>

      <%!-- ③ Vote --%>
      <div
        id={step_id(@id, 3)}
        role="group"
        aria-labelledby={heading_id(@id, 3)}
        class="origin-left"
        hidden
      >
        <.step_heading id={@id} n={3} />

        <%= if @position || @vote do %>
          <div class="my-3.5 flex items-center gap-3">
            <p
              :if={@position}
              id={"#{@id}-position"}
              class="font-serif text-[30px] font-bold uppercase leading-none"
            >
              {@position}
            </p>
            <p class="text-[12.5px] leading-snug text-muted">
              <span :if={@vote_kind}>{@vote_kind}<br /></span>
              {@tally && "Tally #{@tally}"}<span :if={@tally && @vote_date}> · </span>{@vote_date}
            </p>
          </div>

          <dl class="divide-y divide-rule-soft rounded-[10px] border border-rule bg-surface text-[12.5px]">
            <div :if={@vote && @vote.action} class="flex justify-between gap-3 px-3 py-2">
              <dt class="text-muted">Action</dt>
              <dd class="text-right">{@vote.action}</dd>
            </div>
            <div class="flex justify-between gap-3 px-3 py-2">
              <dt class="text-muted">Before the pledge?</dt>
              <dd id={"#{@id}-timing"} class="text-right">
                {timing_label(@receipt)}
              </dd>
            </div>
          </dl>
        <% else %>
          <p
            id={"#{@id}-no-vote"}
            class="mt-3 rounded-[10px] border border-dashed border-rule-strong p-3 text-[13.5px] text-muted"
          >
            No recorded vote on this.
          </p>
        <% end %>

        <div
          id={"#{@id}-verdict"}
          class="mt-3.5 flex items-start justify-between gap-3 rounded-[10px] border border-rule bg-surface p-3"
        >
          <div>
            <.outcome_badge outcome={@receipt.outcome} size={:lg} />
            <p :if={@receipt.rationale} class="mt-1.5 text-[12px] text-ink-soft">
              {@receipt.rationale}
            </p>
            <p :if={@receipt.outcome == :absent} class="mt-1.5 text-[12px] text-ink-soft">
              Shown, not graded.
            </p>
          </div>
          <p :if={@receipt.confidence} class="shrink-0 text-[11px] text-muted">
            Confidence: {@receipt.confidence}
          </p>
        </div>

        <p class="mt-2.5">
          <.verified_badge :if={@receipt.verified} />
          <span :if={!@receipt.verified} id={"#{@id}-unverified"} class="text-[11.5px] text-muted">
            AI-matched from cited records · not yet human-verified
          </span>
        </p>

        <ul
          :if={@citations != []}
          aria-label="Sources"
          class="mt-2 space-y-0.5 text-[11.5px] text-muted"
        >
          <li :for={{title, url} <- @citations}>
            <.ext_link :if={url} href={url}>{title}</.ext_link>
            <span :if={!url}>{title}</span>
          </li>
        </ul>

        <.source_line :if={@vote_url || @retrieved}>
          <span :if={@vote_url}><.ext_link href={@vote_url}>Roll call</.ext_link></span>
          <span :if={@retrieved}>retrieved {@retrieved}</span>
        </.source_line>

        <.step_nav id={@id} n={3} />
      </div>
    </article>
    """
  end

  @doc """
  JS that shows step `n` of the receipt card `id`, hides the other steps and
  moves focus to the new step's heading so screen readers announce it.
  """
  def show_receipt_step(js \\ %JS{}, id, n) when n in 1..3 do
    1..3
    |> Enum.reduce(js, fn
      ^n, js ->
        js
        |> JS.remove_attribute("hidden", to: "##{step_id(id, n)}")
        |> JS.transition(@enter, to: "##{step_id(id, n)}", time: 300)

      other, js ->
        JS.set_attribute(js, {"hidden", ""}, to: "##{step_id(id, other)}")
    end)
    |> JS.focus(to: "##{heading_id(id, n)}")
  end

  attr :id, :string, required: true
  attr :n, :integer, required: true

  defp step_heading(assigns) do
    assigns = assign(assigns, :title, Map.fetch!(@steps, assigns.n))

    ~H"""
    <h3
      id={heading_id(@id, @n)}
      tabindex="-1"
      class="flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-[0.12em] text-accent focus:outline-none focus-visible:outline-2"
    >
      <span
        aria-hidden="true"
        class="grid size-[18px] place-items-center rounded-full border border-accent text-[10px] leading-none"
      >
        {@n}
      </span>
      <span class="sr-only">Step {@n} of 3:</span>
      {@title}
    </h3>
    """
  end

  attr :id, :string, required: true
  attr :n, :integer, required: true

  defp step_nav(assigns) do
    ~H"""
    <div class="mt-5">
      <div class="mb-3 flex justify-center gap-1.5" aria-hidden="true">
        <span
          :for={i <- 1..3}
          class={[
            "h-2 rounded-full transition-all duration-300",
            if(i == @n, do: "w-[22px] bg-accent", else: "w-2 bg-rule")
          ]}
        />
      </div>
      <div class="flex gap-2">
        <button
          :if={@n > 1}
          type="button"
          phx-click={show_receipt_step(@id, @n - 1)}
          class="rounded-[12px] border border-rule bg-surface px-3.5 py-3 text-[14px] font-medium text-ink-soft transition hover:border-muted hover:text-ink active:scale-[0.98]"
        >
          <span aria-hidden="true">←</span> Back
        </button>
        <button
          :if={@n < 3}
          id={"#{@id}-next-#{@n}"}
          type="button"
          phx-click={show_receipt_step(@id, @n + 1)}
          class="group flex flex-1 items-center justify-center gap-1.5 rounded-[12px] bg-ink px-4 py-3 text-[14px] font-semibold text-paper transition hover:bg-ink-soft active:scale-[0.98]"
        >
          {if @n == 1, do: "See the bill", else: "See the vote"}
          <span aria-hidden="true" class="transition-transform group-hover:translate-x-0.5">→</span>
        </button>
        <button
          :if={@n == 3}
          type="button"
          phx-click={show_receipt_step(@id, 1)}
          class="flex-1 rounded-[12px] border border-rule bg-surface px-4 py-3 text-[14px] font-medium text-ink-soft transition hover:border-muted hover:text-ink active:scale-[0.98]"
        >
          Start over
        </button>
      </div>
    </div>
    """
  end

  # Each segment is a <span>; the "·" separators are drawn between the
  # segments that render, so missing data never leaves a stray dot.
  slot :inner_block, required: true

  defp source_line(assigns) do
    ~H"""
    <p
      data-role="sources"
      class="mt-3 border-t border-rule pt-2.5 text-[11.5px] text-muted [&>span]:whitespace-nowrap [&>span+span]:before:mx-1 [&>span+span]:before:content-['·']"
    >
      {render_slot(@inner_block)}
    </p>
    """
  end

  attr :href, :string, required: true
  slot :inner_block, required: true

  defp ext_link(assigns) do
    ~H"""
    <a
      href={@href}
      target="_blank"
      rel="noopener noreferrer"
      class="py-1 underline decoration-rule-strong underline-offset-2 transition-colors hover:text-accent hover:decoration-accent"
    >
      {render_slot(@inner_block)}<span aria-hidden="true"> ↗</span><span class="sr-only"> (opens in a new tab)</span>
    </a>
    """
  end

  defp step_id(id, n), do: "#{id}-step-#{n}"
  defp heading_id(id, n), do: "#{id}-step-#{n}-heading"

  defp loaded(%Ecto.Association.NotLoaded{}), do: nil
  defp loaded(other), do: other

  defp quote_source(nil),
    do: %{
      phrase: nil,
      url: nil,
      host: nil,
      date: nil,
      archive_url: nil,
      retrieved: nil,
      secondary?: false
    }

  defp quote_source(pledge) do
    url = safe_url(pledge.source_url)
    host = host(url)

    phrase =
      case pledge.source_kind do
        :news -> if host, do: "quoted in #{host}", else: "quoted in the news"
        :site -> "campaign website"
        :filing -> "candidate filing"
        _ -> nil
      end

    %{
      phrase: phrase,
      url: url,
      host: host || "source",
      date: format_date(pledge.quoted_at),
      archive_url: safe_url(pledge.archive_url),
      retrieved: format_date(pledge.retrieved_at),
      secondary?: pledge.source_kind == :news
    }
  end

  defp rubric(nil), do: []

  defp rubric(pledge) do
    hits = pledge.rubric_hits || %{}

    # `value <-` (not `value =`): a match in a `for` filter would drop false hits.
    for {key, atom, label} <- @rubric,
        value <- [Map.get(hits, key, Map.get(hits, atom))],
        not is_nil(value),
        do: {key, label, value in [true, "true", 1, "1", "yes"]}
  end

  defp bill_number_label(nil), do: nil

  defp bill_number_label(bill) do
    [format_bill_number(bill.number), session_label(bill.session)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  @doc false
  def format_bill_number(nil), do: nil

  def format_bill_number(number) do
    case Regex.run(~r/^([A-Z]+?)0*(\d+)$/, number) do
      [_, letters, digits] ->
        Enum.map_join(String.graphemes(letters), &(&1 <> ".")) <> " " <> digits

      _ ->
        number
    end
  end

  @doc false
  def session_label(nil), do: nil

  def session_label(session) do
    case Regex.run(~r/^(\d{4})(GS|S(\d))$/, session) do
      [_, year, "GS"] -> "#{year} General Session"
      [_, year, _, n] -> "#{year} #{ordinal(String.to_integer(n))} Special Session"
      _ -> session
    end
  end

  defp bill_page_url(nil), do: nil

  # Prefer the stored page URL; ingest stores the JSON API URL, so build the
  # public page for General Session bills in that case.
  defp bill_page_url(bill) do
    case safe_url(bill.url) do
      nil -> built_bill_url(bill)
      url -> if String.ends_with?(url, ".json"), do: built_bill_url(bill) || url, else: url
    end
  end

  defp built_bill_url(bill) do
    case Regex.run(~r/^(\d{4})GS$/, bill.session || "") do
      [_, year] when is_binary(bill.number) ->
        "https://le.utah.gov/~#{year}/bills/static/#{bill.number}.html"

      _ ->
        nil
    end
  end

  defp sponsor_role(nil, _candidate), do: nil
  defp sponsor_role(_bill, nil), do: nil

  defp sponsor_role(bill, candidate) do
    code = candidate.le_code && String.upcase(candidate.le_code)
    same? = fn other -> is_binary(other) and String.upcase(other) == code end

    cond do
      is_nil(code) -> nil
      same?.(bill.prime_sponsor) -> "Prime sponsor"
      same?.(bill.floor_sponsor) -> "Floor sponsor"
      Enum.any?(bill.sponsors || [], same?) -> "Cosponsor"
      true -> nil
    end
  end

  defp version_labels(nil), do: []

  defp version_labels(bill) do
    labels =
      (bill.versions || [])
      |> Enum.map(&(&1["subVersion"] || &1[:subVersion]))
      |> Enum.map(&parse_int/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(fn
        0 -> "Original"
        n -> "#{ordinal(n)} Substitute"
      end)

    if length(labels) > 1, do: labels, else: []
  end

  # Absent/NV and Untested never count toward a grade, so never claim they do.
  defp timing_label(%{track_record: true}), do: "Yes · context only, not graded"
  defp timing_label(%{outcome: outcome}) when outcome in [:absent, :untested], do: "No"
  defp timing_label(_receipt), do: "No · counts toward the grade"

  defp position_label(:yea), do: "Yea"
  defp position_label(:nay), do: "Nay"
  defp position_label(:absent), do: "Absent"
  defp position_label(_), do: nil

  defp vote_kind_label(nil), do: nil

  defp vote_kind_label(vote) do
    house = %{"H" => "House", "S" => "Senate"}[vote.house]
    kind = %{floor: "floor", committee: "committee"}[vote.kind]

    case {house, kind} do
      {nil, nil} -> nil
      {nil, kind} -> String.capitalize(kind)
      {house, nil} -> house
      {house, kind} -> "#{house} #{kind}"
    end
  end

  defp tally_label(receipt, vote) do
    case vote && vote.tally do
      %{"yea" => y, "nay" => n, "absent" => a} -> "#{y}-#{n}-#{a}"
      _ -> receipt.tally
    end
  end

  defp citation_links(citations) do
    (citations || [])
    |> Enum.map(fn c ->
      url = safe_url(c["url"] || c[:url])
      title = c["title"] || c[:title] || c["document_title"] || c[:document_title] || host(url)
      {title, url}
    end)
    |> Enum.reject(fn {title, _url} -> is_nil(title) end)
    |> Enum.uniq()
    |> Enum.take(5)
  end

  # Only http(s) links are rendered; anything else (javascript:, data:) is dropped.
  defp safe_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) -> url
      _ -> nil
    end
  end

  defp safe_url(_), do: nil

  defp host(nil), do: nil
  defp host(url), do: url |> URI.parse() |> Map.get(:host) |> String.replace_prefix("www.", "")

  defp format_date(nil), do: nil
  defp format_date(%DateTime{} = dt), do: dt |> DateTime.to_date() |> format_date()
  defp format_date(%NaiveDateTime{} = dt), do: dt |> NaiveDateTime.to_date() |> format_date()
  defp format_date(%Date{} = d), do: Calendar.strftime(d, "%b %-d, %Y")

  defp parse_int(n) when is_integer(n), do: n

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_int(_), do: nil

  defp ordinal(1), do: "1st"
  defp ordinal(2), do: "2nd"
  defp ordinal(3), do: "3rd"
  defp ordinal(n), do: "#{n}th"
end

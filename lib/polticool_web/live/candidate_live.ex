defmodule PolticoolWeb.CandidateLive do
  @moduledoc """
  A candidate's scorecard (UI Views page 4): grade, the three bars, stats,
  receipts grouped by issue, vague promises (collapsed) and track record.

  Every graded receipt is listed under its issue, including receipts on
  vague pledges, since they still count on the Voted bar. Pledges that are
  specific but have no receipt yet show as Untested. Track-record receipts
  (votes before the pledge) are context only and listed separately.

  Tapping a receipt opens it in the receipt card below (`?receipt=`), the
  same way as on the compare page.
  """
  use PolticoolWeb, :live_view

  alias Polticool.Ballot
  alias Polticool.Ballot.Receipt
  alias PolticoolWeb.IssueCategories

  import PolticoolWeb.ScoreComponents

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(%{"id" => id} = params, _uri, socket) do
    case load(id) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "We couldn't find that candidate.")
         |> push_navigate(to: ~p"/ballot")}

      candidate ->
        receipts = for p <- candidate.pledges, r <- p.receipts, do: {p, r}
        {graded, track_record} = Enum.split_with(receipts, fn {_p, r} -> !r.track_record end)
        groups = groups(candidate, graded)

        {:noreply,
         assign(socket,
           page_title: candidate.name,
           candidate: candidate,
           scorecard: Ballot.scorecard(candidate),
           stats: stats(receipts),
           groups: groups,
           vague: Enum.reject(candidate.pledges, & &1.specific),
           track_record: Enum.map(track_record, &item/1),
           current: pick(groups, track_record, params["receipt"])
         )}
    end
  end

  defp load(id) do
    with {int, ""} <- Integer.parse(to_string(id)) do
      try do
        Ballot.get_candidate!(int)
      rescue
        Ecto.NoResultsError -> nil
      end
    else
      _ -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex items-center gap-3.5">
        <.grade_tile grade={@scorecard.grade} size={:lg} />
        <div class="min-w-0">
          <h1 class="font-serif text-[24px] leading-[1.1]">
            {@candidate.name}
            <.party_label :if={@candidate.party} party={@candidate.party} class="align-[3px]" />
          </h1>
          <p class="mt-1 text-[12.5px] text-muted">{meta(@candidate)}</p>
        </div>
      </div>
      <.unofficial_badge :if={unofficial?(@candidate)} class="mt-2.5" />

      <div id="scorecard-bars" class="mt-4 rounded-[12px] border border-rule bg-surface p-3.5">
        <.score_bars scorecard={@scorecard} labels={:long} />
        <p :if={@scorecard.grade && @scorecard.bars_used < 3} class="mt-2.5 text-[11px] text-faint">
          Graded on {@scorecard.bars_used} of 3 bars
        </p>
        <p :if={!@scorecard.grade} class="mt-2.5 text-[11px] text-faint">
          Not graded yet: no bar has a record.
        </p>
      </div>

      <dl id="scorecard-stats" class="mt-2.5 grid grid-cols-3 gap-2 text-center">
        <div id="stat-receipts" class="flex flex-col rounded-[10px] border border-rule bg-surface p-2">
          <dt class="text-[11px] text-muted">receipts</dt>
          <dd class="order-first font-serif text-[18px]">{@stats.receipts}</dd>
        </div>
        <div id="stat-untested" class="flex flex-col rounded-[10px] border border-rule bg-surface p-2">
          <dt class="text-[11px] text-muted">untested</dt>
          <dd class="order-first font-serif text-[18px]">{@stats.untested}</dd>
        </div>
        <div id="stat-absence" class="flex flex-col rounded-[10px] border border-rule bg-surface p-2">
          <dt class="text-[11px] text-muted">absent rate</dt>
          <dd class="order-first font-serif text-[18px]">{@stats.absence}</dd>
        </div>
      </dl>

      <section
        :for={group <- @groups}
        id={"issue-group-#{group.id}"}
        aria-labelledby={"issue-group-#{group.id}-title"}
      >
        <h2
          id={"issue-group-#{group.id}-title"}
          class="mb-2 mt-5 text-[11px] font-semibold uppercase tracking-[0.12em] text-faint"
        >
          {group.title}
        </h2>
        <ul class="space-y-2">
          <li :for={item <- group.items}>
            <.receipt_row item={item} current={@current} candidate={@candidate} />
          </li>
        </ul>
      </section>

      <p :if={@groups == []} id="scorecard-empty" class="mt-5 text-[13.5px] text-muted">
        No pledges on record yet.
      </p>

      <details
        :if={@vague != []}
        id="vague-promises"
        class="group mt-3 rounded-[10px] border border-dashed border-rule-strong p-2.5 text-[12.5px] text-muted"
      >
        <summary class="cursor-pointer list-none select-none transition-colors hover:text-ink [&::-webkit-details-marker]:hidden">
          <span aria-hidden="true" class="inline-block transition-transform group-open:rotate-90">▸</span>
          Vague promises ({length(@vague)}): lowers the Promised bar only
        </summary>
        <ul class="mt-2 space-y-1.5 pl-4">
          <li :for={p <- @vague} class="text-ink-soft">“{p.text}”</li>
        </ul>
      </details>

      <section :if={@track_record != []} id="track-record" aria-labelledby="track-record-title">
        <h2
          id="track-record-title"
          class="mb-1 mt-5 text-[11px] font-semibold uppercase tracking-[0.12em] text-faint"
        >
          Track record
        </h2>
        <p class="mb-2 text-[12px] text-muted">
          Votes cast before the pledge: context only, not graded.
        </p>
        <ul class="space-y-2">
          <li :for={item <- @track_record}>
            <.receipt_row item={item} current={@current} candidate={@candidate} />
          </li>
        </ul>
      </section>

      <section
        :if={@current}
        id="receipt-panel"
        tabindex="-1"
        class="-mx-[18px] mt-6 scroll-mt-16 bg-ink px-[18px] py-6 focus:outline-none sm:mx-0 sm:rounded-2xl sm:px-6"
      >
        <h2 class="sr-only">Receipt</h2>
        <.receipt_card
          id={"receipt-#{@current.id}"}
          receipt={@current.receipt}
          pledge={@current.pledge}
          candidate={@candidate}
          label={@current.label}
        />
      </section>
    </Layouts.app>
    """
  end

  attr :item, :map, required: true
  attr :current, :map, default: nil
  attr :candidate, :map, required: true

  defp receipt_row(assigns) do
    assigns =
      assign(assigns, :selected?, assigns.current && assigns.current.id == assigns.item.id)

    ~H"""
    <button
      id={"item-#{@item.id}"}
      type="button"
      phx-click={
        JS.patch(~p"/candidates/#{@candidate.id}?#{%{receipt: @item.id}}")
        |> JS.focus(to: "#receipt-panel")
      }
      aria-controls="receipt-panel"
      aria-current={@selected? && "true"}
      class={[
        "flex w-full gap-2.5 rounded-[10px] border bg-surface p-2.5 text-left transition duration-150 hover:-translate-y-px hover:shadow-[0_6px_16px_-10px_rgba(28,27,25,0.4)]",
        if(@selected?, do: "border-accent ring-1 ring-accent", else: "border-rule hover:border-muted")
      ]}
    >
      <span class="sr-only">Open receipt:</span>
      <.outcome_badge outcome={@item.receipt.outcome} class="h-fit" />
      <span class="min-w-0 text-[13px]">
        {@item.title}
        <small :if={@item.meta} class="block text-[11px] text-faint">{@item.meta}</small>
        <.verified_badge :if={@item.receipt.verified} class="text-[10.5px]" />
      </span>
    </button>
    """
  end

  # Issue groups in display order, then "Other issues".
  defp groups(candidate, graded) do
    graded_items = Enum.map(graded, &item/1)

    untested =
      for p <- candidate.pledges,
          p.specific,
          p.receipts == [],
          do: item({p, %Receipt{outcome: :untested}}, "p#{p.id}")

    items = graded_items ++ untested

    for c <- IssueCategories.all() ++ [%{id: "other", title: "Other issues"}],
        group_items <- [Enum.filter(items, &(&1.category == c.id))],
        group_items != [] do
      %{id: c.id, title: c.title, items: group_items}
    end
  end

  defp item({pledge, receipt}, id \\ nil) do
    category = IssueCategories.for_issue(pledge.issue)
    group_id = if category, do: category.id, else: "other"
    group_title = if category, do: category.title, else: "Other issues"

    %{
      id: id || "r#{receipt.id}",
      pledge: pledge,
      receipt: receipt,
      category: group_id,
      label: group_title,
      title: item_title(pledge, receipt),
      meta: item_meta(receipt)
    }
  end

  defp item_title(pledge, receipt) do
    bill_title =
      case receipt.bill do
        %{title: title} when is_binary(title) -> title
        _ -> nil
      end

    receipt.bill_title || bill_title || "“#{receipt.quote || pledge.text}”"
  end

  defp item_meta(%Receipt{} = r) do
    [
      r.vote_position && "voted #{r.vote_position}",
      r.trap && "trap vote flagged",
      r.outcome == :absent && "shown, not graded",
      r.confidence && r.confidence != :high && "possibly related"
    ]
    |> Enum.filter(&is_binary/1)
    |> case do
      [] -> nil
      parts -> Enum.join(parts, " · ")
    end
  end

  defp pick(groups, track_record, requested) do
    items = Enum.flat_map(groups, & &1.items) ++ Enum.map(track_record, &item/1)

    Enum.find(items, &(&1.id == requested)) ||
      Enum.find(items, &String.starts_with?(&1.id, "r")) ||
      List.first(items)
  end

  defp stats(receipts) do
    votes = for {_p, r} <- receipts, r.vote_position != nil, do: r

    %{
      receipts: length(receipts),
      untested: Enum.count(receipts, fn {_p, r} -> r.outcome == :untested end),
      absence:
        case votes do
          [] ->
            "—"

          _ ->
            "#{round(Enum.count(votes, &(&1.vote_position == :absent)) / length(votes) * 100)}%"
        end
    }
  end

  defp meta(c) do
    place =
      cond do
        is_nil(c.district) -> c.office
        (c.office || "") =~ "House" -> "Utah House · District #{c.district}"
        (c.office || "") =~ "Senate" -> "Utah Senate · District #{c.district}"
        true -> "#{c.office} · #{c.district}"
      end

    [place, if(c.incumbent, do: "Incumbent", else: "Challenger")]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp unofficial?(c), do: (c.result_status || "") =~ "unofficial"
end

defmodule PolticoolWeb.CompareLive do
  @moduledoc """
  Step 3 of the flow: a race side by side, by issue (UI Views page 3).

  `#compare-grid` (a demo DOM hook) holds one column per candidate (grade,
  the three bars, "No record" states) and one row per issue with that
  candidate's receipts. Tapping a receipt patches `?receipt=` and opens it in
  the receipt card below the grid. One receipt is always open, so the demo
  can click "See the bill" straight away, and only one card is ever on the
  page, so that button text stays unambiguous.

  The grid is a single, bounded race, so it uses plain assigns: every tap
  re-renders the selection highlight across the whole grid anyway.
  """
  use PolticoolWeb, :live_view

  alias Polticool.Ballot
  alias Polticool.Ballot.Receipt
  alias PolticoolWeb.{IssueCategories, Races}

  import PolticoolWeb.ScoreComponents

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(%{"key" => key} = params, _uri, socket) do
    case Enum.find(Ballot.list_races(), &(&1.key == key)) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "We couldn't find that race.")
         |> push_navigate(to: ~p"/ballot")}

      race ->
        issues = IssueCategories.parse(params["issues"])
        columns = Enum.map(race.candidates, &column/1)
        rows = rows(columns, issues)

        {:noreply,
         assign(socket,
           page_title: "Compare · #{Races.title(race)}",
           race: race,
           issues: issues,
           columns: columns,
           rows: rows,
           current: pick(rows, params["receipt"])
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.link
        id="back-to-ballot"
        navigate={~p"/ballot?#{IssueCategories.to_params(@issues)}"}
        class="group -my-1.5 py-1.5 inline-flex items-center gap-1 text-[12.5px] text-muted transition-colors hover:text-accent"
      >
        <span aria-hidden="true" class="transition-transform group-hover:-translate-x-0.5">←</span>
        Your ballot
      </.link>
      <h1 class="mb-3 mt-1 font-serif text-[24px] leading-tight tracking-[-0.01em]">
        {Races.title(@race)}
      </h1>

      <div id="compare-grid">
        <div class="grid gap-2" style={cols(@columns)}>
          <div
            :for={col <- @columns}
            id={"candidate-#{col.candidate.id}"}
            class="rounded-[12px] border border-rule bg-surface p-3 text-center"
          >
            <.grade_tile grade={col.scorecard.grade} size={:md} class="mx-auto" />
            <p class="mt-1.5 text-[13.5px] font-semibold leading-tight">
              <.link
                id={"scorecard-link-#{col.candidate.id}"}
                navigate={~p"/candidates/#{col.candidate.id}"}
                class="-my-1.5 py-1.5 underline decoration-rule-strong underline-offset-2 transition-colors hover:text-accent hover:decoration-accent"
              >
                {col.candidate.name}
              </.link>
              <.party_label :if={col.candidate.party} party={col.candidate.party} />
            </p>
            <p class="text-[11px] text-muted">
              {if col.candidate.incumbent, do: "Incumbent", else: "Challenger"}
            </p>
            <.score_bars scorecard={col.scorecard} class="mt-2.5" />
            <p
              :if={col.scorecard.grade && col.scorecard.bars_used < 3}
              class="mt-2 text-[10.5px] text-faint"
            >
              Graded on {col.scorecard.bars_used} of 3 bars
            </p>
          </div>
        </div>

        <section
          :for={row <- @rows}
          id={"issue-row-#{row.id}"}
          aria-labelledby={"issue-row-#{row.id}-title"}
          class="mt-4"
        >
          <h2
            id={"issue-row-#{row.id}-title"}
            class="mb-1.5 flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-[0.12em] text-accent"
          >
            {row.title}
            <span
              :if={row.chosen?}
              class="rounded-full bg-accent-tint px-1.5 py-px text-[10px] font-semibold normal-case tracking-normal"
            >
              your issue
            </span>
          </h2>
          <div class="grid gap-2" style={cols(@columns)}>
            <div :for={{cell, col} <- Enum.zip(row.cells, @columns)} class="space-y-2">
              <h3 class="sr-only">{col.candidate.name}</h3>
              <p
                :if={cell == []}
                class="rounded-[10px] border border-dashed border-rule-strong p-2.5 text-[11.5px] text-muted"
              >
                No pledge on this issue
              </p>
              <button
                :for={item <- cell}
                id={"item-#{item.id}"}
                type="button"
                phx-click={select(@race, @issues, item)}
                aria-controls="receipt-panel"
                aria-current={@current && @current.id == item.id && "true"}
                class={[
                  "block w-full rounded-[10px] border bg-surface p-2.5 text-left text-[12px] transition duration-150 hover:-translate-y-px hover:shadow-[0_6px_16px_-10px_rgba(28,27,25,0.4)] active:translate-y-0",
                  if(@current && @current.id == item.id,
                    do: "border-accent ring-1 ring-accent",
                    else: "border-rule hover:border-muted"
                  )
                ]}
              >
                <span class="sr-only">Open receipt:</span>
                <.outcome_badge outcome={item.receipt.outcome} />
                <span class="mt-1 line-clamp-3 block text-ink-soft">{item_text(item)}</span>
                <span
                  :if={item.receipt.outcome == :absent}
                  class="mt-0.5 block text-[11px] text-muted"
                >
                  Shown, not graded
                </span>
              </button>
            </div>
          </div>
        </section>

        <p :if={@rows == []} id="compare-empty" class="mt-4 text-[13.5px] text-muted">
          No pledges on record for this race yet.
        </p>
      </div>

      <p :if={@rows != []} class="mt-3.5 text-center text-[11px] text-faint">
        Tap any receipt to see the quote → bill → vote
      </p>

      <section
        :if={@current}
        id="receipt-panel"
        tabindex="-1"
        class="-mx-[18px] mt-5 scroll-mt-16 bg-ink px-[18px] py-6 focus:outline-none sm:mx-0 sm:rounded-2xl sm:px-6"
      >
        <h2 class="sr-only">Receipt</h2>
        <.receipt_card
          id={"receipt-#{@current.id}"}
          receipt={@current.receipt}
          pledge={@current.pledge}
          candidate={@current.candidate}
          label={"#{Races.short(@race)} · #{row_title(@current.category)}"}
        />
      </section>
    </Layouts.app>
    """
  end

  # Patch to the receipt and move focus to the panel (scrolling it into view).
  defp select(race, issues, item) do
    params = Map.put(IssueCategories.to_params(issues), :receipt, item.id)

    JS.patch(~p"/races/#{race.key}/compare?#{params}")
    |> JS.focus(to: "#receipt-panel")
  end

  defp cols(columns),
    do: "grid-template-columns: repeat(#{max(length(columns), 1)}, minmax(0, 1fr))"

  defp column(candidate) do
    full = Ballot.get_candidate!(candidate.id)

    %{
      candidate: full,
      scorecard: Ballot.scorecard(full),
      items: Enum.flat_map(full.pledges, &items(&1, full))
    }
  end

  # A pledge with no receipt yet still shows, as an Untested receipt.
  defp items(%{receipts: []} = pledge, candidate),
    do: [item("p#{pledge.id}", pledge, %Receipt{outcome: :untested}, candidate)]

  defp items(pledge, candidate),
    do: for(r <- pledge.receipts, do: item("r#{r.id}", pledge, r, candidate))

  defp item(id, pledge, receipt, candidate) do
    category = IssueCategories.for_issue(pledge.issue)

    %{
      id: id,
      pledge: pledge,
      receipt: receipt,
      candidate: candidate,
      category: if(category, do: category.id, else: "other")
    }
  end

  # Chosen issues first (display order), then the other groups, then "other".
  defp rows(columns, issues) do
    all_ids = Enum.map(IssueCategories.all(), & &1.id) ++ ["other"]

    for id <- issues ++ (all_ids -- issues),
        cells <- [Enum.map(columns, fn col -> Enum.filter(col.items, &(&1.category == id)) end)],
        Enum.any?(cells, &(&1 != [])) do
      %{id: id, title: row_title(id), cells: cells, chosen?: id in issues}
    end
  end

  defp row_title("other"), do: "Other issues"
  defp row_title(id), do: IssueCategories.get(id).title

  # The requested receipt, else the first real receipt, else the first item.
  defp pick(rows, requested) do
    items = for row <- rows, cell <- row.cells, item <- cell, do: item

    Enum.find(items, &(&1.id == requested)) ||
      Enum.find(items, &String.starts_with?(&1.id, "r")) ||
      List.first(items)
  end

  defp item_text(%{receipt: receipt, pledge: pledge}) do
    bill_title =
      case receipt.bill do
        %{title: title} when is_binary(title) -> title
        _ -> nil
      end

    receipt.bill_title || bill_title || "“#{receipt.quote || pledge.text}”"
  end
end

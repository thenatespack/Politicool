defmodule PolticoolWeb.BallotLive do
  @moduledoc """
  Step 2 of the flow: the voter's whole ballot, with races that have
  receipts on the chosen issues first (UI Views page 2).

  DOM hooks for the demo test: `#race-<key>` race cards (e.g. `#race-hd62`)
  and their `#compare-<key>` links named "Compare".
  """
  use PolticoolWeb, :live_view

  alias Polticool.{Ballot, Legislature}
  alias PolticoolWeb.{IssueCategories, Races}

  # Ballot measures shown in the Amendments section, read from their bills.
  @amendments [%{key: "amendment-a", name: "Amendment A", session: "2025GS", number: "HJR010"}]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Your ballot", categories: IssueCategories.all())
     |> stream_configure(:house, dom_id: &"race-#{&1.key}")
     |> stream_configure(:judicial, dom_id: &"race-#{&1.key}")
     |> stream_configure(:amendments, dom_id: & &1.key)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    selected = IssueCategories.parse(params["issues"])
    slugs = IssueCategories.slugs_for(selected)
    {judicial, house} = Enum.split_with(Ballot.list_races(slugs), &judicial?/1)

    {:noreply,
     socket
     |> assign(selected: selected)
     |> stream(:house, Enum.map(house, &race_card(&1, slugs, selected)), reset: true)
     |> stream(:judicial, Enum.map(judicial, &judicial_card/1), reset: true)
     |> stream(:amendments, amendment_cards(), reset: true)}
  end

  @impl true
  def handle_event("toggle", %{"issue" => id}, socket) do
    selected = IssueCategories.toggle(socket.assigns.selected, id)
    {:noreply, push_patch(socket, to: ~p"/ballot?#{IssueCategories.to_params(selected)}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex items-baseline justify-between gap-3">
        <h1 class="font-serif text-[26px] tracking-[-0.01em]">Your ballot</h1>
        <.link
          id="change-issues"
          navigate={~p"/?#{IssueCategories.to_params(@selected)}"}
          class="text-[12.5px] text-muted underline decoration-rule-strong underline-offset-2 transition-colors hover:text-accent hover:decoration-accent"
        >
          Change issues
        </.link>
      </div>

      <div
        id="ballot-filters"
        role="group"
        aria-label="Put these issues first"
        class="mb-2 mt-2.5 flex flex-wrap gap-1.5"
      >
        <button
          :for={c <- @categories}
          id={"filter-#{c.id}"}
          type="button"
          phx-click="toggle"
          phx-value-issue={c.id}
          aria-pressed={to_string(c.id in @selected)}
          class={[
            "rounded-full border px-2.5 py-1 text-[12px] transition duration-150 active:scale-95",
            if(c.id in @selected,
              do: "border-accent bg-accent text-white hover:bg-grade-b",
              else: "border-rule text-muted hover:border-muted hover:text-ink"
            )
          ]}
        >
          {c.short}
        </button>
      </div>

      <.ballot_section id="house" title="Utah House">
        <div id="house-races" phx-update="stream" class="space-y-2.5">
          <p id="house-empty" class="hidden text-[13.5px] text-muted only:block">
            No House races loaded yet.
          </p>
          <article
            :for={{dom_id, race} <- @streams.house}
            id={dom_id}
            class="rounded-[12px] border border-rule bg-surface p-3.5 transition-shadow duration-200 hover:shadow-[0_6px_20px_-12px_rgba(28,27,25,0.35)]"
          >
            <header class="flex items-baseline justify-between gap-3">
              <h3 id={"#{dom_id}-title"} class="font-serif text-[17px] leading-tight">
                {race.title}
              </h3>
              <.link
                id={"compare-#{race.key}"}
                navigate={race.compare_path}
                aria-describedby={"#{dom_id}-title"}
                class="group shrink-0 text-[12.5px] font-semibold text-accent"
              >
                Compare
                <span
                  aria-hidden="true"
                  class="inline-block transition-transform group-hover:translate-x-0.5"
                >
                  →
                </span>
              </.link>
            </header>
            <ul class="mt-1">
              <li :for={c <- race.candidates} class="mt-2.5 flex items-center gap-2.5">
                <.grade_tile grade={c.grade} />
                <div class="min-w-0">
                  <p class="text-[15px] leading-snug">
                    {c.name} <.party_label :if={c.party} party={c.party} />
                  </p>
                  <p class="text-[12px] text-muted">{c.meta}</p>
                </div>
              </li>
            </ul>
            <.unofficial_badge :if={race.unofficial?} class="mt-2.5" />
          </article>
        </div>
      </.ballot_section>

      <.ballot_section id="judicial" title="Judicial retention">
        <div id="judicial-races" phx-update="stream" class="space-y-2.5">
          <p id="judicial-empty" class="hidden text-[13.5px] text-muted only:block">
            No judges on this ballot.
          </p>
          <article
            :for={{dom_id, judge} <- @streams.judicial}
            id={dom_id}
            class="rounded-[12px] border border-rule bg-surface p-3.5"
          >
            <header class="flex items-baseline justify-between gap-3">
              <h3 id={"#{dom_id}-title"} class="font-serif text-[17px] leading-tight">
                {judge.name}
              </h3>
              <.link
                id={"brief-#{judge.slug}"}
                href={judge.brief_path}
                aria-describedby={"#{dom_id}-title"}
                class="shrink-0 text-[12.5px] font-semibold text-accent"
              >
                Brief <span aria-hidden="true">→</span>
              </.link>
            </header>
            <p class="mt-1.5 text-[13px] text-ink-soft">
              {judge.office} · no grade: see the independent JPEC evaluation
            </p>
          </article>
        </div>
      </.ballot_section>

      <.ballot_section id="amendments" title="Constitutional amendments">
        <div id="amendment-list" phx-update="stream" class="space-y-2.5">
          <p id="amendments-empty" class="hidden text-[13.5px] text-muted only:block">
            No amendments loaded yet.
          </p>
          <article
            :for={{dom_id, amendment} <- @streams.amendments}
            id={dom_id}
            class="rounded-[12px] border border-rule bg-surface p-3.5"
          >
            <h3 class="font-serif text-[17px] leading-tight">{amendment.name}</h3>
            <p :if={amendment.summary} class="mt-1.5 text-[13px] text-ink-soft">
              {amendment.summary}
            </p>
          </article>
        </div>
      </.ballot_section>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true

  defp ballot_section(assigns) do
    ~H"""
    <section id={"section-#{@id}"} aria-labelledby={"section-#{@id}-title"} class="mt-5">
      <h2
        id={"section-#{@id}-title"}
        class="mb-2 border-t border-rule pt-3 text-[11px] font-semibold uppercase tracking-[0.12em] text-faint"
      >
        {@title}
      </h2>
      {render_slot(@inner_block)}
    </section>
    """
  end

  defp judicial?(race),
    do: String.starts_with?(race.key || "", "judicial-") or (race.office || "") =~ "retention"

  defp race_card(race, slugs, selected) do
    %{
      key: race.key,
      title: Races.title(race),
      compare_path: ~p"/races/#{race.key}/compare?#{IssueCategories.to_params(selected)}",
      unofficial?: Enum.any?(race.candidates, &((&1.result_status || "") =~ "unofficial")),
      candidates: Enum.map(race.candidates, &candidate_row(&1, slugs, selected))
    }
  end

  defp candidate_row(candidate, slugs, selected) do
    full = Ballot.get_candidate!(candidate.id)
    scorecard = Ballot.scorecard(full)
    receipts = for p <- full.pledges, r <- p.receipts, do: {p.issue, r}
    on_issues = Enum.count(receipts, fn {issue, _r} -> issue in slugs end)

    record =
      cond do
        selected != [] and on_issues > 0 ->
          "#{on_issues} #{plural(on_issues, "receipt")} on your issues"

        selected != [] and receipts != [] ->
          "no receipts on your issues yet"

        receipts != [] ->
          "#{length(receipts)} #{plural(length(receipts), "receipt")}"

        full.pledges != [] ->
          "promises only"

        true ->
          "no record yet"
      end

    graded =
      if scorecard.grade && scorecard.bars_used < 3,
        do: "graded on #{scorecard.bars_used} of 3 bars"

    %{
      name: candidate.name,
      party: candidate.party,
      grade: scorecard.grade,
      meta:
        [if(candidate.incumbent, do: "Incumbent", else: "Challenger"), record, graded]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" · ")
    }
  end

  defp judicial_card(race) do
    judge = List.first(race.candidates)
    slug = String.replace_prefix(race.key || "", "judicial-", "")

    %{
      key: race.key,
      slug: slug,
      name: if(judge, do: "Justice #{judge.name}", else: race.office),
      office: race.office,
      # TODO(919): switch to ~p once the judge briefing route exists.
      brief_path: "/races/judicial/#{slug}"
    }
  end

  defp amendment_cards do
    for a <- @amendments, bill <- [Legislature.get_bill(a.session, a.number)], bill != nil do
      %{key: a.key, name: a.name, summary: bill.provisions}
    end
  end

  defp plural(1, word), do: word
  defp plural(_, word), do: word <> "s"
end

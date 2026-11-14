defmodule PolticoolWeb.IssuesLive do
  @moduledoc """
  Step 1 of the flow: pick the issues you care about (UI Views page 1).

  DOM hooks for the demo test: issue toggle buttons named exactly by their
  titles ("Housing & cost of living", …) and the "See my ballot" button.
  """
  use PolticoolWeb, :live_view

  alias PolticoolWeb.IssueCategories

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Know your whole ballot",
       categories: IssueCategories.all(),
       selected: IssueCategories.parse(params["issues"])
     )}
  end

  @impl true
  def handle_event("toggle", %{"issue" => id}, socket) do
    {:noreply, update(socket, :selected, &IssueCategories.toggle(&1, id))}
  end

  def handle_event("see_ballot", _params, socket) do
    params = IssueCategories.to_params(socket.assigns.selected)
    {:noreply, push_navigate(socket, to: ~p"/ballot?#{params}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <p class="text-[11px] font-semibold uppercase tracking-[0.12em] text-accent">
        Utah · 2026 ballot
      </p>
      <h1 class="mt-2 font-serif text-[30px] leading-[1.1] tracking-[-0.02em] sm:text-[38px]">
        Know your whole ballot.
      </h1>
      <p class="mb-6 mt-2.5 text-[15px] text-muted">
        Pick what matters to you. We'll put those receipts first.
      </p>

      <div id="issue-picker" role="group" aria-label="Issues" class="space-y-2.5">
        <div
          :for={c <- @categories}
          class={[
            "relative flex items-center gap-3 rounded-[12px] border-[1.5px] px-4 py-3.5 transition duration-150",
            "has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-offset-2 has-[:focus-visible]:outline-accent",
            if(c.id in @selected,
              do: "border-accent bg-accent-tint",
              else: "border-rule bg-surface hover:border-muted"
            )
          ]}
        >
          <span
            aria-hidden="true"
            class={[
              "grid size-[22px] shrink-0 place-items-center rounded-[6px] border-[1.5px] text-[13px] text-white transition",
              if(c.id in @selected, do: "border-accent bg-accent", else: "border-muted bg-surface")
            ]}
          >
            <.icon :if={c.id in @selected} name="hero-check-micro" class="size-4" />
          </span>
          <span class="min-w-0">
            <button
              id={"issue-#{c.id}"}
              type="button"
              phx-click="toggle"
              phx-value-issue={c.id}
              aria-pressed={to_string(c.id in @selected)}
              aria-describedby={"issue-#{c.id}-blurb"}
              class="block text-left text-[15px] font-semibold text-ink after:absolute after:inset-0 after:rounded-[12px] after:content-[''] focus:outline-none"
            >
              {c.title}
            </button>
            <span id={"issue-#{c.id}-blurb"} class="block text-[12.5px] text-muted">
              {c.blurb}
            </span>
          </span>
        </div>
      </div>

      <button
        id="see-ballot"
        type="button"
        phx-click="see_ballot"
        class="group mt-6 flex w-full items-center justify-center gap-1.5 rounded-[12px] bg-ink px-4 py-[15px] text-[15px] font-semibold text-paper transition hover:bg-ink-soft active:scale-[0.99] phx-click-loading:opacity-80"
      >
        See my ballot
        <span aria-hidden="true" class="transition-transform group-hover:translate-x-0.5">→</span>
      </button>

      <p class="mt-3.5 text-center text-[11.5px] text-faint">
        Nonpartisan · every claim cites a public record · no vote recommendations
      </p>
    </Layouts.app>
    """
  end
end

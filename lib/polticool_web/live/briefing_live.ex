defmodule PolticoolWeb.BriefingLive do
  @moduledoc """
  Down-ballot briefings (UI Views page 7): judicial retention and the
  30-second amendment decoder, on one page.

  `/races/judicial/:slug` (a demo route) puts that judge first;
  `/amendments/:slug` puts that amendment first. The rest of the down-ballot
  items follow, so both are visible in the demo's "Down-ballot" scene.
  Facts and sources come from `PolticoolWeb.Briefings`.
  """
  use PolticoolWeb, :live_view

  alias PolticoolWeb.Briefings

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(%{"slug" => slug}, _uri, socket) do
    case focus(socket.assigns.live_action, slug) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "We couldn't find that briefing.")
         |> push_navigate(to: ~p"/ballot")}

      {kind, item} ->
        {judges, amendments} = order(kind, item)

        {:noreply,
         assign(socket,
           page_title: title(kind, item),
           kind: kind,
           judges: judges,
           amendments: amendments
         )}
    end
  end

  defp focus(:judge, slug), do: (j = Briefings.judge(slug)) && {:judge, j}
  defp focus(:amendment, slug), do: (a = Briefings.amendment(slug)) && {:amendment, a}

  defp order(:judge, judge),
    do:
      {[judge | Enum.reject(Briefings.judges(), &(&1.slug == judge.slug))],
       Briefings.amendments()}

  defp order(:amendment, a),
    do: {Briefings.judges(), [a | Enum.reject(Briefings.amendments(), &(&1.slug == a.slug))]}

  defp title(:judge, j), do: "#{j.title} #{j.name}"
  defp title(:amendment, a), do: a.name

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.link
        id="back-to-ballot"
        navigate={~p"/ballot"}
        class="group -my-1.5 py-1.5 inline-flex items-center gap-1 text-[12.5px] text-muted transition-colors hover:text-accent"
      >
        <span aria-hidden="true" class="transition-transform group-hover:-translate-x-0.5">←</span>
        Your ballot
      </.link>

      <%= if @kind == :judge do %>
        <.judge :for={{j, i} <- Enum.with_index(@judges)} judge={j} lead={i == 0} />
        <.amendment :for={a <- @amendments} amendment={a} lead={false} />
      <% else %>
        <.amendment :for={{a, i} <- Enum.with_index(@amendments)} amendment={a} lead={i == 0} />
        <.judge :for={j <- @judges} judge={j} lead={false} />
      <% end %>
    </Layouts.app>
    """
  end

  attr :judge, :map, required: true
  attr :lead, :boolean, required: true

  defp judge(assigns) do
    ~H"""
    <article
      id={"judge-#{@judge.slug}"}
      aria-labelledby={"judge-#{@judge.slug}-title"}
      class={["mt-3", !@lead && "mt-6 border-t border-rule pt-5"]}
    >
      <p class="text-[11px] font-bold uppercase tracking-[0.12em] text-accent">
        Judicial retention · no grade
      </p>
      <.dynamic_tag
        tag_name={if @lead, do: "h1", else: "h2"}
        id={"judge-#{@judge.slug}-title"}
        class="mt-1 font-serif text-[22px] leading-tight"
      >
        {@judge.title} {@judge.name}
      </.dynamic_tag>
      <p class="text-[12.5px] text-muted">{@judge.court}</p>

      <div class="mt-2.5 rounded-[12px] border border-rule bg-surface p-3.5">
        <div
          id={"jpec-#{@judge.slug}"}
          class="flex items-center gap-2.5 rounded-[10px] bg-accent-tint p-2.5"
        >
          <p class="shrink-0 whitespace-nowrap font-serif text-[16px] font-bold text-accent">
            {@judge.recommendation}
          </p>
          <p class="text-[11.5px] text-ink-soft">
            JPEC vote {@judge.jpec_vote} · passed {@judge.standards} standards
          </p>
        </div>
        <dl class="mt-1 divide-y divide-rule-soft text-[12.5px]">
          <div class="flex justify-between gap-3 py-1.5">
            <dt class="text-muted">Survey: recommend retention</dt>
            <dd class="font-semibold">{@judge.survey_recommend}</dd>
          </div>
          <div class="flex justify-between gap-3 py-1.5">
            <dt class="text-muted">Evaluated by</dt>
            <dd class="text-right">JPEC (independent commission)</dd>
          </div>
        </dl>
        <p class="mt-1.5 text-[11.5px] text-muted">
          We don't grade judges; this is JPEC's own evaluation.
        </p>
        <.sources sources={@judge.sources} />
      </div>
    </article>
    """
  end

  attr :amendment, :map, required: true
  attr :lead, :boolean, required: true

  defp amendment(assigns) do
    ~H"""
    <article
      id={"amendment-#{@amendment.slug}"}
      aria-labelledby={"amendment-#{@amendment.slug}-title"}
      class={["mt-3", !@lead && "mt-6 border-t border-rule pt-5"]}
    >
      <p class="text-[11px] font-bold uppercase tracking-[0.12em] text-accent">
        Constitutional amendment · 30-second decoder
      </p>
      <.dynamic_tag
        tag_name={if @lead, do: "h1", else: "h2"}
        id={"amendment-#{@amendment.slug}-title"}
        class="mt-1 font-serif text-[22px] leading-tight"
      >
        {@amendment.name}
      </.dynamic_tag>
      <p class="text-[12.5px] text-muted">{@amendment.bill}</p>

      <div class="mt-2.5 rounded-[12px] border border-rule bg-surface p-3.5">
        <div class="grid grid-cols-1 gap-2 min-[380px]:grid-cols-2">
          <div
            id={"yes-#{@amendment.slug}"}
            class="rounded-[10px] border border-rule p-2.5 text-[12.5px]"
          >
            <p class="text-[11px] font-bold tracking-[0.1em] text-accent">YES MEANS</p>
            {@amendment.yes_means}
          </div>
          <div
            id={"no-#{@amendment.slug}"}
            class="rounded-[10px] border border-rule p-2.5 text-[12.5px]"
          >
            <p class="text-[11px] font-bold tracking-[0.1em] text-accent">NO MEANS</p>
            {@amendment.no_means}
          </div>
        </div>
        <dl class="mt-1.5 divide-y divide-rule-soft text-[12.5px]">
          <div class="flex justify-between gap-3 py-1.5">
            <dt class="text-muted">Fiscal impact</dt>
            <dd class="text-right">{@amendment.fiscal_impact}</dd>
          </div>
          <div class="flex justify-between gap-3 py-1.5">
            <dt class="text-muted">How it got here</dt>
            <dd class="text-right">{@amendment.legislature}</dd>
          </div>
          <div id={"reps-#{@amendment.slug}"} class="flex justify-between gap-3 py-1.5">
            <dt class="text-muted">Your reps' votes</dt>
            <dd class="text-right">
              <span :for={r <- @amendment.reps} class="block">
                {r.name} <.party_label party={r.party} /> {r.district}: <strong>{r.vote}</strong>
              </span>
            </dd>
          </div>
          <div class="flex items-center justify-between gap-3 py-1.5">
            <dt class="text-muted">Result</dt>
            <dd class="text-right">
              {@amendment.result} <.unofficial_badge class="ml-1" />
            </dd>
          </div>
        </dl>
        <.sources sources={@amendment.sources} />
      </div>
    </article>
    """
  end

  attr :sources, :list, required: true

  defp sources(assigns) do
    ~H"""
    <p data-role="sources" class="mt-2.5 border-t border-rule pt-2 text-[11px] text-muted">
      Sources:
      <span class="[&>span+span]:before:mx-1 [&>span+span]:before:content-['·']">
        <span :for={{label, url} <- @sources}>
          <a
            href={url}
            target="_blank"
            rel="noopener noreferrer"
            class="py-1 underline decoration-rule-strong underline-offset-2 transition-colors hover:text-accent hover:decoration-accent"
          >
            {label}<span aria-hidden="true"> ↗</span><span class="sr-only"> (opens in a new tab)</span>
          </a>
        </span>
      </span>
    </p>
    """
  end
end

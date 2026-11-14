defmodule PolticoolWeb.ResearchLive do
  @moduledoc """
  Live research (UI Views page 6): type a legislator's name, pick one if the
  name is ambiguous, then watch `Polticool.Research` stream its steps and
  receipts until the scorecard arrives.

  `Research.start/1` subscribes this process to the run's topic. Messages:
  `{:step, step}` (same `id` replaces its row), `{:receipt, receipt}`,
  then exactly one of `{:done, scorecard}` or `{:failed, %{reason: _}}`.

  DOM hooks for the demo test: the `Legislator name` label, the "Research"
  button and `#research-done`.
  """
  use PolticoolWeb, :live_view

  alias Polticool.Research

  import PolticoolWeb.{MoneyComponents, ScoreComponents}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Research any legislator")
     |> assign(form: to_form(%{"name" => ""}, as: :research))
     |> reset_run()
     |> stream_configure(:steps, dom_id: &"step-#{&1.id}")
     |> stream_configure(:receipts, dom_id: &"research-receipt-#{&1.id}")
     |> stream(:steps, [])
     |> stream(:receipts, [])}
  end

  @impl true
  def handle_event("research", %{"research" => %{"name" => name}}, socket) do
    socket = assign(socket, form: to_form(%{"name" => name}, as: :research))

    case String.trim(name) do
      "" -> {:noreply, assign(reset_run(socket), error: "Type a legislator's name to start.")}
      name -> {:noreply, start(socket, name)}
    end
  end

  def handle_event("pick", %{"id" => id}, socket) do
    {:noreply, start(socket, id)}
  end

  @impl true
  def handle_info({:step, step}, socket) do
    {:noreply,
     socket |> assign(status: status_after(socket, step)) |> stream_insert(:steps, step)}
  end

  def handle_info({:receipt, receipt}, socket) do
    {:noreply, socket |> update(:receipt_count, &(&1 + 1)) |> stream_insert(:receipts, receipt)}
  end

  def handle_info({:done, scorecard}, socket) do
    {:noreply, assign(socket, status: :done, scorecard: normalize_scorecard(scorecard))}
  end

  def handle_info({:failed, %{reason: reason}}, socket) do
    {:noreply, assign(socket, status: :failed, failure: reason)}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  # Leaves the previous run's topic first so its messages can't mix in.
  defp start(socket, input) do
    if run = socket.assigns.run_id,
      do: Phoenix.PubSub.unsubscribe(Polticool.PubSub, Research.topic(run))

    socket =
      socket
      |> reset_run()
      |> stream(:steps, [], reset: true)
      |> stream(:receipts, [], reset: true)

    case Research.start(input) do
      {:ok, run_id} ->
        assign(socket, run_id: run_id, status: :running)

      {:ambiguous, candidates} ->
        assign(socket, candidates: candidates)

      {:error, :not_found} ->
        assign(socket, error: "No legislator matches “#{input}”. Try a last name.")
    end
  end

  defp reset_run(socket) do
    assign(socket,
      run_id: nil,
      status: :idle,
      candidates: [],
      error: nil,
      failure: nil,
      scorecard: nil,
      receipt_count: 0
    )
  end

  defp status_after(%{assigns: %{status: :idle}}, _step), do: :running
  defp status_after(socket, _step), do: socket.assigns.status

  # Research scorecards nest bars under :bars and list the bars used.
  defp normalize_scorecard(card) do
    bars = Map.get(card, :bars) || %{}

    used =
      case Map.get(card, :bars_used) do
        list when is_list(list) -> length(list)
        n when is_integer(n) -> n
        _ -> Enum.count(bars, fn {_k, v} -> v != nil end)
      end

    %{
      candidate: Map.get(card, :candidate) || %{},
      bars: bars,
      bars_used: used,
      grade: Map.get(card, :grade),
      receipts: Map.get(card, :receipts_count, 0),
      pledges: Map.get(card, :pledges_count, 0),
      absence_rate: Map.get(card, :absence_rate),
      industries: Map.get(card, :industries) || []
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="font-serif text-[24px] leading-tight tracking-[-0.01em]">
        Research any legislator
      </h1>
      <p class="mb-4 mt-1 text-[13px] text-muted">
        Built live from public records. Every claim cited.
      </p>

      <.form
        for={@form}
        id="research-form"
        phx-submit="research"
        class="flex items-end gap-2 [&_.fieldset]:mb-0 [&_.fieldset]:flex-1 [&_.label]:text-[12.5px] [&_.label]:font-medium [&_.label]:text-ink-soft"
      >
        <.input
          field={@form[:name]}
          label="Legislator name"
          autocomplete="off"
          placeholder="e.g. Thompson"
          class="w-full rounded-[10px] border-[1.5px] border-accent bg-surface px-3 py-2.5 text-[15px] text-ink placeholder:text-faint focus:outline-2 focus:outline-offset-2 focus:outline-accent"
        />
        <button
          id="research-submit"
          type="submit"
          class="rounded-[10px] bg-ink px-4 py-[11px] text-[15px] font-semibold text-paper transition hover:bg-ink-soft active:scale-[0.98] phx-submit-loading:opacity-80"
        >
          Research
        </button>
      </.form>

      <p :if={@error} id="research-error" role="alert" class="mt-3 text-[13px] text-ink-soft">
        {@error}
      </p>

      <div :if={@candidates != []} id="research-picker" class="mt-3">
        <p class="mb-1.5 text-[12.5px] text-muted">Which one did you mean?</p>
        <ul class="divide-y divide-rule-soft overflow-hidden rounded-[10px] border border-rule bg-surface">
          <li :for={c <- @candidates}>
            <button
              id={"pick-#{c.id}"}
              type="button"
              phx-click="pick"
              phx-value-id={c.id}
              class="w-full px-3 py-2.5 text-left text-[13.5px] transition-colors hover:bg-accent-tint focus-visible:bg-accent-tint"
            >
              <span class="font-semibold">{c.name}</span>
              <.party_label :if={c.party} party={c.party} />
              <span class="text-faint">· {candidate_place(c)}</span>
            </button>
          </li>
        </ul>
      </div>

      <section
        :if={@status == :idle && @candidates == [] && is_nil(@error)}
        id="research-how"
        aria-labelledby="research-how-title"
        class="mt-6 rounded-[12px] border border-dashed border-rule-strong p-4"
      >
        <h2
          id="research-how-title"
          class="text-[11px] font-semibold uppercase tracking-[0.12em] text-faint"
        >
          How it works
        </h2>
        <ol class="mt-2.5 space-y-2 text-[13px] text-ink-soft">
          <li :for={
            {n, text} <- [
              {1, "Finds the legislator on le.utah.gov"},
              {2, "Reads their campaign promises and sorts specific from vague"},
              {3, "Matches promises to their bills and roll-call votes, citing every match"},
              {4, "Grades Promised · Proposed · Voted"}
            ]
          }>
            <span class="flex items-start gap-2.5">
              <span
                aria-hidden="true"
                class="mt-px grid size-[18px] shrink-0 place-items-center rounded-full border border-accent text-[10px] font-bold text-accent"
              >
                {n}
              </span>
              {text}
            </span>
          </li>
        </ol>
      </section>

      <section
        :if={@status != :idle}
        id="research-run"
        aria-labelledby="research-run-title"
        class="mt-5"
      >
        <h2
          id="research-run-title"
          class="mb-2 text-[11px] font-semibold uppercase tracking-[0.12em] text-faint"
        >
          {run_title(@status)}
        </h2>
        <p role="status" class="sr-only">{status_text(@status, @scorecard)}</p>

        <ol
          id="research-steps"
          phx-update="stream"
          aria-busy={to_string(@status == :running)}
          class="space-y-0.5"
        >
          <li
            id="steps-starting"
            class="hidden items-center gap-2.5 py-1.5 text-[13px] text-muted only:flex"
          >
            <span class="size-[18px] shrink-0 rounded-full border-2 border-accent border-t-transparent motion-safe:animate-spin" />
            Starting research…
          </li>
          <li
            :for={{dom_id, step} <- @streams.steps}
            id={dom_id}
            data-status={step.status}
            class="flex items-start gap-2.5 py-1.5 text-[13px] motion-safe:animate-[fade-in_300ms_ease-out]"
          >
            <.step_icon status={step.status} />
            <div class={["min-w-0", step.status == :running && "text-ink"]}>
              {step.label}
              <small :if={step.detail} class="block text-[11.5px] text-muted">{step.detail}</small>
            </div>
          </li>
        </ol>

        <div :if={@receipt_count > 0} class="mt-3">
          <h3 class="mb-1.5 text-[11px] font-semibold uppercase tracking-[0.12em] text-faint">
            Receipts found
          </h3>
          <ul id="research-receipts" phx-update="stream" class="space-y-1.5">
            <li
              :for={{dom_id, r} <- @streams.receipts}
              id={dom_id}
              class="rounded-[10px] border border-rule bg-surface p-2.5 text-[12.5px] motion-safe:animate-[fade-in_300ms_ease-out]"
            >
              <.outcome_badge outcome={r.outcome} />
              <span class="ml-1 text-ink-soft">{receipt_text(r)}</span>
              <span :if={r[:possibly_related]} class="ml-1 text-[11px] text-muted">
                · possibly related, not graded
              </span>
            </li>
          </ul>
        </div>

        <div
          :if={@status == :failed}
          id="research-failed"
          class="mt-3 rounded-[10px] border border-dashed border-rule-strong p-3 text-[13px] text-ink-soft"
        >
          Research stopped: {@failure}. Try again, or pick another legislator.
        </div>

        <div
          :if={@status == :done && @scorecard}
          id="research-done"
          class="mt-4 rounded-[14px] border border-rule bg-surface p-4"
        >
          <div class="flex items-center gap-3.5">
            <.grade_tile grade={@scorecard.grade} size={:lg} />
            <div class="min-w-0">
              <p class="font-serif text-[20px] leading-tight">
                {@scorecard.candidate[:name] || "Scorecard"}
                <.party_label :if={@scorecard.candidate[:party]} party={@scorecard.candidate[:party]} />
              </p>
              <p :if={candidate_place(@scorecard.candidate)} class="text-[12.5px] text-muted">
                {candidate_place(@scorecard.candidate)}
              </p>
            </div>
          </div>
          <.score_bars scorecard={@scorecard.bars} class="mt-3.5" />
          <.link
            :if={@scorecard.candidate[:id]}
            id="research-scorecard-link"
            navigate={~p"/candidates/#{@scorecard.candidate[:id]}"}
            class="mt-3 inline-block text-[12.5px] font-semibold text-accent"
          >
            Open the full scorecard <span aria-hidden="true">→</span>
          </.link>
          <p :if={@scorecard.grade && @scorecard.bars_used < 3} class="mt-2 text-[11px] text-faint">
            Graded on {@scorecard.bars_used} of 3 bars
          </p>
          <dl class="mt-3 grid grid-cols-3 gap-2 text-center">
            <div class="flex flex-col rounded-[10px] border border-rule p-2">
              <dt class="text-[11px] text-muted">receipts</dt>
              <dd class="order-first font-serif text-[18px]">{@scorecard.receipts}</dd>
            </div>
            <div class="flex flex-col rounded-[10px] border border-rule p-2">
              <dt class="text-[11px] text-muted">pledges</dt>
              <dd class="order-first font-serif text-[18px]">{@scorecard.pledges}</dd>
            </div>
            <div class="flex flex-col rounded-[10px] border border-rule p-2">
              <dt class="text-[11px] text-muted">absent rate</dt>
              <dd class="order-first font-serif text-[18px]">{percent(@scorecard.absence_rate)}</dd>
            </div>
          </dl>
          <.money_bar
            :if={@scorecard.industries != []}
            id="research-money"
            industries={@scorecard.industries}
            class="mt-3"
          />
        </div>

        <p class="mt-3 text-center text-[11px] text-faint">
          AI-generated from cited public records · not human-verified yet
        </p>
      </section>
    </Layouts.app>
    """
  end

  attr :status, :atom, required: true

  defp step_icon(%{status: :ok} = assigns) do
    ~H"""
    <span class="mt-px grid size-[18px] shrink-0 place-items-center rounded-full bg-accent text-white">
      <.icon name="hero-check-micro" class="size-3.5" /><span class="sr-only">Done:</span>
    </span>
    """
  end

  defp step_icon(%{status: :error} = assigns) do
    ~H"""
    <span class="mt-px grid size-[18px] shrink-0 place-items-center rounded-full bg-ink text-paper">
      <.icon name="hero-x-mark-micro" class="size-3.5" /><span class="sr-only">Failed:</span>
    </span>
    """
  end

  defp step_icon(assigns) do
    ~H"""
    <span class="mt-px size-[18px] shrink-0 rounded-full border-2 border-accent border-t-transparent motion-safe:animate-spin">
      <span class="sr-only">In progress:</span>
    </span>
    """
  end

  defp run_title(:running), do: "Researching…"
  defp run_title(:done), do: "Research complete"
  defp run_title(:failed), do: "Research stopped"
  defp run_title(_), do: "Research"

  defp status_text(:done, %{grade: grade}) when is_binary(grade),
    do: "Research complete. Grade #{grade}."

  defp status_text(:done, _), do: "Research complete."
  defp status_text(:failed, _), do: "Research stopped."
  defp status_text(_, _), do: ""

  defp candidate_place(c) do
    [c[:office], c[:district] && "District #{c[:district]}"]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      parts -> Enum.join(parts, " · ")
    end
  end

  defp receipt_text(r),
    do: r[:bill_title] || (r[:pledge_text] && "“#{r[:pledge_text]}”") || "Receipt"

  defp percent(nil), do: "—"
  defp percent(rate) when is_number(rate), do: "#{round(rate * 100)}%"
end

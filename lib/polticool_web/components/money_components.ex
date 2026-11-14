defmodule PolticoolWeb.MoneyComponents do
  @moduledoc """
  The money trail: top donor industries as a stacked single-hue bar with a
  legend (`Polticool.Money.top_industries/2`). Disclosed facts only; the copy
  never implies that a donation caused a vote.
  """
  use Phoenix.Component

  import PolticoolWeb.CoreComponents, only: [icon: 1]

  # Darkest first, all from the accent hue (Design Tokens note).
  @shades ~w(bg-grade-a bg-grade-c bg-grade-d bg-outcome-partial bg-grade-f)

  @doc """
  Stacked bar + legend. `industries` is `[%{industry, total, share}]` with
  `total` in dollars and `share` a 0..1 fraction of all contributions; the
  rest of the bar is everyone else.

  ## Examples

      <.money_bar id="money" industries={Money.top_industries(candidate)} />
  """
  attr :id, :string, required: true
  attr :industries, :list, required: true
  attr :class, :any, default: nil

  def money_bar(assigns) do
    rows =
      assigns.industries
      |> Enum.take(length(@shades))
      |> Enum.with_index()
      |> Enum.map(fn {row, i} ->
        %{
          industry: row.industry,
          pct: percent(row.share),
          dollars: dollars(row.total),
          shade: Enum.at(@shades, i)
        }
      end)

    assigns = assign(assigns, :rows, rows)

    ~H"""
    <div
      id={@id}
      data-role="money-bar"
      class={["rounded-[10px] border border-rule bg-surface p-3", @class]}
    >
      <div aria-hidden="true" class="flex h-3 gap-px overflow-hidden rounded-full bg-track">
        <span :for={r <- @rows} class={["h-full", r.shade]} style={"width: #{r.pct}%"} />
      </div>
      <ul class="mt-2.5 space-y-1 text-[12px]">
        <li :for={r <- @rows} data-industry={r.industry} class="flex items-center gap-2">
          <span aria-hidden="true" class={["size-2.5 shrink-0 rounded-[3px]", r.shade]} />
          <span class="min-w-0 flex-1 text-ink-soft">{r.industry}</span>
          <span class="tabular-nums text-muted">{r.dollars}</span>
          <span class="w-9 text-right font-semibold tabular-nums text-ink">{r.pct}%</span>
        </li>
      </ul>
      <p class="mt-2 text-[11px] text-muted">
        Disclosed contributions · facts only, no implied cause
      </p>
    </div>
    """
  end

  @doc """
  Small tag on a receipt when an industry related to its issue is among the
  candidate's top donors. States the fact only.
  """
  attr :industries, :list, required: true, doc: "related top donor industry names"
  attr :class, :any, default: nil

  def donor_tag(assigns) do
    ~H"""
    <span
      data-role="donor-tag"
      class={["inline-flex items-center gap-1 text-[10.5px] text-muted", @class]}
    >
      <.icon name="hero-banknotes-micro" class="size-3.5 shrink-0" />
      Top donor industry: {Enum.join(@industries, ", ")}
    </span>
    """
  end

  defp percent(share) when is_number(share),
    do: share |> Kernel.*(100) |> round() |> max(0) |> min(100)

  defp percent(_), do: 0

  @doc false
  def dollars(total) when is_number(total) do
    whole = total |> round() |> Integer.to_string()

    "$" <>
      (whole |> String.reverse() |> String.replace(~r/(\d{3})(?=\d)/, "\\1,") |> String.reverse())
  end

  def dollars(_), do: "$0"
end

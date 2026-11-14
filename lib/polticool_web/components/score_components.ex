defmodule PolticoolWeb.ScoreComponents do
  @moduledoc """
  The three scorecard bars (Promised · Proposed · Voted) from
  `Polticool.Ballot.scorecard/1`. A bar with no record shows "No record"
  and an empty track instead of a zero.
  """
  use Phoenix.Component

  @bars [
    {:promised, "Promised"},
    {:proposed, "Proposed"},
    {:voted, "Voted"}
  ]

  @doc """
  ## Examples

      <.score_bars scorecard={Ballot.scorecard(candidate)} />
  """
  attr :scorecard, :map,
    required: true,
    doc: "map with :promised, :proposed, :voted (0..100 or nil)"

  attr :class, :any, default: nil
  attr :rest, :global

  def score_bars(assigns) do
    bars = for {key, label} <- @bars, do: {key, label, to_value(Map.get(assigns.scorecard, key))}
    assigns = assign(assigns, :bars, bars)

    ~H"""
    <ul data-role="score-bars" class={["space-y-1.5 text-left", @class]} {@rest}>
      <li :for={{key, label, value} <- @bars} data-bar={key} data-value={value || "none"}>
        <span class="flex justify-between gap-2 text-[10.5px] leading-tight">
          <span class="text-muted">{label}</span>
          <span :if={value} class="font-semibold tabular-nums text-ink">
            {value}<span class="sr-only"> out of 100</span>
          </span>
          <span :if={!value} class="text-muted">No record</span>
        </span>
        <span aria-hidden="true" class="mt-1 block h-[5px] overflow-hidden rounded-full bg-track">
          <span :if={value} class="block h-full rounded-full bg-accent" style={"width: #{value}%"} />
        </span>
      </li>
    </ul>
    """
  end

  defp to_value(nil), do: nil
  defp to_value(n) when is_number(n), do: n |> round() |> max(0) |> min(100)
end

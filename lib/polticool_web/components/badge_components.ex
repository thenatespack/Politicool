defmodule PolticoolWeb.BadgeComponents do
  @moduledoc """
  Small civic-editorial labels shared across pages: party labels, receipt
  outcome badges and the unofficial-result badge.

  Party colour appears only on `party_label/1` (see the Design Tokens note in
  the UI Views sketch). Everything else uses the neutrals and the single
  accent hue defined in `assets/css/app.css`.
  """
  use Phoenix.Component

  @party_names %{"R" => "Republican", "D" => "Democrat", "U" => "Unaffiliated"}

  @outcomes ~w(kept partial broken untested absent)
  @absent_aliases ~w(absent_nv absent/nv absent-nv nv not_voting)

  @doc """
  Tiny party label: R, D or U.

  Accepts a letter or a party name, as a string or atom (`"R"`, `:d`,
  `"Democratic"`). Only R and D get a tint; any other party uses the neutral
  style. Screen readers hear the full party name.

  ## Examples

      <.party_label party="R" />
      <.party_label party={@candidate.party} />
  """
  attr :party, :any, required: true, doc: "party letter or name (string or atom)"
  attr :class, :any, default: nil
  attr :rest, :global

  def party_label(assigns) do
    {letter, name} = party_info(assigns.party)
    assigns = assign(assigns, letter: letter, name: name)

    ~H"""
    <span
      data-role="party"
      data-party={@letter}
      title={@name}
      class={[
        "inline-flex items-center rounded-[3px] px-[5px] py-px align-middle text-[10px] font-bold leading-[1.4] tracking-wide",
        party_classes(@letter),
        @class
      ]}
      {@rest}
    >
      <span aria-hidden="true">{@letter}</span><span class="sr-only">{@name}</span>
    </span>
    """
  end

  defp party_info(party) when is_atom(party) and not is_nil(party),
    do: party_info(Atom.to_string(party))

  defp party_info(party) when is_binary(party) do
    case String.trim(party) do
      "" ->
        raise ArgumentError, "party_label/1 needs a party, got: #{inspect(party)}"

      trimmed ->
        letter = trimmed |> String.first() |> String.upcase()
        # A full party name is shown as given; only bare letters are expanded.
        name =
          if String.length(trimmed) > 1,
            do: trimmed,
            else: Map.get(@party_names, letter, letter)

        {letter, name}
    end
  end

  defp party_info(party),
    do: raise(ArgumentError, "party_label/1 needs a party, got: #{inspect(party)}")

  defp party_classes("R"), do: "bg-party-r-tint text-party-r"
  defp party_classes("D"), do: "bg-party-d-tint text-party-d"
  defp party_classes(_), do: "bg-party-u-tint text-party-u"

  @doc """
  Receipt outcome badge: Kept, Partial, Broken, Untested or Absent/NV.

  Renders `data-role="outcome"`, an agreed DOM hook that the demo test asserts
  on, plus `data-outcome` with the normalised outcome. Absent/NV is drawn
  dashed because it is shown but not graded.

  Unknown outcomes raise instead of falling back, so a receipt is never shown
  with the wrong verdict.

  ## Examples

      <.outcome_badge outcome={:kept} />
      <.outcome_badge outcome={@receipt.outcome} />
  """
  attr :outcome, :any,
    required: true,
    doc: "kept | partial | broken | untested | absent (atom or string)"

  attr :size, :atom, default: :sm, values: [:sm, :lg], doc: ":lg for the receipt verdict"
  attr :class, :any, default: nil
  attr :rest, :global

  def outcome_badge(assigns) do
    outcome = normalize_outcome!(assigns.outcome)
    assigns = assign(assigns, outcome: outcome, label: outcome_label(outcome))

    ~H"""
    <span
      data-role="outcome"
      data-outcome={@outcome}
      class={[
        "inline-flex items-center whitespace-nowrap border font-bold uppercase leading-[1.4] tracking-[0.04em]",
        @size == :sm && "rounded-[3px] px-1.5 py-px text-[10px]",
        @size == :lg && "rounded-[5px] px-2.5 py-1 text-[13px]",
        outcome_classes(@outcome),
        @class
      ]}
      {@rest}
    >
      {@label}
    </span>
    """
  end

  defp normalize_outcome!(outcome) when is_atom(outcome) and not is_nil(outcome),
    do: normalize_outcome!(Atom.to_string(outcome))

  defp normalize_outcome!(outcome) when is_binary(outcome) do
    key = outcome |> String.trim() |> String.downcase()

    cond do
      key in @outcomes -> key
      key in @absent_aliases -> "absent"
      true -> raise_unknown_outcome(outcome)
    end
  end

  defp normalize_outcome!(outcome), do: raise_unknown_outcome(outcome)

  defp raise_unknown_outcome(outcome) do
    raise ArgumentError,
          "unknown receipt outcome #{inspect(outcome)}; expected one of #{inspect(@outcomes)}"
  end

  defp outcome_label("kept"), do: "Kept"
  defp outcome_label("partial"), do: "Partial"
  defp outcome_label("broken"), do: "Broken"
  defp outcome_label("untested"), do: "Untested"
  defp outcome_label("absent"), do: "Absent/NV"

  defp outcome_classes("kept"), do: "border-transparent bg-outcome-kept text-white"

  defp outcome_classes("partial"),
    do: "border-transparent bg-outcome-partial text-outcome-partial-ink"

  defp outcome_classes("broken"), do: "border-transparent bg-outcome-broken text-accent"

  defp outcome_classes("untested"),
    do: "border-transparent bg-outcome-untested text-outcome-untested-ink"

  defp outcome_classes("absent"), do: "border-dashed border-rule-strong bg-surface text-muted"

  @doc """
  Amber "Unofficial result" badge for races whose results aren't canvassed yet.

  ## Examples

      <.unofficial_badge />
      <.unofficial_badge canvass={nil} />
  """
  attr :canvass, :string,
    default: "Nov 23",
    doc: "canvass date appended to the label; nil to omit it"

  attr :class, :any, default: nil
  attr :rest, :global

  def unofficial_badge(assigns) do
    ~H"""
    <span
      data-role="unofficial-result"
      class={[
        "inline-block rounded-[3px] bg-notice-tint px-[5px] py-px text-[10.5px] font-medium leading-[1.4] text-notice",
        @class
      ]}
      {@rest}
    >
      {unofficial_label(@canvass)}
    </span>
    """
  end

  defp unofficial_label(nil), do: "Unofficial result"
  defp unofficial_label(canvass), do: "Unofficial result · canvass #{canvass}"

  @doc """
  Letter-grade tile. A–C take white text and D/F take ink (white on D fails
  contrast). No grade renders a dashed neutral "—" so it never reads as a
  grade in the accent hue.

  ## Examples

      <.grade_tile grade="B" />
      <.grade_tile grade={@scorecard.grade} size={:md} />
  """
  attr :grade, :string, default: nil, doc: ~s("A", "B", "C", "D", "F" or nil)
  attr :size, :atom, default: :sm, values: [:sm, :md, :lg]
  attr :class, :any, default: nil
  attr :rest, :global

  def grade_tile(assigns) do
    ~H"""
    <span
      data-role="grade"
      data-grade={@grade || "none"}
      role="img"
      aria-label={if @grade, do: "Grade #{@grade}", else: "Not graded"}
      class={[
        "grid shrink-0 place-items-center font-serif font-bold leading-none",
        @size == :sm && "size-[34px] rounded-[8px] text-[17px]",
        @size == :md && "size-[46px] rounded-[10px] text-[24px]",
        @size == :lg && "size-16 rounded-[14px] text-[34px]",
        grade_classes(@grade),
        @class
      ]}
      {@rest}
    >
      <span aria-hidden="true">{@grade || "—"}</span>
    </span>
    """
  end

  defp grade_classes("A"), do: "bg-grade-a text-white"
  defp grade_classes("B"), do: "bg-grade-b text-white"
  defp grade_classes("C"), do: "bg-grade-c text-white"
  defp grade_classes("D"), do: "bg-grade-d text-ink"
  defp grade_classes("F"), do: "bg-grade-f text-ink"
  defp grade_classes(nil), do: "border border-dashed border-rule-strong bg-surface text-muted"

  defp grade_classes(other),
    do: raise(ArgumentError, "unknown grade #{inspect(other)}; expected A, B, C, D, F or nil")

  @doc """
  "Secondary source" badge for pledges taken from news coverage, which are
  only ever shown as verbatim quotes.
  """
  attr :class, :any, default: nil
  attr :rest, :global

  def secondary_source_badge(assigns) do
    ~H"""
    <span
      data-role="secondary-source"
      class={[
        "inline-block rounded-[3px] bg-outcome-untested px-1.5 py-px text-[10px] font-bold uppercase leading-[1.4] tracking-[0.04em] text-outcome-untested-ink",
        @class
      ]}
      {@rest}
    >
      Secondary source<span class="font-medium normal-case tracking-normal"> · verbatim quote</span>
    </span>
    """
  end

  @doc """
  "✓ Human-verified" mark for receipts a person has hand-checked.
  """
  attr :class, :any, default: nil
  attr :rest, :global

  def verified_badge(assigns) do
    ~H"""
    <span
      data-role="verified"
      class={["inline-flex items-center gap-1 text-[11.5px] font-semibold text-accent", @class]}
      {@rest}
    >
      <span aria-hidden="true">✓</span> Human-verified
    </span>
    """
  end
end

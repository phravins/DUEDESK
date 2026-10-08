defmodule DueDesk.DueItems.Recurrence do
  @moduledoc """
  How a DueItem repeats, and the next dates when it is renewed.

  The next dates count from the previous dates (not from the day it was
  renewed). Each date is shifted by the interval from the *anchor*: the
  latest cycle whose dates a person entered. Shifting from the anchor
  rather than from the previous computed date keeps month ends stable:
  31 Jan renews to 29 Feb, then 31 Mar, then 30 Apr, then 31 May.
  """

  alias DueDesk.DueItems.DueItem

  @options [
    {"Does not repeat", "none"},
    {"Every month", "monthly"},
    {"Every 3 months (quarterly)", "quarterly"},
    {"Every 6 months (half-yearly)", "half_yearly"},
    {"Every year", "annual"},
    {"Custom", "custom"}
  ]

  @unit_options [
    {"Days", "day"},
    {"Months", "month"},
    {"I'll set the next date each time", "explicit"}
  ]

  @doc "Options for the recurrence select."
  def options, do: @options

  @doc "Options for the custom recurrence unit select."
  def unit_options, do: @unit_options

  @doc "True when the item repeats."
  def recurring?(%DueItem{recurrence: recurrence}), do: recurrence not in [nil, "none"]

  @doc "Describes the recurrence, e.g. \"Every 3 months\"."
  def describe(%DueItem{recurrence: recurrence} = item) do
    describe(recurrence, item.recurrence_unit, item.recurrence_interval)
  end

  def describe(recurrence, unit, interval)
  def describe("monthly", _, _), do: "Every month"
  def describe("quarterly", _, _), do: "Every 3 months"
  def describe("half_yearly", _, _), do: "Every 6 months"
  def describe("annual", _, _), do: "Every year"
  def describe("custom", "explicit", _), do: "Next date set at each renewal"
  def describe("custom", "day", 1), do: "Every day"
  def describe("custom", "day", n) when is_integer(n), do: "Every #{n} days"
  def describe("custom", "month", 1), do: "Every month"
  def describe("custom", "month", n) when is_integer(n), do: "Every #{n} months"
  def describe(_, _, _), do: "Does not repeat"

  @doc """
  The interval between cycles: `{:month, n}`, `{:day, n}`, `:explicit`
  (the next date is entered at each renewal) or `:none`.
  """
  def interval(%DueItem{recurrence: recurrence} = item) do
    case recurrence do
      "monthly" -> {:month, 1}
      "quarterly" -> {:month, 3}
      "half_yearly" -> {:month, 6}
      "annual" -> {:month, 12}
      "custom" -> custom_interval(item.recurrence_unit, item.recurrence_interval)
      _ -> :none
    end
  end

  defp custom_interval("explicit", _), do: :explicit
  defp custom_interval("month", n) when is_integer(n) and n > 0, do: {:month, n}
  defp custom_interval("day", n) when is_integer(n) and n > 0, do: {:day, n}
  defp custom_interval(_, _), do: :none

  @doc """
  The dates of the cycle after the last of `cycles` (the item's cycles,
  in any order). Start, Due and Expiry Dates are each shifted; a missing
  date stays missing.

  Returns `{:ok, %{start_date: _, due_date: _, expiry_date: _}}`,
  `:explicit` when the next dates must be entered, or `:none` for an item
  that does not repeat.
  """
  def next_dates(%DueItem{} = item, [_ | _] = cycles) do
    case interval(item) do
      {unit, n} ->
        cycles = Enum.sort_by(cycles, & &1.sequence)
        {anchor, after_anchor} = anchor(cycles)
        steps = n * (after_anchor + 1)

        {:ok,
         %{
           start_date: shift(anchor.start_date, unit, steps),
           due_date: shift(anchor.due_date, unit, steps),
           expiry_date: shift(anchor.expiry_date, unit, steps)
         }}

      other ->
        other
    end
  end

  # The latest cycle with entered dates and how many cycles follow it.
  # Cycles before Phase 3 all count as entered, so there is always one;
  # the first cycle is the fallback.
  defp anchor(cycles) do
    reversed = Enum.reverse(cycles)

    case Enum.find_index(reversed, &(&1.dates_source != "computed")) do
      nil -> {hd(cycles), length(cycles) - 1}
      index -> {Enum.at(reversed, index), index}
    end
  end

  defp shift(nil, _unit, _n), do: nil
  defp shift(%Date{} = date, :day, n), do: Date.add(date, n)
  defp shift(%Date{} = date, :month, n), do: Date.shift(date, month: n)
end

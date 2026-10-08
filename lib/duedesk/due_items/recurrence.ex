defmodule DueDesk.DueItems.Recurrence do
  @moduledoc """
  How a DueItem repeats. Phase 2 stores and describes the setting; the
  next dates are computed at renewal (Phase 3).
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
end

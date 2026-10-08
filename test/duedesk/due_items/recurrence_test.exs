defmodule DueDesk.DueItems.RecurrenceTest do
  use ExUnit.Case, async: true

  alias DueDesk.DueItems.{Cycle, DueItem, Recurrence}

  defp item(recurrence, unit \\ nil, interval \\ nil),
    do: %DueItem{recurrence: recurrence, recurrence_unit: unit, recurrence_interval: interval}

  defp cycle(sequence, dates, source \\ "entered") do
    struct(%Cycle{sequence: sequence, dates_source: source}, dates)
  end

  defp next(item, cycles) do
    {:ok, dates} = Recurrence.next_dates(item, cycles)
    dates
  end

  # Renews `times` times from `first`, as the lifecycle does, and returns
  # each new cycle's dates.
  defp renewals(item, first, times) do
    Enum.reduce(1..times, [cycle(1, first)], fn _, cycles ->
      dates = next(item, cycles)
      cycles ++ [cycle(length(cycles) + 1, dates, "computed")]
    end)
    |> tl()
  end

  defp due_dates(cycles), do: Enum.map(cycles, & &1.due_date)

  test "each interval moves the dates on by its length" do
    first = [cycle(1, %{due_date: ~D[2027-03-15]})]

    assert next(item("monthly"), first).due_date == ~D[2027-04-15]
    assert next(item("quarterly"), first).due_date == ~D[2027-06-15]
    assert next(item("half_yearly"), first).due_date == ~D[2027-09-15]
    assert next(item("annual"), first).due_date == ~D[2028-03-15]
    assert next(item("custom", "day", 45), first).due_date == ~D[2027-04-29]
    assert next(item("custom", "month", 18), first).due_date == ~D[2028-09-15]
  end

  test "monthly from 31 Jan keeps to the month end over 13 cycles" do
    cycles = renewals(item("monthly"), %{due_date: ~D[2028-01-31]}, 13)

    assert due_dates(cycles) == [
             ~D[2028-02-29],
             ~D[2028-03-31],
             ~D[2028-04-30],
             ~D[2028-05-31],
             ~D[2028-06-30],
             ~D[2028-07-31],
             ~D[2028-08-31],
             ~D[2028-09-30],
             ~D[2028-10-31],
             ~D[2028-11-30],
             ~D[2028-12-31],
             ~D[2029-01-31],
             ~D[2029-02-28]
           ]
  end

  test "annual from 29 Feb returns to 29 Feb in the next leap year" do
    cycles = renewals(item("annual"), %{due_date: ~D[2028-02-29]}, 4)

    assert due_dates(cycles) == [~D[2029-02-28], ~D[2030-02-28], ~D[2031-02-28], ~D[2032-02-29]]
  end

  test "quarterly from 31 May and half-yearly from 31 Aug" do
    quarterly = renewals(item("quarterly"), %{due_date: ~D[2027-05-31]}, 4)

    assert due_dates(quarterly) == [
             ~D[2027-08-31],
             ~D[2027-11-30],
             ~D[2028-02-29],
             ~D[2028-05-31]
           ]

    half_yearly = renewals(item("half_yearly"), %{due_date: ~D[2027-08-31]}, 2)
    assert due_dates(half_yearly) == [~D[2028-02-29], ~D[2028-08-31]]
  end

  test "custom day and month intervals" do
    days = renewals(item("custom", "day", 45), %{due_date: ~D[2027-01-01]}, 2)
    assert due_dates(days) == [~D[2027-02-15], ~D[2027-04-01]]

    months = renewals(item("custom", "month", 18), %{due_date: ~D[2027-07-31]}, 2)
    assert due_dates(months) == [~D[2029-01-31], ~D[2030-07-31]]
  end

  test "an item with only an Expiry Date shifts the Expiry Date" do
    assert next(item("annual"), [cycle(1, %{expiry_date: ~D[2027-06-30]})]) ==
             %{start_date: nil, due_date: nil, expiry_date: ~D[2028-06-30]}
  end

  test "Start, Due and Expiry Dates each shift by the interval" do
    first = %{start_date: ~D[2027-04-01], due_date: ~D[2027-04-30], expiry_date: ~D[2027-05-15]}

    assert next(item("monthly"), [cycle(1, first)]) ==
             %{start_date: ~D[2027-05-01], due_date: ~D[2027-05-30], expiry_date: ~D[2027-06-15]}
  end

  test "dates a person entered become the new anchor" do
    cycles = [
      cycle(1, %{due_date: ~D[2028-01-31]}),
      cycle(2, %{due_date: ~D[2028-02-29]}, "computed"),
      cycle(3, %{due_date: ~D[2028-03-15]})
    ]

    assert next(item("monthly"), cycles).due_date == ~D[2028-04-15]

    # Order of the list does not matter.
    assert next(item("monthly"), Enum.reverse(cycles)).due_date == ~D[2028-04-15]
  end

  test "explicit and non-repeating items have no computed next dates" do
    first = [cycle(1, %{due_date: ~D[2027-03-15]})]

    assert Recurrence.next_dates(item("custom", "explicit"), first) == :explicit
    assert Recurrence.next_dates(item("none"), first) == :none
    refute Recurrence.recurring?(item("none"))
    assert Recurrence.recurring?(item("custom", "explicit"))
  end
end

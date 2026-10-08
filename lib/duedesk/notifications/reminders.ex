defmodule DueDesk.Notifications.Reminders do
  @moduledoc """
  Which reminders fall due, worked out from reminder rules and dates.

  A rule's reminder falls on the cycle's effective date (Due Date, else
  Expiry Date) plus its offset. After the last rule on or after the date,
  the reminder repeats weekly while the DueItem is overdue. A reminder
  after the effective date is **escalated**: it also goes to the
  Administrators and Super Admins.

  Each scan looks back `catch_up_days/0` days, so a short outage does not
  lose a reminder, but old ones are never sent in bulk. Reminders that
  fall before the cycle began are never sent: a DueItem created five days
  before its Due Date gets no "7 days before" reminder.

  Only active DueItems that are not waiting for an Administrator get
  reminders. Everything here is computed for a given `today`, so it can
  be tested with any date.
  """

  import Ecto.Query, warn: false

  alias DueDesk.Repo
  alias DueDesk.DueItems.{Cycle, DueItem, ReminderRule}
  alias DueDesk.Tenancy.CustomerAccount

  @catch_up_days 2
  @repeat_days 7

  @type occurrence :: %{
          item: DueItem.t(),
          cycle: Cycle.t(),
          rule: ReminderRule.t(),
          target_date: Date.t(),
          offset_days: integer(),
          escalated: boolean()
        }

  @doc "How many days back a scan still sends a missed reminder."
  def catch_up_days, do: @catch_up_days

  @doc "Days between repeated reminders while a DueItem is overdue."
  def repeat_days, do: @repeat_days

  @doc """
  The reminders of the account's DueItems that fall in the catch-up
  window ending `today`, with their items preloaded with active
  assignments.
  """
  @spec occurrences(CustomerAccount.t(), Date.t()) :: [occurrence()]
  def occurrences(%CustomerAccount{id: account_id, timezone: tz}, %Date{} = today) do
    first = Date.add(today, -@catch_up_days)

    account_id
    |> live_items()
    |> Enum.flat_map(fn %DueItem{current_cycle: cycle} = item ->
      started = cycle.inserted_at |> DateTime.shift_zone!(tz) |> DateTime.to_date()
      rules = Map.new(item.reminder_rules, &{&1.offset_days, &1})

      for {date, offset} <- targets(cycle, Map.keys(rules), first, today),
          not Date.before?(date, started) do
        %{
          item: item,
          cycle: cycle,
          rule: Map.fetch!(rules, offset),
          target_date: date,
          offset_days: offset,
          escalated: Date.after?(date, Cycle.effective_date(cycle))
        }
      end
    end)
  end

  defp live_items(account_id) do
    from(i in DueItem,
      join: c in assoc(i, :current_cycle),
      where:
        i.customer_account_id == ^account_id and i.status == "active" and
          is_nil(i.disposition_state) and is_nil(c.completed_at) and
          (not is_nil(c.due_date) or not is_nil(c.expiry_date)),
      preload: [
        current_cycle: c,
        reminder_rules: ^from(r in ReminderRule, where: r.active),
        active_assignments: []
      ]
    )
    |> Repo.all()
  end

  @doc """
  The next reminder of a live DueItem after `today`, as
  `{date, offset_days, repeat?}`, or nil when none is left.
  """
  @spec next(DueItem.t(), Cycle.t() | nil, [integer()], Date.t()) ::
          {Date.t(), integer(), boolean()} | nil
  def next(%DueItem{status: "active", disposition_state: nil}, %Cycle{} = cycle, offsets, today)
      when offsets != [] do
    with %Date{} = effective <- Cycle.effective_date(cycle) do
      first = Date.add(today, 1)
      # Late enough to include the last rule or, after it, one weekly repeat.
      last = Enum.max([today, Date.add(effective, Enum.max(offsets))], Date)
      last = Date.add(last, @repeat_days)

      case targets(cycle, offsets, first, last) do
        [] -> nil
        [{date, offset} | _] -> {date, offset, Date.after?(date, Date.add(effective, offset))}
      end
    end
  end

  def next(_item, _cycle, _offsets, _today), do: nil

  @doc """
  Reminder dates of `cycle` from `first` to `last` (inclusive), sorted, as
  `{date, offset_days}`. Weekly repeats carry the offset of the last rule
  they follow. A status override other than Overdue stops the reminders
  after the effective date.
  """
  @spec targets(Cycle.t(), [integer()], Date.t(), Date.t()) :: [{Date.t(), integer()}]
  def targets(%Cycle{} = cycle, offsets, %Date{} = first, %Date{} = last) do
    effective = Cycle.effective_date(cycle)

    if is_nil(effective) or offsets == [] do
      []
    else
      in_range? = &(not Date.before?(&1, first) and not Date.after?(&1, last))

      rule_dates =
        for o <- offsets, date = Date.add(effective, o), in_range?.(date), do: {date, o}

      (rule_dates ++ repeats(effective, Enum.max(offsets), first, last))
      |> Enum.reject(fn {date, _} -> paused?(cycle, effective, date) end)
      |> Enum.uniq_by(&elem(&1, 0))
      |> Enum.sort_by(&elem(&1, 0), Date)
    end
  end

  defp repeats(_effective, anchor, _first, _last) when anchor < 0, do: []

  defp repeats(effective, anchor, first, last) do
    from = Date.add(effective, anchor)
    # The first repeat on or after `first`, counting whole weeks from `from`.
    weeks = max(1, ceil_div(Date.diff(first, from), @repeat_days))

    Stream.iterate(Date.add(from, weeks * @repeat_days), &Date.add(&1, @repeat_days))
    |> Enum.take_while(&(not Date.after?(&1, last)))
    |> Enum.map(&{&1, anchor})
  end

  defp ceil_div(a, b) when a <= 0, do: div(a, b)
  defp ceil_div(a, b), do: div(a + b - 1, b)

  defp paused?(%Cycle{status_override: override}, effective, date)
       when override in ["due_soon", "up_to_date"],
       do: Date.after?(date, effective)

  defp paused?(_cycle, _effective, _date), do: false
end

defmodule DueDesk.DueItems.Status do
  @moduledoc """
  The effective status of a DueItem, computed and never stored.

  In order:

    1. archived items are `:archived`;
    2. a status override on the current cycle wins;
    3. an effective date (Due Date, else Expiry Date) before today is `:overdue`;
    4. one within the account's due-soon window is `:due_soon`;
    5. anything else is `:up_to_date`.

  `effective/4` is the Elixir rule and `sql/4` the same rule as a query
  fragment for filters, counts and ordering. A parity test keeps them
  equal. "Unassigned" is about responsibility, not status.
  """

  alias DueDesk.DueItems.{Cycle, DueItem}

  @type t :: :archived | :overdue | :due_soon | :up_to_date

  @statuses [:overdue, :due_soon, :up_to_date, :archived]

  @doc "Every status, in display order."
  def all, do: @statuses

  @doc "Parses a status name from a filter. Returns nil for anything else."
  def parse(value) when is_binary(value) do
    Enum.find(@statuses, &(Atom.to_string(&1) == value))
  end

  def parse(_), do: nil

  @doc "Human label for a status."
  def label(:overdue), do: "Overdue"
  def label(:due_soon), do: "Due Soon"
  def label(:up_to_date), do: "Up to Date"
  def label(:archived), do: "Archived"

  @doc "The effective status of `item` with its `cycle` on `today`."
  @spec effective(DueItem.t(), Cycle.t() | nil, Date.t(), non_neg_integer()) :: t()
  def effective(%DueItem{status: "archived"}, _cycle, _today, _due_soon_days), do: :archived

  def effective(_item, %Cycle{status_override: override}, _today, _days)
      when is_binary(override),
      do: parse(override)

  def effective(_item, cycle, today, due_soon_days) do
    case Cycle.effective_date(cycle) do
      nil ->
        :up_to_date

      date ->
        cond do
          Date.before?(date, today) -> :overdue
          Date.diff(date, today) <= due_soon_days -> :due_soon
          true -> :up_to_date
        end
    end
  end

  @doc """
  The status rule as a SQL expression returning the status name.

  `item` and `cycle` are query bindings; `today` and `soon_until`
  (today plus the due-soon window) are pinned dates.
  """
  defmacro sql(item, cycle, today, soon_until) do
    quote do
      fragment(
        """
        CASE
          WHEN ? = 'archived' THEN 'archived'
          WHEN ? IS NOT NULL THEN ?
          WHEN COALESCE(?, ?) < ? THEN 'overdue'
          WHEN COALESCE(?, ?) <= ? THEN 'due_soon'
          ELSE 'up_to_date'
        END
        """,
        unquote(item).status,
        unquote(cycle).status_override,
        unquote(cycle).status_override,
        unquote(cycle).due_date,
        unquote(cycle).expiry_date,
        type(unquote(today), :date),
        unquote(cycle).due_date,
        unquote(cycle).expiry_date,
        type(unquote(soon_until), :date)
      )
    end
  end

  @doc "The date that drives status, as a SQL expression."
  defmacro effective_date_sql(cycle) do
    quote do
      fragment("COALESCE(?, ?)", unquote(cycle).due_date, unquote(cycle).expiry_date)
    end
  end
end

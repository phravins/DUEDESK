defmodule DueDesk.DueItems.Completion do
  @moduledoc """
  Form input for renewing or completing a DueItem: the day it was done,
  an optional note and, when the next date is set at each renewal, the
  next dates.

  The note is the person's own text. It is stored on the cycle and never
  written to audit events.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias DueDesk.DueItems.Cycle

  @next_fields [:next_start_date, :next_due_date, :next_expiry_date]

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field :completed_on, :date
    field :note, :string
    field :next_start_date, :date
    field :next_due_date, :date
    field :next_expiry_date, :date
  end

  @doc """
  Changeset for the renew and complete forms.

  ## Options

    * `:today` - today in the account timezone (required)
    * `:cycle` - the cycle being closed
    * `:explicit` - when true, the next dates are cast and checked
  """
  def changeset(completion, attrs, opts) do
    today = Keyword.fetch!(opts, :today)
    cycle = Keyword.get(opts, :cycle)
    explicit? = Keyword.get(opts, :explicit, false)
    fields = [:completed_on, :note] ++ if(explicit?, do: @next_fields, else: [])

    completion
    |> cast(attrs, fields)
    |> update_change(:note, &blank_to_nil/1)
    |> validate_required([:completed_on], message: "enter the date it was done")
    |> validate_length(:note, max: 2000)
    |> validate_completed_on(today, cycle)
    |> validate_next_dates(cycle)
  end

  @doc "True when any next date was entered."
  def next_dates?(%__MODULE__{} = completion),
    do: Enum.any?(@next_fields, &Map.get(completion, &1))

  @doc "The entered next dates, keyed like a cycle's dates."
  def next_dates(%__MODULE__{} = completion) do
    %{
      start_date: completion.next_start_date,
      due_date: completion.next_due_date,
      expiry_date: completion.next_expiry_date
    }
  end

  defp validate_completed_on(changeset, today, cycle) do
    case get_field(changeset, :completed_on) do
      nil ->
        changeset

      date ->
        start = cycle && cycle.start_date

        cond do
          Date.after?(date, today) ->
            add_error(changeset, :completed_on, "cannot be in the future")

          start && Date.before?(date, start) ->
            add_error(changeset, :completed_on, "cannot be before the Start Date")

          true ->
            changeset
        end
    end
  end

  # Next dates are optional: left blank, an Administrator sets them later.
  # Once any is entered they follow the usual date rules, and the new
  # Due (or Expiry) Date must come after the current one.
  defp validate_next_dates(changeset, cycle) do
    due = get_field(changeset, :next_due_date)
    expiry = get_field(changeset, :next_expiry_date)
    start = get_field(changeset, :next_start_date)
    current = Cycle.effective_date(cycle)
    next = due || expiry

    cond do
      is_nil(due) and is_nil(expiry) and is_nil(start) ->
        changeset

      is_nil(next) ->
        add_error(changeset, :next_due_date, "enter a Due Date or an Expiry Date")

      start && ((due && Date.after?(start, due)) || (expiry && Date.after?(start, expiry))) ->
        add_error(changeset, :next_start_date, "must be on or before the Due and Expiry Dates")

      current && not Date.after?(next, current) ->
        add_error(
          changeset,
          if(due, do: :next_due_date, else: :next_expiry_date),
          "must be after the current date (#{Calendar.strftime(current, "%d %b %Y")})"
        )

      true ->
        changeset
    end
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end

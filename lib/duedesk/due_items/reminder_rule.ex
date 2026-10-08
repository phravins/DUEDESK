defmodule DueDesk.DueItems.ReminderRule do
  @moduledoc """
  When reminders go out for a DueItem, as days from its effective date:
  negative is before, 0 is on the date and positive is after.
  """
  use Ecto.Schema

  @defaults [-90, -30, -7, 0, 1]
  @max_days 365

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "reminder_rules" do
    field :offset_days, :integer
    field :active, :boolean, default: true

    belongs_to :customer_account, DueDesk.Tenancy.CustomerAccount
    belongs_to :due_item, DueDesk.DueItems.DueItem

    timestamps(type: :utc_datetime)
  end

  @doc "The reminders every new DueItem starts with."
  def defaults, do: @defaults

  @doc "The largest number of days before or after a custom reminder may be."
  def max_days, do: @max_days

  @doc "True when `offset` is an allowed reminder offset."
  def valid_offset?(offset), do: is_integer(offset) and abs(offset) <= @max_days

  @doc "Describes an offset, e.g. \"30 days before\"."
  def describe(0), do: "On the Due Date"
  def describe(-1), do: "1 day before"
  def describe(1), do: "1 day after"
  def describe(offset) when offset < 0, do: "#{-offset} days before"
  def describe(offset), do: "#{offset} days after"
end

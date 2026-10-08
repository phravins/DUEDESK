defmodule DueDesk.DueItems.Cycle do
  @moduledoc """
  One period of a DueItem. Dates live only here: a DueItem's dates are
  the dates of its current cycle. A status override also lives on the
  cycle, so it ends when the next cycle starts.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @overrides ~w(overdue due_soon up_to_date)

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "due_item_cycles" do
    field :sequence, :integer
    field :start_date, :date
    field :due_date, :date
    field :expiry_date, :date

    field :status_override, :string
    field :status_override_reason, :string
    field :status_override_at, :utc_datetime

    field :completed_at, :utc_datetime
    field :completion_note, :string
    field :reviewed_at, :utc_datetime

    belongs_to :customer_account, DueDesk.Tenancy.CustomerAccount
    belongs_to :due_item, DueDesk.DueItems.DueItem
    belongs_to :status_override_by_user, DueDesk.Accounts.User
    belongs_to :completed_by_user, DueDesk.Accounts.User
    belongs_to :reviewed_by_user, DueDesk.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def overrides, do: @overrides

  @doc """
  Changeset for the cycle's dates. At least one of Due Date and Expiry
  Date is required.
  """
  def dates_changeset(cycle, attrs) do
    cycle
    |> cast(attrs, [:start_date, :due_date, :expiry_date])
    |> validate_dates()
  end

  @doc false
  def validate_dates(changeset) do
    due = get_field(changeset, :due_date)
    expiry = get_field(changeset, :expiry_date)
    start = get_field(changeset, :start_date)

    changeset =
      if is_nil(due) and is_nil(expiry) do
        add_error(changeset, :due_date, "enter a Due Date or an Expiry Date")
      else
        changeset
      end

    if start && ((due && Date.after?(start, due)) || (expiry && Date.after?(start, expiry))) do
      add_error(changeset, :start_date, "must be on or before the Due and Expiry Dates")
    else
      changeset
    end
  end

  @doc "Changeset for setting a status override with its reason."
  def override_changeset(cycle, status, reason, user_id) do
    cycle
    |> change(
      status_override: status,
      status_override_reason: reason && String.trim(reason),
      status_override_by_user_id: user_id,
      status_override_at: DateTime.utc_now(:second)
    )
    |> validate_required([:status_override])
    |> validate_inclusion(:status_override, @overrides)
    |> validate_required([:status_override_reason], message: "enter a reason")
    |> validate_length(:status_override_reason, max: 500)
  end

  @doc "Changeset that removes a status override."
  def clear_override_changeset(cycle) do
    change(cycle,
      status_override: nil,
      status_override_reason: nil,
      status_override_by_user_id: nil,
      status_override_at: nil
    )
  end

  @doc "The date that drives status: the Due Date, else the Expiry Date."
  def effective_date(%__MODULE__{due_date: due, expiry_date: expiry}), do: due || expiry
  def effective_date(nil), do: nil
end

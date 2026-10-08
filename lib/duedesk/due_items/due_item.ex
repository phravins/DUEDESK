defmodule DueDesk.DueItems.DueItem do
  @moduledoc """
  Something an account must renew, file or complete by a date: a
  licence, a registration, a policy, a contract.

  Dates live on the current cycle (`DueDesk.DueItems.Cycle`). The date,
  responsibility and reminder fields here are virtual: they carry form
  input to the context, which writes them to cycles, assignments and
  reminder rules.

  Users may set only the operational fields (`user_fields/0`). Everything
  else is a control field that only Administrators and Super Admins set.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias DueDesk.DueItems.{Assignment, Cycle, ReminderRule}

  @recurrences ~w(none monthly quarterly half_yearly annual custom)
  @recurrence_units ~w(day month explicit)
  @statuses ~w(active archived)

  @user_fields [
    :title,
    :description,
    :reference_number,
    :organisation_id,
    :category_id,
    :start_date,
    :due_date,
    :expiry_date
  ]
  @control_fields [:related_party, :recurrence, :recurrence_unit, :recurrence_interval]
  @assignment_fields [:primary_user_id, :additional_user_ids]

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "due_items" do
    field :title, :string
    field :description, :string
    field :reference_number, :string
    field :related_party, :string
    field :recurrence, :string, default: "none"
    field :recurrence_unit, :string
    field :recurrence_interval, :integer
    field :status, :string, default: "active"
    field :disposition_state, :string
    field :archived_at, :utc_datetime

    # Form input, written to the current cycle, assignments and reminder rules.
    field :start_date, :date, virtual: true
    field :due_date, :date, virtual: true
    field :expiry_date, :date, virtual: true
    field :primary_user_id, :binary_id, virtual: true
    field :additional_user_ids, {:array, :binary_id}, virtual: true, default: []
    field :reminder_offsets, {:array, :integer}, virtual: true, default: []

    belongs_to :customer_account, DueDesk.Tenancy.CustomerAccount
    belongs_to :organisation, DueDesk.Organisations.Organisation
    belongs_to :category, DueDesk.DueItems.Category
    belongs_to :current_cycle, Cycle
    belongs_to :created_by_user, DueDesk.Accounts.User
    belongs_to :archived_by_user, DueDesk.Accounts.User

    has_many :cycles, Cycle
    has_many :assignments, Assignment
    has_many :active_assignments, Assignment, where: [ended_at: nil]
    has_many :reminder_rules, ReminderRule

    timestamps(type: :utc_datetime)
  end

  def recurrences, do: @recurrences
  def recurrence_units, do: @recurrence_units
  def statuses, do: @statuses

  @doc "Fields any member may set when creating a DueItem."
  def user_fields, do: @user_fields

  @doc """
  Changeset for creating a DueItem.

  ## Options

    * `:control` - when true (Administrators and Super Admins), the
      control fields, responsibility and reminders are cast too. When
      false they are ignored, whatever the input says.
  """
  def create_changeset(item, attrs, opts \\ []) do
    control? = Keyword.get(opts, :control, false)
    attrs = clean_lists(attrs)

    fields =
      if control?, do: @user_fields ++ @control_fields ++ @assignment_fields, else: @user_fields

    item
    |> cast(attrs, if(control?, do: fields ++ [:reminder_offsets], else: fields))
    |> validate_item()
    |> validate_assignment()
    |> validate_reminders()
  end

  @doc """
  Changeset for editing a DueItem (Administrators and Super Admins). The
  item should have its virtual date and reminder fields loaded.
  """
  def update_changeset(item, attrs) do
    item
    |> cast(clean_lists(attrs), @user_fields ++ @control_fields ++ [:reminder_offsets])
    |> validate_item()
    |> validate_reminders()
  end

  @doc """
  Changeset for re-dating and reactivating a DueItem, or restoring an
  archived one (Administrators and Super Admins): dates of the cycle
  that starts, responsibility and reminders. The item should have these
  virtual fields loaded.
  """
  def reactivate_changeset(item, attrs) do
    item
    |> cast(
      clean_lists(attrs),
      [:start_date, :due_date, :expiry_date] ++ @assignment_fields ++ [:reminder_offsets]
    )
    |> Cycle.validate_dates()
    |> validate_assignment()
    |> validate_reminders()
  end

  defp validate_item(changeset) do
    changeset
    |> update_change(:title, &squish/1)
    |> update_change(:reference_number, &squish/1)
    |> update_change(:related_party, &squish/1)
    |> update_change(:description, &trim/1)
    |> validate_required([:title], message: "enter a title")
    |> validate_length(:title, min: 2, max: 160)
    |> validate_length(:description, max: 4000)
    |> validate_length(:reference_number, max: 100)
    |> validate_length(:related_party, max: 160)
    |> validate_required([:organisation_id], message: "choose an Organisation")
    |> validate_required([:category_id], message: "choose a category")
    |> Cycle.validate_dates()
    |> validate_recurrence()
    |> foreign_key_constraint(:organisation_id)
    |> foreign_key_constraint(:category_id)
  end

  defp validate_recurrence(changeset) do
    changeset =
      changeset
      |> validate_required([:recurrence])
      |> validate_inclusion(:recurrence, @recurrences)

    if get_field(changeset, :recurrence) == "custom" do
      changeset =
        changeset
        |> validate_required([:recurrence_unit], message: "choose how it repeats")
        |> validate_inclusion(:recurrence_unit, @recurrence_units)

      if get_field(changeset, :recurrence_unit) == "explicit" do
        put_change(changeset, :recurrence_interval, nil)
      else
        changeset
        |> validate_required([:recurrence_interval], message: "enter a number")
        |> validate_number(:recurrence_interval,
          greater_than_or_equal_to: 1,
          less_than_or_equal_to: 3650
        )
      end
    else
      changeset
      |> put_change(:recurrence_unit, nil)
      |> put_change(:recurrence_interval, nil)
    end
  end

  defp validate_assignment(changeset) do
    primary = get_field(changeset, :primary_user_id)
    additional = changeset |> get_field(:additional_user_ids) |> List.wrap()
    changeset = put_change(changeset, :additional_user_ids, Enum.uniq(additional -- [primary]))

    if is_nil(primary) and additional != [] do
      add_error(changeset, :primary_user_id, "choose a Primary Responsible first")
    else
      changeset
    end
  end

  defp validate_reminders(changeset) do
    offsets = changeset |> get_field(:reminder_offsets) |> List.wrap()

    if Enum.all?(offsets, &ReminderRule.valid_offset?/1) do
      put_change(changeset, :reminder_offsets, offsets |> Enum.uniq() |> Enum.sort())
    else
      add_error(
        changeset,
        :reminder_offsets,
        "reminders must be within #{ReminderRule.max_days()} days"
      )
    end
  end

  # Checkbox groups post a blank value so an empty selection is still sent.
  defp clean_lists(attrs) do
    Enum.reduce(["additional_user_ids", "reminder_offsets"], attrs, fn key, acc ->
      atom = String.to_existing_atom(key)

      cond do
        is_list(acc[key]) -> Map.put(acc, key, Enum.reject(acc[key], &(&1 in ["", nil])))
        is_list(acc[atom]) -> Map.put(acc, atom, Enum.reject(acc[atom], &(&1 in ["", nil])))
        true -> acc
      end
    end)
  end

  defp squish(nil), do: nil
  defp squish(value), do: value |> String.trim() |> String.replace(~r/\s+/u, " ")

  defp trim(nil), do: nil
  defp trim(value), do: String.trim(value)

  @doc "The active Primary Responsible user, from preloaded active assignments."
  def primary_user(%__MODULE__{active_assignments: assignments}) when is_list(assignments) do
    Enum.find_value(assignments, fn
      %Assignment{role: "primary", user: user} -> user
      _ -> nil
    end)
  end

  @doc "The active Additional Assignees, from preloaded active assignments."
  def additional_users(%__MODULE__{active_assignments: assignments}) when is_list(assignments) do
    for %Assignment{role: "additional", user: user} <- assignments, do: user
  end

  @doc "True when nobody is responsible for the item."
  def unassigned?(%__MODULE__{active_assignments: assignments}) when is_list(assignments),
    do: not Enum.any?(assignments, &(&1.role == "primary"))
end

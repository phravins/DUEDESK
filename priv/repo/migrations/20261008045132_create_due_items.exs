defmodule DueDesk.Repo.Migrations.CreateDueItems do
  use Ecto.Migration

  def change do
    create table(:due_items, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :customer_account_id,
          references(:customer_accounts, type: :binary_id, on_delete: :delete_all),
          null: false

      add :organisation_id,
          references(:organisations, type: :binary_id, on_delete: :restrict),
          null: false

      add :category_id, references(:categories, type: :binary_id, on_delete: :restrict),
        null: false

      add :title, :string, size: 160, null: false
      add :description, :text
      add :reference_number, :string
      add :related_party, :string
      add :recurrence, :string, null: false, default: "none"
      add :recurrence_unit, :string
      add :recurrence_interval, :integer
      add :status, :string, null: false, default: "active"
      add :disposition_state, :string
      add :archived_at, :utc_datetime
      add :archived_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :created_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:due_items, [:customer_account_id, :status])
    create index(:due_items, [:customer_account_id, :organisation_id])
    create index(:due_items, [:customer_account_id, :category_id])

    create constraint(:due_items, :status_valid, check: "status IN ('active', 'archived')")

    create constraint(:due_items, :recurrence_valid,
             check:
               "recurrence IN ('none', 'monthly', 'quarterly', 'half_yearly', 'annual', 'custom')"
           )

    create constraint(:due_items, :recurrence_unit_valid,
             check: "recurrence_unit IS NULL OR recurrence_unit IN ('day', 'month', 'explicit')"
           )

    create constraint(:due_items, :recurrence_interval_valid,
             check: "recurrence_interval IS NULL OR (recurrence_interval BETWEEN 1 AND 3650)"
           )

    create constraint(:due_items, :disposition_state_valid,
             check:
               "disposition_state IS NULL OR disposition_state IN ('awaiting_admin_disposition')"
           )

    # Dates live only on cycles; a DueItem points at its current cycle.
    create table(:due_item_cycles, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :customer_account_id,
          references(:customer_accounts, type: :binary_id, on_delete: :delete_all),
          null: false

      add :due_item_id, references(:due_items, type: :binary_id, on_delete: :delete_all),
        null: false

      add :sequence, :integer, null: false
      add :start_date, :date
      add :due_date, :date
      add :expiry_date, :date

      add :status_override, :string
      add :status_override_reason, :string, size: 500

      add :status_override_by_user_id,
          references(:users, type: :binary_id, on_delete: :nilify_all)

      add :status_override_at, :utc_datetime

      add :completed_at, :utc_datetime
      add :completed_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :completion_note, :text
      add :reviewed_at, :utc_datetime
      add :reviewed_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:due_item_cycles, [:due_item_id, :sequence])
    create index(:due_item_cycles, [:customer_account_id])

    create constraint(:due_item_cycles, :a_date_present,
             check: "due_date IS NOT NULL OR expiry_date IS NOT NULL"
           )

    create constraint(:due_item_cycles, :status_override_valid,
             check:
               "status_override IS NULL OR status_override IN ('overdue', 'due_soon', 'up_to_date')"
           )

    alter table(:due_items) do
      add :current_cycle_id,
          references(:due_item_cycles, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:due_items, [:current_cycle_id])

    # Rows are never deleted: ending an assignment sets ended_at.
    create table(:due_item_assignments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :customer_account_id,
          references(:customer_accounts, type: :binary_id, on_delete: :delete_all),
          null: false

      add :due_item_id, references(:due_items, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :assigned_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :assigned_at, :utc_datetime, null: false
      add :ended_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create constraint(:due_item_assignments, :role_valid,
             check: "role IN ('primary', 'additional')"
           )

    create unique_index(:due_item_assignments, [:due_item_id],
             where: "role = 'primary' AND ended_at IS NULL",
             name: :due_item_assignments_one_active_primary_index
           )

    create unique_index(:due_item_assignments, [:due_item_id, :user_id],
             where: "ended_at IS NULL",
             name: :due_item_assignments_one_active_per_user_index
           )

    create index(:due_item_assignments, [:customer_account_id, :user_id],
             where: "ended_at IS NULL"
           )

    create table(:reminder_rules, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :customer_account_id,
          references(:customer_accounts, type: :binary_id, on_delete: :delete_all),
          null: false

      add :due_item_id, references(:due_items, type: :binary_id, on_delete: :delete_all),
        null: false

      add :offset_days, :integer, null: false
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:reminder_rules, [:due_item_id, :offset_days])

    create constraint(:reminder_rules, :offset_days_valid,
             check: "offset_days BETWEEN -365 AND 365"
           )

    # Append-only notes on a DueItem.
    create table(:due_item_notes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :customer_account_id,
          references(:customer_accounts, type: :binary_id, on_delete: :delete_all),
          null: false

      add :due_item_id, references(:due_items, type: :binary_id, on_delete: :delete_all),
        null: false

      add :cycle_id, references(:due_item_cycles, type: :binary_id, on_delete: :nilify_all)
      add :author_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :body, :text, null: false

      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create index(:due_item_notes, [:due_item_id, :inserted_at])
  end
end

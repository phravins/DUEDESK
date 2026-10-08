defmodule DueDesk.Repo.Migrations.CreateNotificationDeliveries do
  use Ecto.Migration

  def change do
    # One row per message to one person on one channel. `dedupe_key` is
    # unique, so a reminder or event notice is queued at most once however
    # often the scan runs or a job retries.
    create table(:notification_deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :customer_account_id,
          references(:customer_accounts, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :due_item_id, references(:due_items, type: :binary_id, on_delete: :delete_all)
      add :cycle_id, references(:due_item_cycles, type: :binary_id, on_delete: :delete_all)

      add :reminder_rule_id,
          references(:reminder_rules, type: :binary_id, on_delete: :nilify_all)

      add :kind, :string, null: false
      add :channel, :string, null: false
      add :target_date, :date
      add :offset_days, :integer
      add :escalated, :boolean, null: false, default: false
      add :status, :string, null: false, default: "pending"
      add :attempts, :integer, null: false, default: 0
      add :error, :string, size: 64
      add :sent_at, :utc_datetime
      add :dedupe_key, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:notification_deliveries, [:dedupe_key])
    create index(:notification_deliveries, [:due_item_id, :inserted_at])
    create index(:notification_deliveries, [:customer_account_id])
    create index(:notification_deliveries, [:user_id])

    create constraint(:notification_deliveries, :kind_valid,
             check: "kind IN ('reminder', 'assignment', 'renewal_review', 'awaiting_disposition')"
           )

    create constraint(:notification_deliveries, :channel_valid,
             check: "channel IN ('email', 'whatsapp')"
           )

    create constraint(:notification_deliveries, :status_valid,
             check: "status IN ('pending', 'sent', 'failed', 'skipped')"
           )
  end
end

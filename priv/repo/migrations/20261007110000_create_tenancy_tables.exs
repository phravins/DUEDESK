defmodule DueDesk.Repo.Migrations.CreateTenancyTables do
  use Ecto.Migration

  def change do
    create table(:customer_accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :status, :string, null: false, default: "active"
      add :plan_code, :string, null: false, default: "free"
      add :billing_state, :string, null: false, default: "free"
      add :timezone, :string, null: false, default: "Asia/Kolkata"
      add :country, :string, null: false, default: "IN"
      add :currency, :string, null: false, default: "INR"
      add :due_soon_days, :integer, null: false, default: 30
      add :storage_used_bytes, :bigint, null: false, default: 0
      add :notification_mobile, :string
      add :closed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create constraint(:customer_accounts, :status_valid,
             check: "status IN ('active', 'suspended', 'closed')"
           )

    create constraint(:customer_accounts, :due_soon_days_range,
             check: "due_soon_days BETWEEN 1 AND 365"
           )

    create table(:customer_account_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :customer_account_id,
          references(:customer_accounts, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :status, :string, null: false, default: "active"
      add :notify_email, :boolean, null: false, default: true
      add :notify_whatsapp, :boolean, null: false, default: false
      add :whatsapp_consent_at, :utc_datetime
      add :deactivated_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:customer_account_memberships, [:customer_account_id, :user_id])
    create index(:customer_account_memberships, [:user_id])

    create constraint(:customer_account_memberships, :role_valid,
             check: "role IN ('super_admin', 'admin', 'user')"
           )

    create constraint(:customer_account_memberships, :status_valid,
             check: "status IN ('active', 'deactivated')"
           )

    create table(:invitations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :customer_account_id,
          references(:customer_accounts, type: :binary_id, on_delete: :delete_all),
          null: false

      add :email, :citext, null: false
      add :role, :string, null: false
      add :token_hash, :binary, null: false
      add :invited_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :expires_at, :utc_datetime, null: false
      add :accepted_at, :utc_datetime
      add :revoked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:invitations, [:token_hash])
    create index(:invitations, [:customer_account_id])

    create constraint(:invitations, :role_valid, check: "role IN ('admin', 'user')")
  end
end

defmodule DueDesk.Repo.Migrations.CreateOrganisationsAndCategories do
  use Ecto.Migration

  # Copied (not referenced) from DueDesk.Categories so this migration keeps
  # working if the application list changes later.
  @default_categories [
    "GST & Income Tax",
    "Company / LLP Filings (ROC)",
    "Licences & Permits",
    "Labour Compliance (PF/ESI)",
    "Insurance",
    "Contracts & Agreements",
    "Property & Rent",
    "Vehicles",
    "Certifications",
    "Banking & Loans",
    "Subscriptions & Utilities",
    "Other"
  ]

  def change do
    create table(:organisations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :customer_account_id,
          references(:customer_accounts, type: :binary_id, on_delete: :delete_all),
          null: false

      add :name, :string, null: false
      add :type, :string, null: false
      add :identifier_type, :string, null: false
      add :identifier, :string, null: false
      add :normalized_identifier, :string, null: false
      add :gstin, :string
      add :status, :string, null: false, default: "active"
      add :archived_at, :utc_datetime
      add :archived_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :created_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    # Unique across every Customer Account: one business, one owner account.
    create unique_index(:organisations, [:identifier_type, :normalized_identifier])
    create index(:organisations, [:customer_account_id, :status])

    create constraint(:organisations, :type_valid,
             check: "type IN ('proprietorship', 'partnership', 'llp', 'private_limited')"
           )

    create constraint(:organisations, :identifier_type_valid,
             check: "identifier_type IN ('udyam', 'llpin', 'cin')"
           )

    create constraint(:organisations, :status_valid, check: "status IN ('active', 'archived')")

    create table(:organisation_declarations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :customer_account_id,
          references(:customer_accounts, type: :binary_id, on_delete: :delete_all),
          null: false

      add :organisation_id,
          references(:organisations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :version, :string, null: false
      add :text_hash, :string, null: false
      add :accepted_at, :utc_datetime_usec, null: false
      add :ip, :string
      add :user_agent, :string, size: 512

      add :inserted_at, :utc_datetime, null: false, default: fragment("now()")
    end

    create index(:organisation_declarations, [:organisation_id])
    create index(:organisation_declarations, [:customer_account_id])

    create table(:categories, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :customer_account_id,
          references(:customer_accounts, type: :binary_id, on_delete: :delete_all),
          null: false

      add :name, :string, null: false
      add :system, :boolean, null: false, default: false
      add :status, :string, null: false, default: "active"
      add :position, :integer, null: false, default: 0
      add :archived_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:categories, ["customer_account_id", "lower(name)"],
             name: :categories_customer_account_id_name_index
           )

    create constraint(:categories, :status_valid, check: "status IN ('active', 'archived')")

    execute(backfill_categories_sql(), "SELECT 1")
  end

  defp backfill_categories_sql do
    values =
      @default_categories
      |> Enum.with_index(1)
      |> Enum.map_join(", ", fn {name, position} ->
        "('#{String.replace(name, "'", "''")}', #{position})"
      end)

    """
    INSERT INTO categories
      (id, customer_account_id, name, system, status, position, inserted_at, updated_at)
    SELECT gen_random_uuid(), a.id, d.name, true, 'active', d.position, now(), now()
    FROM customer_accounts a
    CROSS JOIN (VALUES #{values}) AS d(name, position)
    """
  end
end

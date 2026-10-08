defmodule DueDesk.Repo.Migrations.CreateDocuments do
  use Ecto.Migration

  def change do
    # One row per stored file. A document belongs to exactly one cycle of
    # one DueItem and is never shared, so there is no link table.
    create table(:documents, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :customer_account_id,
          references(:customer_accounts, type: :binary_id, on_delete: :delete_all),
          null: false

      add :due_item_id, references(:due_items, type: :binary_id, on_delete: :delete_all),
        null: false

      add :cycle_id, references(:due_item_cycles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :uploaded_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :role, :string, null: false
      add :filename, :string, size: 255, null: false
      add :storage_key, :string, size: 512, null: false
      add :content_type, :string, null: false
      add :byte_size, :bigint, null: false
      add :checksum_sha256, :string, size: 64, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:documents, [:storage_key])
    create index(:documents, [:cycle_id])
    create index(:documents, [:due_item_id])
    create index(:documents, [:customer_account_id])

    create constraint(:documents, :role_valid,
             check: "role IN ('current', 'supporting', 'completion')"
           )

    create constraint(:documents, :byte_size_positive, check: "byte_size > 0")
  end
end

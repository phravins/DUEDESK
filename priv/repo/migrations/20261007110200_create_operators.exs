defmodule DueDesk.Repo.Migrations.CreateOperators do
  use Ecto.Migration

  def change do
    # Internal DueDesk staff for the operator console. Kept apart from
    # customer users so a customer login can never reach /admin.
    create table(:operators, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :email, :citext, null: false
      add :hashed_password, :string, null: false
      add :active, :boolean, null: false, default: true
      add :last_login_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:operators, [:email])
  end
end

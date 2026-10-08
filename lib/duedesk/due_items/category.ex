defmodule DueDesk.DueItems.Category do
  @moduledoc """
  An account-level label for DueItems, such as "Insurance". System
  categories are copied into every new account and cannot be changed;
  custom categories can be added, renamed, archived and restored. There is
  no nesting.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "categories" do
    field :name, :string
    field :system, :boolean, default: false
    field :status, :string, default: "active"
    field :position, :integer, default: 0
    field :archived_at, :utc_datetime

    belongs_to :customer_account, DueDesk.Tenancy.CustomerAccount

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name])
    |> update_change(:name, &(&1 |> String.trim() |> String.replace(~r/\s+/u, " ")))
    |> validate_required([:name], message: "enter a category name")
    |> validate_length(:name, min: 2, max: 60)
    |> unique_constraint(:name,
      name: :categories_customer_account_id_name_index,
      message: "a category with this name already exists"
    )
  end
end

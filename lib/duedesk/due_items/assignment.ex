defmodule DueDesk.DueItems.Assignment do
  @moduledoc """
  Who is responsible for a DueItem. Each item has at most one active
  Primary Responsible and any number of Additional Assignees. Rows are
  never deleted; ending an assignment sets `ended_at`.
  """
  use Ecto.Schema

  @roles ~w(primary additional)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "due_item_assignments" do
    field :role, :string
    field :assigned_at, :utc_datetime
    field :ended_at, :utc_datetime

    belongs_to :customer_account, DueDesk.Tenancy.CustomerAccount
    belongs_to :due_item, DueDesk.DueItems.DueItem
    belongs_to :user, DueDesk.Accounts.User
    belongs_to :assigned_by_user, DueDesk.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def roles, do: @roles
end

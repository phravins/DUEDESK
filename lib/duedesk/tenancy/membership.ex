defmodule DueDesk.Tenancy.Membership do
  @moduledoc """
  Links a user to a Customer Account with an account-level role.

  Roles are `super_admin`, `admin` and `user`. Organisations never grant
  access; only the membership role and DueItem assignments do.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(super_admin admin user)
  @statuses ~w(active deactivated)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "customer_account_memberships" do
    field :role, :string
    field :status, :string, default: "active"
    field :notify_email, :boolean, default: true
    field :notify_whatsapp, :boolean, default: false
    field :whatsapp_consent_at, :utc_datetime
    field :deactivated_at, :utc_datetime

    belongs_to :customer_account, DueDesk.Tenancy.CustomerAccount
    belongs_to :user, DueDesk.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def roles, do: @roles
  def statuses, do: @statuses

  @doc false
  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role, :status, :notify_email, :notify_whatsapp, :whatsapp_consent_at])
    |> validate_required([:role, :status])
    |> validate_inclusion(:role, @roles)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:customer_account_id, :user_id])
  end

  @doc "Human label for a role."
  def role_label("super_admin"), do: "Super Admin"
  def role_label("admin"), do: "Administrator"
  def role_label("user"), do: "User"
end

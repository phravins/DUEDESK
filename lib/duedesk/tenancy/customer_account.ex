defmodule DueDesk.Tenancy.CustomerAccount do
  @moduledoc """
  A Customer Account is the tenancy and subscription boundary. Every
  business record in DueDesk belongs to exactly one Customer Account.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias DueDesk.Accounts.User

  @statuses ~w(active suspended closed)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "customer_accounts" do
    field :name, :string
    field :status, :string, default: "active"
    field :plan_code, :string, default: "free"
    field :billing_state, :string, default: "free"
    field :timezone, :string, default: "Asia/Kolkata"
    field :country, :string, default: "IN"
    field :currency, :string, default: "INR"
    field :due_soon_days, :integer, default: 30
    field :storage_used_bytes, :integer, default: 0
    field :notification_mobile, :string
    field :closed_at, :utc_datetime

    # Virtual: WhatsApp consent captured during account setup, stored on the membership.
    field :whatsapp_consent, :boolean, virtual: true, default: false

    has_many :memberships, DueDesk.Tenancy.Membership

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  @doc """
  Changeset for account setup during onboarding.
  """
  def setup_changeset(account, attrs) do
    account
    |> cast(attrs, [:name, :notification_mobile, :whatsapp_consent])
    |> validate_name()
    |> User.validate_mobile_number(field: :notification_mobile, required: true)
  end

  @doc """
  Changeset for account settings edited by a Super Admin.
  """
  def settings_changeset(account, attrs) do
    account
    |> cast(attrs, [:name, :notification_mobile, :due_soon_days])
    |> validate_name()
    |> User.validate_mobile_number(field: :notification_mobile)
    |> validate_number(:due_soon_days, greater_than_or_equal_to: 1, less_than_or_equal_to: 365)
  end

  defp validate_name(changeset) do
    changeset
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name], message: "enter your account name")
    |> validate_length(:name, min: 2, max: 120)
  end
end

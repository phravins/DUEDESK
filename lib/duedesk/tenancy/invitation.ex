defmodule DueDesk.Tenancy.Invitation do
  @moduledoc """
  An email invitation to join a Customer Account as an Administrator or
  User. Only the SHA-256 hash of the token is stored.
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "invitations" do
    field :email, :string
    field :role, :string
    field :token_hash, :binary, redact: true
    field :expires_at, :utc_datetime
    field :accepted_at, :utc_datetime
    field :revoked_at, :utc_datetime

    belongs_to :customer_account, DueDesk.Tenancy.CustomerAccount
    belongs_to :invited_by, DueDesk.Accounts.User, foreign_key: :invited_by_user_id

    timestamps(type: :utc_datetime)
  end
end

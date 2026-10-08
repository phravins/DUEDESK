defmodule DueDesk.Tenancy.Invitation do
  @moduledoc """
  An email invitation to join a Customer Account as an Administrator or
  User. Only the SHA-256 hash of the token is stored.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(admin user)
  @validity_days 7

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

  def roles, do: @roles
  def validity_days, do: @validity_days

  @doc "The invite form: email and role."
  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:email, :role])
    |> update_change(:email, &String.trim/1)
    |> validate_required([:email], message: "enter an email address")
    |> validate_required([:role], message: "choose a role")
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+\.[^@,;\s]+$/,
      message: "must be a valid email address"
    )
    |> validate_length(:email, max: 160)
    |> validate_inclusion(:role, @roles)
  end

  @doc """
  The state of an invitation at `now`: `:pending`, `:accepted`,
  `:revoked` or `:expired`.
  """
  def state(%__MODULE__{} = invitation, now \\ DateTime.utc_now(:second)) do
    cond do
      invitation.accepted_at -> :accepted
      invitation.revoked_at -> :revoked
      DateTime.compare(invitation.expires_at, now) != :gt -> :expired
      true -> :pending
    end
  end
end

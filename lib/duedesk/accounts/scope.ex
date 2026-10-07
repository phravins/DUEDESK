defmodule DueDesk.Accounts.Scope do
  @moduledoc """
  The caller of a context function.

  For signed-in pages the scope carries the user and, once the user belongs
  to a Customer Account, the account, the membership and the account-level
  role. Every tenant query is filtered by `scope.customer_account.id` and
  every permission check (see `DueDesk.Permissions`) reads `scope.role`.
  """

  alias DueDesk.Accounts.User
  alias DueDesk.Tenancy.{CustomerAccount, Membership}

  @type role :: :super_admin | :admin | :user | nil

  @type t :: %__MODULE__{
          user: User.t() | nil,
          customer_account: CustomerAccount.t() | nil,
          membership: Membership.t() | nil,
          role: role()
        }

  defstruct user: nil, customer_account: nil, membership: nil, role: nil

  @doc """
  Creates a scope for the given user.

  Returns nil if no user is given.
  """
  def for_user(%User{} = user) do
    %__MODULE__{user: user}
  end

  def for_user(nil), do: nil

  @doc """
  Puts the Customer Account and membership on the scope.
  """
  def put_membership(
        %__MODULE__{user: %User{id: user_id}} = scope,
        %Membership{user_id: user_id, customer_account: %CustomerAccount{} = account} = membership
      ) do
    %{scope | customer_account: account, membership: membership, role: role(membership.role)}
  end

  defp role("super_admin"), do: :super_admin
  defp role("admin"), do: :admin
  defp role("user"), do: :user

  @doc "Returns the account id for the scope, raising if there is none."
  def account_id!(%__MODULE__{customer_account: %CustomerAccount{id: id}}), do: id
end

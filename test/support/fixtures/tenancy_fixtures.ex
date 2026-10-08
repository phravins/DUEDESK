defmodule DueDesk.TenancyFixtures do
  @moduledoc """
  Test helpers for Customer Accounts and memberships.
  """

  alias DueDesk.{Repo, Tenancy}
  alias DueDesk.Accounts.Scope
  alias DueDesk.Tenancy.Membership

  import DueDesk.AccountsFixtures

  @doc """
  Creates a Customer Account whose Super Admin is `user` (a new user by
  default). Returns the Super Admin's scope.
  """
  def account_scope_fixture(user \\ nil, attrs \\ %{}) do
    user = user || user_fixture()

    {:ok, %{membership: membership}} =
      Tenancy.create_customer_account(
        Scope.for_user(user),
        Enum.into(attrs, %{
          name: "Acme #{System.unique_integer([:positive])}",
          notification_mobile: "9876543210"
        })
      )

    Scope.put_membership(Scope.for_user(user), membership)
  end

  @doc """
  Adds a member with `role` ("admin" or "user") to the account of `scope`.
  Returns the new member's scope.
  """
  def member_scope_fixture(%Scope{customer_account: account}, role, user \\ nil) do
    user = user || user_fixture()

    membership =
      %Membership{customer_account_id: account.id, user_id: user.id}
      |> Membership.changeset(%{role: role, status: "active"})
      |> Repo.insert!()

    Scope.put_membership(Scope.for_user(user), %{membership | customer_account: account})
  end

  @doc """
  Moves the scope's account to `plan_code` and returns the updated scope.
  """
  def put_plan(%Scope{customer_account: account} = scope, plan_code) do
    account =
      account
      |> Ecto.Changeset.change(plan_code: plan_code)
      |> Repo.update!()

    %{
      scope
      | customer_account: account,
        membership: %{scope.membership | customer_account: account}
    }
  end
end

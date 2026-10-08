defmodule DueDesk.Billing do
  @moduledoc """
  Plan entitlements: what an account is using and whether it may add more.

  Feature code never compares plan codes; it calls `check/2` and shows
  `limit_message/2` when a limit is reached. Archived records do not count
  toward limits.
  """

  import Ecto.Query, warn: false

  alias DueDesk.{Permissions, Repo}
  alias DueDesk.Accounts.Scope
  alias DueDesk.Billing.Plans
  alias DueDesk.Organisations.Organisation
  alias DueDesk.Tenancy.Membership

  @type resource :: :organisation | :member
  @type limit_info :: %{plan: map(), limit: non_neg_integer(), resource: resource()}

  @doc "The plan of the scope's account."
  def plan(%Scope{customer_account: account}), do: Plans.get(account.plan_code)

  @doc """
  Current usage of the scope's account:

    * `:organisations` — active Organisations
    * `:members` — active Administrators and Users (Super Admins are not counted)
    * `:super_admins` — active Super Admins
    * `:due_items` — active DueItems (from Phase 2)
    * `:storage_bytes` — stored document bytes
  """
  def usage(%Scope{} = scope) do
    account_id = Scope.account_id!(scope)

    roles =
      from(m in Membership,
        where: m.customer_account_id == ^account_id and m.status == "active",
        group_by: m.role,
        select: {m.role, count(m.id)}
      )
      |> Repo.all()
      |> Map.new()

    %{
      organisations: count_active_organisations(account_id),
      members: Map.get(roles, "admin", 0) + Map.get(roles, "user", 0),
      super_admins: Map.get(roles, "super_admin", 0),
      due_items: 0,
      storage_bytes: scope.customer_account.storage_used_bytes
    }
  end

  @doc """
  Checks whether the scope's account may add one more `resource`.

  Returns `:ok` or `{:error, {:limit_reached, info}}`. Call it inside the
  transaction that adds the record, after locking the account row.
  """
  @spec check(Scope.t(), resource()) :: :ok | {:error, {:limit_reached, limit_info()}}
  def check(%Scope{} = scope, resource) do
    plan = plan(scope)
    limit = limit_for(plan, resource)

    cond do
      limit == :unlimited -> :ok
      used(scope, resource) < limit -> :ok
      true -> {:error, {:limit_reached, %{plan: plan, limit: limit, resource: resource}}}
    end
  end

  defp limit_for(plan, :organisation), do: plan.max_organisations
  defp limit_for(plan, :member), do: plan.max_members

  defp used(scope, :organisation), do: count_active_organisations(Scope.account_id!(scope))
  defp used(scope, :member), do: usage(scope).members

  defp count_active_organisations(account_id) do
    from(o in Organisation,
      where: o.customer_account_id == ^account_id and o.status == "active",
      select: count(o.id)
    )
    |> Repo.one()
  end

  @doc """
  The message shown when a limit is reached. Super Admins are pointed to
  the plans; everyone else is asked to contact their Super Admin.
  """
  def limit_message(%Scope{} = scope, %{plan: plan, limit: limit, resource: resource}) do
    reached = "You have reached the #{plan.name} Plan limit of #{limit} #{noun(resource, limit)}."

    if Permissions.can_manage_billing?(scope) do
      reached <> " Upgrade your plan to add more."
    else
      reached <> " Ask your Super Admin to upgrade the plan."
    end
  end

  defp noun(:organisation, 1), do: "Organisation"
  defp noun(:organisation, _), do: "Organisations"
  defp noun(:member, 1), do: "Administrator or User"
  defp noun(:member, _), do: "Administrators and Users"
end

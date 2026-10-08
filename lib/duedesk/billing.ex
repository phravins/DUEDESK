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
  alias DueDesk.DueItems.DueItem
  alias DueDesk.Organisations.Organisation
  alias DueDesk.Tenancy.{Invitation, Membership}

  @type resource :: :organisation | :member | :super_admin | :due_item | :storage
  @type limit_info :: %{plan: map(), limit: non_neg_integer(), resource: resource()}

  @doc "The plan of the scope's account."
  def plan(%Scope{customer_account: account}), do: Plans.get(account.plan_code)

  @doc """
  Current usage of the scope's account:

    * `:organisations` — active Organisations
    * `:members` — active Administrators and Users (Super Admins are not counted)
    * `:invitations` — pending invitations, which hold a seat until they
      are accepted, revoked or expire
    * `:super_admins` — active Super Admins
    * `:due_items` — DueItems that are not archived (including those
      awaiting disposition)
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
      invitations: count_pending_invitations(account_id),
      super_admins: Map.get(roles, "super_admin", 0),
      due_items: count_due_items(account_id),
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

  @doc """
  Checks whether `adding` more bytes fit in the plan's storage, given
  `used` bytes read from the locked account row. Reaching the limit only
  blocks uploads; nothing is ever deleted automatically.

  Returns `:ok` or `{:error, {:limit_reached, info}}`, where `info` also
  has `:used`.
  """
  @spec check_storage(Scope.t(), non_neg_integer(), non_neg_integer()) ::
          :ok | {:error, {:limit_reached, map()}}
  def check_storage(%Scope{} = scope, used, adding) do
    plan = plan(scope)

    if used + adding <= plan.storage_bytes,
      do: :ok,
      else:
        {:error,
         {:limit_reached,
          %{plan: plan, limit: plan.storage_bytes, resource: :storage, used: used}}}
  end

  @doc """
  The account's storage, read fresh: `%{used: bytes, limit: bytes,
  left: bytes}`.
  """
  def storage(%Scope{} = scope) do
    account_id = Scope.account_id!(scope)
    limit = plan(scope).storage_bytes

    used =
      Repo.one(
        from(a in DueDesk.Tenancy.CustomerAccount,
          where: a.id == ^account_id,
          select: a.storage_used_bytes
        )
      ) || 0

    %{used: used, limit: limit, left: max(limit - used, 0)}
  end

  defp limit_for(plan, :organisation), do: plan.max_organisations
  defp limit_for(plan, :member), do: plan.max_members
  defp limit_for(plan, :super_admin), do: plan.max_super_admins
  defp limit_for(plan, :due_item), do: plan.max_due_items

  defp used(scope, :organisation), do: count_active_organisations(Scope.account_id!(scope))

  defp used(scope, :member) do
    usage = usage(scope)
    usage.members + usage.invitations
  end

  defp used(scope, :super_admin), do: usage(scope).super_admins
  defp used(scope, :due_item), do: count_due_items(Scope.account_id!(scope))

  defp count_active_organisations(account_id) do
    from(o in Organisation,
      where: o.customer_account_id == ^account_id and o.status == "active",
      select: count(o.id)
    )
    |> Repo.one()
  end

  defp count_pending_invitations(account_id) do
    now = DateTime.utc_now(:second)

    from(i in Invitation,
      where:
        i.customer_account_id == ^account_id and is_nil(i.accepted_at) and
          is_nil(i.revoked_at) and i.expires_at > ^now,
      select: count(i.id)
    )
    |> Repo.one()
  end

  @doc """
  Seats for Administrators and Users: `%{used: n, limit: n}`, where
  `used` counts active members and pending invitations.
  """
  def seats(%Scope{} = scope) do
    %{used: used(scope, :member), limit: plan(scope).max_members}
  end

  @doc "Whether the plan allows more than one Super Admin."
  def multiple_super_admins?(%Scope{} = scope), do: plan(scope).max_super_admins > 1

  defp count_due_items(account_id) do
    from(i in DueItem,
      where: i.customer_account_id == ^account_id and i.status != "archived",
      select: count(i.id)
    )
    |> Repo.one()
  end

  @doc """
  The message shown when a limit is reached. Super Admins are pointed to
  the plans; everyone else is asked to contact their Super Admin.
  """
  def limit_message(%Scope{} = scope, %{plan: plan, limit: limit, resource: resource} = info) do
    reached = reached(plan, limit, resource, info)

    if Permissions.can_manage_billing?(scope) do
      reached <> " Upgrade your plan to add more."
    else
      reached <> " Ask your Super Admin to upgrade the plan."
    end
  end

  defp reached(plan, limit, :storage, info) do
    left = max(limit - Map.get(info, :used, limit), 0)

    if left == 0,
      do: "You have reached the #{plan.name} Plan storage limit of #{Plans.format_bytes(limit)}.",
      else:
        "Not enough storage left: #{Plans.format_bytes(left)} of #{Plans.format_bytes(limit)} remaining."
  end

  defp reached(plan, limit, resource, _info),
    do: "You have reached the #{plan.name} Plan limit of #{limit} #{noun(resource, limit)}."

  defp noun(:organisation, 1), do: "Organisation"
  defp noun(:organisation, _), do: "Organisations"
  defp noun(:member, 1), do: "Administrator or User"
  defp noun(:member, _), do: "Administrators and Users"
  defp noun(:super_admin, 1), do: "Super Admin"
  defp noun(:super_admin, _), do: "Super Admins"
  defp noun(:due_item, 1), do: "DueItem"
  defp noun(:due_item, _), do: "DueItems"
end

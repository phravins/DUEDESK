defmodule DueDesk.Tenancy do
  @moduledoc """
  Customer Accounts, memberships and invitations: inviting people,
  accepting invitations, deactivating and reactivating members, role
  changes and Super Admin appointments.

  All functions that read tenant data take a `DueDesk.Accounts.Scope` and
  filter by the scope's account. Nothing here ever looks up a record by id
  alone.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias DueDesk.{Audit, Billing, Categories, Notifications, Permissions, Repo}
  alias DueDesk.Accounts.{Scope, User}
  alias DueDesk.DueItems.{Assignment, DueItem, Steps}
  alias DueDesk.Tenancy.{CustomerAccount, Invitation, MemberNotifier, Membership}

  ## Account setup (onboarding)

  @doc """
  Returns a changeset for the account setup form.
  """
  def change_account_setup(attrs \\ %{}) do
    CustomerAccount.setup_changeset(%CustomerAccount{}, attrs)
  end

  @doc """
  Creates a Customer Account, makes the scope's user its Super Admin and
  copies the default categories into it.

  Runs in one transaction with the audit event. Returns
  `{:ok, %{customer_account: account, membership: membership}}`.
  """
  def create_customer_account(%Scope{user: %User{} = user} = scope, attrs) do
    changeset = CustomerAccount.setup_changeset(%CustomerAccount{}, attrs)
    consent? = Ecto.Changeset.get_field(changeset, :whatsapp_consent) == true
    now = DateTime.utc_now(:second)

    Multi.new()
    |> Multi.insert(:customer_account, changeset)
    |> Multi.insert(:membership, fn %{customer_account: account} ->
      %Membership{customer_account_id: account.id, user_id: user.id}
      |> Membership.changeset(%{
        role: "super_admin",
        status: "active",
        notify_email: true,
        notify_whatsapp: consent?,
        whatsapp_consent_at: if(consent?, do: now)
      })
    end)
    |> Categories.multi_insert_defaults(:categories, & &1.customer_account)
    |> Audit.multi_log(:audit, scope, "account.created", & &1.customer_account,
      customer_account_id: & &1.customer_account.id,
      metadata: %{whatsapp_consent: consent?}
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{customer_account: account, membership: membership}} ->
        {:ok, %{customer_account: account, membership: %{membership | customer_account: account}}}

      {:error, _step, changeset, _} ->
        {:error, changeset}
    end
  end

  ## Memberships

  @doc """
  Returns the active membership the user works in, with the account
  preloaded, or nil if the user has not set up or joined an account.

  V1 users belong to one account; if there are several, the oldest wins.
  """
  def get_current_membership(%User{id: user_id}) do
    from(m in Membership,
      join: a in assoc(m, :customer_account),
      where: m.user_id == ^user_id and m.status == "active" and a.status != "closed",
      order_by: [asc: m.inserted_at],
      limit: 1,
      preload: [customer_account: a]
    )
    |> Repo.one()
  end

  @doc """
  Lists the memberships of the scope's account with users preloaded.
  """
  def list_memberships(%Scope{} = scope) do
    account_id = Scope.account_id!(scope)

    from(m in Membership,
      join: u in assoc(m, :user),
      where: m.customer_account_id == ^account_id,
      order_by: [asc: u.name],
      preload: [user: u]
    )
    |> Repo.all()
  end

  @doc """
  Gets a membership of the scope's account. Raises if it belongs to
  another account or does not exist.
  """
  def get_membership!(%Scope{} = scope, id) do
    account_id = Scope.account_id!(scope)

    from(m in Membership,
      where: m.id == ^id and m.customer_account_id == ^account_id,
      preload: [:user]
    )
    |> Repo.one!()
  end

  ## Notification preferences

  @notification_types %{
    notify_email: :boolean,
    notify_whatsapp: :boolean,
    whatsapp_consent: :boolean
  }

  @doc """
  Returns a changeset for the scope's own notification preferences:
  Email reminders, WhatsApp reminders and consent to WhatsApp messages.
  WhatsApp needs both the consent and a mobile number on the profile.
  """
  def change_notification_preferences(%Scope{membership: %Membership{} = m} = scope, attrs \\ %{}) do
    data = %{
      notify_email: m.notify_email,
      notify_whatsapp: m.notify_whatsapp,
      whatsapp_consent: not is_nil(m.whatsapp_consent_at)
    }

    {data, @notification_types}
    |> Ecto.Changeset.cast(attrs, Map.keys(@notification_types))
    |> validate_whatsapp(scope)
  end

  defp validate_whatsapp(changeset, %Scope{user: user}) do
    cond do
      Ecto.Changeset.get_field(changeset, :notify_whatsapp) != true ->
        changeset

      Ecto.Changeset.get_field(changeset, :whatsapp_consent) != true ->
        Ecto.Changeset.add_error(changeset, :whatsapp_consent, "agree to WhatsApp messages first")

      is_nil(user.mobile_number) ->
        Ecto.Changeset.add_error(
          changeset,
          :notify_whatsapp,
          "add a mobile number to your profile first"
        )

      true ->
        changeset
    end
  end

  @doc """
  Saves the scope's own notification preferences. Consent is stamped when
  it is first given and cleared when it is withdrawn. Audited as
  `membership.notifications_changed`.

  Returns `{:ok, membership}` or `{:error, changeset}`.
  """
  def update_notification_preferences(%Scope{membership: %Membership{}} = scope, attrs) do
    changeset = change_notification_preferences(scope, attrs)

    with {:ok, prefs} <- Ecto.Changeset.apply_action(changeset, :update) do
      account_id = Scope.account_id!(scope)

      membership =
        Repo.one!(
          from(m in Membership,
            where: m.id == ^scope.membership.id and m.customer_account_id == ^account_id
          )
        )

      consent_at =
        if prefs.whatsapp_consent, do: membership.whatsapp_consent_at || DateTime.utc_now(:second)

      update =
        Ecto.Changeset.change(membership,
          notify_email: prefs.notify_email,
          notify_whatsapp: prefs.notify_whatsapp,
          whatsapp_consent_at: consent_at
        )

      changes =
        for {field, old, new} <- [
              {"notify_email", membership.notify_email, prefs.notify_email},
              {"notify_whatsapp", membership.notify_whatsapp, prefs.notify_whatsapp},
              {"whatsapp_consent", not is_nil(membership.whatsapp_consent_at),
               prefs.whatsapp_consent}
            ],
            old != new,
            into: %{},
            do: {field, [old, new]}

      Multi.new()
      |> Multi.update(:membership, update)
      |> then(fn multi ->
        if changes == %{},
          do: multi,
          else:
            Audit.multi_log(multi, :audit, scope, "membership.notifications_changed", membership,
              changes: changes
            )
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{membership: updated}} ->
          {:ok, %{updated | customer_account: scope.customer_account}}
      end
    end
  end

  ## Members

  @doc """
  The number of active DueItems each member is responsible for or
  assigned to, keyed by user id.
  """
  def assigned_counts(%Scope{} = scope) do
    account_id = Scope.account_id!(scope)

    from(a in Assignment,
      join: i in assoc(a, :due_item),
      where: a.customer_account_id == ^account_id and is_nil(a.ended_at) and i.status == "active",
      group_by: a.user_id,
      select: {a.user_id, count(a.due_item_id, :distinct)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Deactivates a member. Their DueItem assignments either move to
  `reassign_to` (the user id of another active member) or end, leaving
  DueItems without a Primary Responsible in the Unassigned queue. They
  lose access on their next request and queued reminders to them are
  skipped. Super Admins deactivate Administrators and Users;
  Administrators deactivate Users.

  Returns `{:ok, %{membership: m, due_items: n}}` or `{:error, reason}`.
  """
  def deactivate_member(%Scope{} = scope, %Membership{} = membership, reassign_to \\ nil) do
    account_id = Scope.account_id!(scope)
    now = DateTime.utc_now(:second)

    with :ok <- authorize(Permissions.can_manage_member?(scope, membership)) do
      Multi.new()
      |> lock_account(account_id)
      |> Multi.run(:membership, fn repo, _ ->
        case lock_membership(repo, account_id, membership.id) do
          %Membership{status: "active", role: role} = m when role == membership.role -> {:ok, m}
          _ -> {:error, :not_active}
        end
      end)
      |> Multi.run(:target, fn repo, %{membership: m} -> reassign_target(repo, m, reassign_to) end)
      |> Multi.run(:reassigned, fn repo, %{membership: m, target: target} ->
        {:ok, reassign_items(repo, scope, m.user_id, target && target.user_id, now)}
      end)
      |> Multi.merge(fn %{reassigned: reassigned} ->
        Enum.reduce(reassigned, Multi.new(), fn {item, refs, changes}, multi ->
          multi
          |> Notifications.multi_notify({:notify, item.id}, "assignment", scope, fn _ ->
            {item, item.current_cycle_id, refs}
          end)
          |> Audit.multi_log({:audit, item.id}, scope, "due_item.assigned", item,
            changes: changes
          )
        end)
      end)
      |> Multi.update(:deactivated, fn %{membership: m} ->
        Ecto.Changeset.change(m, status: "deactivated", deactivated_at: now)
      end)
      |> Audit.multi_log(:audit, scope, "member.deactivated", & &1.membership,
        metadata: fn %{reassigned: reassigned, target: target} ->
          %{
            "role" => membership.role,
            "due_items" => length(reassigned),
            "reassigned_to" => target && target.user_id
          }
        end
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{deactivated: m, reassigned: reassigned}} ->
          {:ok, %{membership: m, due_items: length(reassigned)}}

        {:error, _step, reason, _} ->
          {:error, reason}
      end
    end
  end

  defp reassign_target(_repo, _membership, nil), do: {:ok, nil}

  defp reassign_target(repo, %Membership{} = membership, user_id) do
    from(m in Membership,
      where:
        m.customer_account_id == ^membership.customer_account_id and m.user_id == ^user_id and
          m.status == "active" and m.user_id != ^membership.user_id
    )
    |> repo.one()
    |> case do
      nil -> {:error, :invalid_target}
      target -> {:ok, target}
    end
  end

  # Moves `user_id`'s assignments on active DueItems to `target_id`, or
  # ends them when there is no target; ends them on archived DueItems.
  # Returns `[{item, [{assignment_id, user_id}], audit_changes}]` for the
  # active DueItems that changed.
  defp reassign_items(repo, scope, user_id, target_id, now) do
    account_id = Scope.account_id!(scope)

    items =
      from(i in DueItem,
        join: a in assoc(i, :active_assignments),
        where: i.customer_account_id == ^account_id and a.user_id == ^user_id,
        distinct: true,
        preload: [:active_assignments]
      )
      |> repo.all()

    {active, archived} = Enum.split_with(items, &(&1.status == "active"))

    for item <- archived, a <- item.active_assignments, a.user_id == user_id do
      repo.update_all(from(x in Assignment, where: x.id == ^a.id),
        set: [ended_at: now, updated_at: now]
      )
    end

    for item <- active do
      primary = Enum.find_value(item.active_assignments, &(&1.role == "primary" && &1.user_id))

      additional =
        for %Assignment{role: "additional", user_id: id} <- item.active_assignments, do: id

      {new_primary, new_additional} =
        cond do
          primary == user_id ->
            {target_id, additional -- [target_id]}

          is_nil(target_id) or target_id == primary or target_id in additional ->
            {primary, additional -- [user_id]}

          true ->
            {primary, (additional -- [user_id]) ++ [target_id]}
        end

      {to_end, new_rows, changes} = Steps.assignment_plan(item, new_primary, new_additional)

      repo.update_all(from(x in Assignment, where: x.id in ^to_end),
        set: [ended_at: now, updated_at: now]
      )

      {_, inserted} =
        repo.insert_all(
          Assignment,
          for({id, role} <- new_rows, do: Steps.assignment_row(scope, item, id, role, now)),
          returning: [:id, :user_id]
        )

      repo.update_all(from(i in DueItem, where: i.id == ^item.id), set: [updated_at: now])

      {item, Enum.map(inserted, &{&1.id, &1.user_id}), changes}
    end
  end

  @doc """
  Gives a deactivated member access again, if a seat is free.

  Returns `{:ok, membership}` or `{:error, reason}`.
  """
  def reactivate_member(%Scope{} = scope, %Membership{} = membership) do
    account_id = Scope.account_id!(scope)

    with :ok <- authorize(Permissions.can_manage_member?(scope, membership)) do
      Multi.new()
      |> lock_account(account_id)
      |> Multi.run(:membership, fn repo, _ ->
        case lock_membership(repo, account_id, membership.id) do
          %Membership{status: "deactivated"} = m -> {:ok, m}
          _ -> {:error, :not_deactivated}
        end
      end)
      |> Multi.run(:limit, fn _repo, _ ->
        with(:ok <- Billing.check(scope, :member), do: {:ok, :ok})
      end)
      |> Multi.update(:reactivated, fn %{membership: m} ->
        Ecto.Changeset.change(m, status: "active", deactivated_at: nil)
      end)
      |> Audit.multi_log(:audit, scope, "member.reactivated", & &1.membership,
        metadata: %{"role" => membership.role}
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{reactivated: m}} -> {:ok, m}
        {:error, _step, reason, _} -> {:error, reason}
      end
    end
  end

  @doc """
  Switches a member between Administrator and User. Super Admin only.
  The member is told by email.

  Returns `{:ok, membership}` or `{:error, reason}`.
  """
  def change_member_role(%Scope{} = scope, %Membership{} = membership, role)
      when role in ["admin", "user"] do
    account_id = Scope.account_id!(scope)

    with :ok <- authorize(Permissions.can_change_role?(scope, membership)) do
      Multi.new()
      |> lock_account(account_id)
      |> Multi.run(:membership, fn repo, _ ->
        case lock_membership(repo, account_id, membership.id) do
          %Membership{role: ^role} -> {:error, :unchanged}
          %Membership{role: current} = m when current in ["admin", "user"] -> {:ok, m}
          _ -> {:error, :unauthorized}
        end
      end)
      |> Multi.update(:updated, fn %{membership: m} -> Ecto.Changeset.change(m, role: role) end)
      |> Audit.multi_log(:audit, scope, "member.role_changed", & &1.membership,
        changes: fn %{membership: m} -> %{"role" => [m.role, role]} end
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{updated: m}} ->
          notify_role(scope, m)
          {:ok, m}

        {:error, _step, reason, _} ->
          {:error, reason}
      end
    end
  end

  ## Super Admins

  @doc "The account's active Super Admins with users, by name."
  def list_super_admins(%Scope{} = scope) do
    scope
    |> list_memberships()
    |> Enum.filter(&(&1.role == "super_admin" and &1.status == "active"))
  end

  @doc """
  Makes an active Administrator a Super Admin, within the plan's Super
  Admin limit. Super Admin only, after re-authentication.
  """
  def appoint_super_admin(%Scope{} = scope, %Membership{} = membership) do
    super_admin_change(scope, membership, "super_admin.appointed", fn _repo, m ->
      cond do
        m.role != "admin" -> {:error, :not_admin}
        true -> with :ok <- Billing.check(scope, :super_admin), do: {:ok, [{m, "super_admin"}]}
      end
    end)
  end

  @doc """
  Makes a Super Admin an Administrator again. The last Super Admin
  cannot be removed, and the new Administrator needs a free seat.
  """
  def remove_super_admin(%Scope{} = scope, %Membership{} = membership) do
    super_admin_change(scope, membership, "super_admin.removed", fn repo, m ->
      others =
        from(x in Membership,
          where:
            x.customer_account_id == ^m.customer_account_id and x.role == "super_admin" and
              x.status == "active" and x.id != ^m.id,
          select: count(x.id)
        )
        |> repo.one()

      cond do
        m.role != "super_admin" -> {:error, :not_super_admin}
        others == 0 -> {:error, :last_super_admin}
        true -> with :ok <- Billing.check(scope, :member), do: {:ok, [{m, "admin"}]}
      end
    end)
  end

  @doc """
  Hands the scope's Super Admin role to another active member, who
  becomes Super Admin while the scope becomes an Administrator.
  """
  def transfer_ownership(%Scope{} = scope, %Membership{} = membership) do
    super_admin_change(scope, membership, "super_admin.transferred", fn repo, m ->
      own = lock_membership(repo, m.customer_account_id, scope.membership.id)

      cond do
        m.role not in ["admin", "user"] -> {:error, :not_member}
        own.role != "super_admin" -> {:error, :unauthorized}
        true -> {:ok, [{m, "super_admin"}, {own, "admin"}]}
      end
    end)
  end

  # Runs a Super Admin change: `plan` gets the locked target membership
  # and returns the `[{membership, new_role}]` to apply.
  defp super_admin_change(scope, membership, action, plan) do
    account_id = Scope.account_id!(scope)

    with :ok <- authorize(Permissions.can_manage_super_admins?(scope)),
         :ok <- authorize(membership.customer_account_id == account_id),
         :ok <- reauthenticated(scope) do
      Multi.new()
      |> lock_account(account_id)
      |> Multi.run(:membership, fn repo, _ ->
        case lock_membership(repo, account_id, membership.id) do
          %Membership{status: "active"} = m -> {:ok, m}
          _ -> {:error, :not_active}
        end
      end)
      |> Multi.run(:plan, fn repo, %{membership: m} -> plan.(repo, m) end)
      |> Multi.run(:updated, fn repo, %{plan: changes} ->
        {:ok,
         for {m, role} <- changes do
           repo.update!(Ecto.Changeset.change(m, role: role))
         end}
      end)
      |> Audit.multi_log(:audit, scope, action, & &1.membership,
        changes: fn %{plan: changes} ->
          Map.new(changes, fn {m, role} -> {m.user_id, [m.role, role]} end)
        end
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{updated: updated}} ->
          updated
          |> Enum.reject(&(&1.user_id == scope.user.id))
          |> Enum.each(&notify_role(scope, &1))

          {:ok, updated}

        {:error, _step, reason, _} ->
          {:error, reason}
      end
    end
  end

  # Super Admin changes need a log-in within the last 10 minutes.
  defp reauthenticated(%Scope{user: user}) do
    if DueDesk.Accounts.sudo_mode?(user, -10), do: :ok, else: {:error, :reauthenticate}
  end

  defp notify_role(scope, %Membership{} = membership) do
    user = Repo.get!(User, membership.user_id)
    MemberNotifier.deliver_role_changed(user, scope.customer_account, membership.role, scope.user)
  end

  ## Invitations

  @doc """
  Invitations that are neither accepted nor revoked, newest first, with
  the inviter. Expired ones are included so they can be sent again.
  Administrators and Super Admins only; others get an empty list.
  """
  def list_open_invitations(%Scope{} = scope) do
    if Permissions.can_manage_users?(scope) do
      account_id = Scope.account_id!(scope)

      from(i in Invitation,
        where:
          i.customer_account_id == ^account_id and is_nil(i.accepted_at) and
            is_nil(i.revoked_at),
        order_by: [desc: i.inserted_at],
        preload: [:invited_by]
      )
      |> Repo.all()
    else
      []
    end
  end

  @doc "Gets an invitation of the scope's account. Raises if there is none."
  def get_invitation!(%Scope{} = scope, id) do
    account_id = Scope.account_id!(scope)
    Repo.one!(from(i in Invitation, where: i.id == ^id and i.customer_account_id == ^account_id))
  end

  @doc "Returns a changeset for the invite form."
  def change_invitation(attrs \\ %{}) do
    Invitation.changeset(%Invitation{role: "user"}, attrs)
  end

  @doc """
  Invites someone by email. A pending invitation to the same address is
  replaced, so only the newest link works. A new invitation takes a seat
  until it is accepted, revoked or expires. Super Admins invite
  Administrators and Users; Administrators invite Users.

  `url_fun` builds the accept link from the token; the token itself is
  only kept as a hash. Returns `{:ok, invitation}`, `{:error, changeset}`
  or `{:error, {:limit_reached, info}}`.
  """
  def invite_member(%Scope{} = scope, attrs, url_fun) when is_function(url_fun, 1) do
    changeset = change_invitation(attrs)
    role = Ecto.Changeset.get_field(changeset, :role)

    changeset =
      if role in Invitation.roles() and not Permissions.can_invite_role?(scope, role),
        do: Ecto.Changeset.add_error(changeset, :role, "choose a role you can invite"),
        else: changeset

    with :ok <- authorize(Permissions.can_manage_users?(scope)),
         {:ok, wanted} <- Ecto.Changeset.apply_action(changeset, :insert) do
      account_id = Scope.account_id!(scope)
      {token, hash} = new_token()
      now = DateTime.utc_now(:second)
      expires_at = DateTime.add(now, Invitation.validity_days(), :day)

      Multi.new()
      |> lock_account(account_id)
      |> Multi.run(:existing, fn repo, _ ->
        case member_by_email(repo, account_id, wanted.email) do
          %Membership{status: "active"} ->
            {:error, {:email, "is already a member of this account"}}

          %Membership{} ->
            {:error, {:email, "was deactivated. Reactivate them from the list instead"}}

          nil ->
            {:ok, pending_invitation(repo, account_id, wanted.email, now)}
        end
      end)
      |> Multi.run(:invitation, fn repo, %{existing: existing} ->
        fields = [
          role: wanted.role,
          token_hash: hash,
          expires_at: expires_at,
          invited_by_user_id: scope.user.id
        ]

        case existing do
          %Invitation{} = invitation ->
            repo.update(Ecto.Changeset.change(invitation, fields))

          nil ->
            with :ok <- Billing.check(scope, :member) do
              repo.insert(
                struct(
                  %Invitation{customer_account_id: account_id, email: wanted.email},
                  fields
                )
              )
            end
        end
      end)
      |> Audit.multi_log(:audit, scope, "invitation.created", & &1.invitation,
        metadata: fn %{existing: existing} ->
          %{"email" => wanted.email, "role" => wanted.role, "replaced" => not is_nil(existing)}
        end
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{invitation: invitation}} ->
          send_invitation(scope, invitation, token, url_fun)
          {:ok, invitation}

        {:error, :existing, {field, message}, _} ->
          {:error, %{Ecto.Changeset.add_error(changeset, field, message) | action: :insert}}

        {:error, _step, reason, _} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Sends an open invitation again with a new link and a fresh expiry; the
  old link stops working. An expired invitation needs a free seat.
  """
  def resend_invitation(%Scope{} = scope, %Invitation{} = invitation, url_fun)
      when is_function(url_fun, 1) do
    account_id = Scope.account_id!(scope)
    {token, hash} = new_token()
    now = DateTime.utc_now(:second)

    with :ok <- authorize(invitation.customer_account_id == account_id),
         :ok <- authorize(Permissions.can_invite_role?(scope, invitation.role)) do
      Multi.new()
      |> lock_account(account_id)
      |> Multi.run(:invitation, fn repo, _ ->
        invitation =
          repo.one(from(i in Invitation, where: i.id == ^invitation.id, lock: "FOR UPDATE"))

        case Invitation.state(invitation, now) do
          :pending -> {:ok, invitation}
          :expired -> with(:ok <- Billing.check(scope, :member), do: {:ok, invitation})
          _ -> {:error, :closed}
        end
      end)
      |> Multi.update(:updated, fn %{invitation: i} ->
        Ecto.Changeset.change(i,
          token_hash: hash,
          expires_at: DateTime.add(now, Invitation.validity_days(), :day),
          invited_by_user_id: scope.user.id
        )
      end)
      |> Audit.multi_log(:audit, scope, "invitation.resent", & &1.invitation,
        metadata: %{"email" => invitation.email, "role" => invitation.role}
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{updated: updated}} ->
          send_invitation(scope, updated, token, url_fun)
          {:ok, updated}

        {:error, _step, reason, _} ->
          {:error, reason}
      end
    end
  end

  @doc "Revokes an open invitation, so its link stops working and its seat is freed."
  def revoke_invitation(%Scope{} = scope, %Invitation{} = invitation) do
    account_id = Scope.account_id!(scope)

    with :ok <- authorize(invitation.customer_account_id == account_id),
         :ok <- authorize(Permissions.can_invite_role?(scope, invitation.role)),
         :ok <-
           if(invitation.accepted_at || invitation.revoked_at, do: {:error, :closed}, else: :ok) do
      Multi.new()
      |> Multi.update(
        :invitation,
        Ecto.Changeset.change(invitation, revoked_at: DateTime.utc_now(:second))
      )
      |> Audit.multi_log(:audit, scope, "invitation.revoked", invitation,
        metadata: %{"email" => invitation.email, "role" => invitation.role}
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{invitation: invitation}} -> {:ok, invitation}
        {:error, _step, reason, _} -> {:error, reason}
      end
    end
  end

  defp send_invitation(scope, invitation, token, url_fun) do
    MemberNotifier.deliver_invitation(
      invitation,
      scope.customer_account,
      scope.user,
      url_fun.(Base.url_encode64(token, padding: false))
    )
  end

  defp new_token do
    token = :crypto.strong_rand_bytes(32)
    {token, :crypto.hash(:sha256, token)}
  end

  defp token_hash(encoded) when is_binary(encoded) do
    case Base.url_decode64(encoded, padding: false) do
      {:ok, token} when byte_size(token) == 32 -> {:ok, :crypto.hash(:sha256, token)}
      _ -> :error
    end
  end

  defp member_by_email(repo, account_id, email) do
    from(m in Membership,
      join: u in assoc(m, :user),
      where: m.customer_account_id == ^account_id and u.email == ^email
    )
    |> repo.one()
  end

  defp pending_invitation(repo, account_id, email, now) do
    from(i in Invitation,
      where:
        i.customer_account_id == ^account_id and i.email == ^email and is_nil(i.accepted_at) and
          is_nil(i.revoked_at) and i.expires_at > ^now,
      order_by: [desc: i.inserted_at],
      limit: 1
    )
    |> repo.one()
  end

  ## Accepting invitations

  @doc """
  Finds the invitation for a link token, with its account and inviter,
  whatever its state. Returns nil for an unknown or malformed token.
  """
  def get_invitation_by_token(token) do
    with {:ok, hash} <- token_hash(token) do
      from(i in Invitation,
        where: i.token_hash == ^hash,
        preload: [:customer_account, :invited_by]
      )
      |> Repo.one()
    else
      _ -> nil
    end
  end

  @doc """
  Why an invitation cannot be accepted, or `:ok`: `:accepted`,
  `:revoked`, `:expired` or `:account_unavailable`.
  """
  def invitation_status(%Invitation{customer_account: account} = invitation) do
    case Invitation.state(invitation) do
      :pending -> if account.status == "active", do: :ok, else: {:error, :account_unavailable}
      state -> {:error, state}
    end
  end

  @doc "Returns a changeset for the sign-up form of an invitation."
  def change_invitation_registration(%Invitation{} = invitation, attrs \\ %{}) do
    User.registration_changeset(
      %User{},
      Map.put(attrs, "email", invitation.email),
      validate_unique: false,
      hash_password: false
    )
  end

  @doc """
  Creates the invited person's DueDesk login and accepts the invitation
  in one step. The email is confirmed already, because the link was sent
  to it. Returns `{:ok, user}`, `{:error, changeset}` or
  `{:error, reason}`.
  """
  def register_and_accept_invitation(token, attrs) do
    with {:ok, hash} <- token_hash(token) do
      Multi.new()
      |> Multi.run(:invitation, fn repo, _ -> lock_invitation(repo, hash) end)
      |> Multi.insert(:user, fn %{invitation: invitation} ->
        %User{}
        |> User.registration_changeset(Map.put(attrs, "email", invitation.email))
        |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now(:second))
      end)
      |> accept_steps()
      |> Repo.transaction()
      |> case do
        {:ok, %{user: user}} -> {:ok, user}
        {:error, _step, reason, _} -> {:error, reason}
      end
    else
      :error -> {:error, :invalid}
    end
  end

  @doc """
  Accepts an invitation for the signed-in user of `scope`, whose email
  must match. A user already working in another DueDesk account cannot
  join a second one in V1. Returns `{:ok, membership}` or
  `{:error, reason}`.
  """
  def accept_invitation(%Scope{user: %User{} = user}, token) do
    with {:ok, hash} <- token_hash(token) do
      Multi.new()
      |> Multi.run(:invitation, fn repo, _ -> lock_invitation(repo, hash) end)
      |> Multi.run(:user, fn _repo, %{invitation: invitation} ->
        if String.downcase(invitation.email) == String.downcase(user.email),
          do: {:ok, user},
          else: {:error, :wrong_email}
      end)
      |> accept_steps()
      |> Repo.transaction()
      |> case do
        {:ok, %{membership: membership}} -> {:ok, membership}
        {:error, _step, reason, _} -> {:error, reason}
      end
    else
      :error -> {:error, :invalid}
    end
  end

  defp lock_invitation(repo, hash) do
    from(i in Invitation,
      where: i.token_hash == ^hash,
      lock: "FOR UPDATE",
      preload: [:customer_account]
    )
    |> repo.one()
    |> case do
      nil ->
        {:error, :invalid}

      invitation ->
        with :ok <- invitation_status(invitation), do: {:ok, invitation}
    end
  end

  # Needs `:invitation` (locked, pending) and `:user` in the changes.
  defp accept_steps(multi) do
    now = DateTime.utc_now(:second)

    multi
    |> Multi.run(:lock, fn repo, %{invitation: invitation} ->
      from(a in CustomerAccount,
        where: a.id == ^invitation.customer_account_id,
        lock: "FOR UPDATE",
        select: a.id
      )
      |> repo.one()
      |> then(&{:ok, &1})
    end)
    |> Multi.run(:existing, fn repo, %{invitation: invitation, user: user} ->
      if get_current_membership(user) do
        {:error, :already_member}
      else
        {:ok,
         repo.get_by(Membership,
           customer_account_id: invitation.customer_account_id,
           user_id: user.id
         )}
      end
    end)
    |> Multi.update(:accepted, fn %{invitation: invitation} ->
      Ecto.Changeset.change(invitation, accepted_at: now)
    end)
    |> Multi.run(:limit, fn _repo, %{invitation: invitation} ->
      # The invitation's own seat was freed by accepting it.
      with :ok <- Billing.check(%Scope{customer_account: invitation.customer_account}, :member),
           do: {:ok, :ok}
    end)
    |> Multi.run(:membership, fn repo,
                                 %{invitation: invitation, user: user, existing: existing} ->
      case existing do
        %Membership{} = membership ->
          repo.update(
            Ecto.Changeset.change(membership,
              role: invitation.role,
              status: "active",
              deactivated_at: nil
            )
          )

        nil ->
          %Membership{customer_account_id: invitation.customer_account_id, user_id: user.id}
          |> Membership.changeset(%{role: invitation.role, status: "active"})
          |> repo.insert()
      end
    end)
    |> Multi.run(:audit, fn _repo, %{invitation: invitation, user: user, membership: m} ->
      Audit.log(Scope.for_user(user), "invitation.accepted", invitation,
        customer_account_id: invitation.customer_account_id,
        metadata: %{"role" => m.role, "membership_id" => m.id}
      )
    end)
  end

  defp lock_account(multi, account_id) do
    Multi.run(multi, :lock, fn repo, _ ->
      from(a in CustomerAccount, where: a.id == ^account_id, lock: "FOR UPDATE", select: a.id)
      |> repo.one()
      |> then(&{:ok, &1})
    end)
  end

  defp lock_membership(repo, account_id, id) do
    from(m in Membership,
      where: m.id == ^id and m.customer_account_id == ^account_id,
      lock: "FOR UPDATE"
    )
    |> repo.one()
  end

  defp authorize(true), do: :ok
  defp authorize(false), do: {:error, :unauthorized}

  ## Account helpers

  @doc """
  Today's date in the account's timezone. All due-date logic uses this,
  never the server's UTC date.
  """
  def today(%CustomerAccount{timezone: tz}) do
    tz |> DateTime.now!() |> DateTime.to_date()
  end

  def today(%Scope{customer_account: account}), do: today(account)
end

defmodule DueDesk.Tenancy do
  @moduledoc """
  Customer Accounts, memberships and invitations.

  All functions that read tenant data take a `DueDesk.Accounts.Scope` and
  filter by the scope's account. Nothing here ever looks up a record by id
  alone.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias DueDesk.{Audit, Categories, Repo}
  alias DueDesk.Accounts.{Scope, User}
  alias DueDesk.Tenancy.{CustomerAccount, Membership}

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

defmodule DueDesk.Notifications.Recipients do
  @moduledoc """
  Who receives a notification, and on which channels.

  Reminders go to the Primary Responsible and the Additional Assignees.
  Once a DueItem is overdue they are **escalated**: every Administrator
  and Super Admin receives them too. An unassigned DueItem has nobody to
  remind until it is overdue. Only active members receive anything, and
  each person is counted once.
  """

  import Ecto.Query, warn: false

  alias DueDesk.Repo
  alias DueDesk.DueItems.DueItem
  alias DueDesk.Notifications.WhatsApp
  alias DueDesk.Tenancy.Membership

  @doc """
  The account's active memberships with users preloaded, keyed by user
  id. Load once and pass to `resolve/3` and `channels/2`.
  """
  @spec members(Ecto.UUID.t()) :: %{Ecto.UUID.t() => Membership.t()}
  def members(account_id) do
    from(m in Membership,
      where: m.customer_account_id == ^account_id and m.status == "active",
      preload: [:user]
    )
    |> Repo.all()
    |> Map.new(&{&1.user_id, &1})
  end

  @doc """
  The user ids to remind about `item` (with active assignments
  preloaded), from the account's active `members`.
  """
  @spec resolve(DueItem.t(), boolean(), map()) :: [Ecto.UUID.t()]
  def resolve(%DueItem{active_assignments: assignments}, escalated?, members)
      when is_list(assignments) do
    # Primary first, so the list reads in order of responsibility.
    assignees =
      assignments
      |> Enum.sort_by(&if(&1.role == "primary", do: 0, else: 1))
      |> Enum.map(& &1.user_id)

    (assignees ++ if(escalated?, do: admins(members), else: []))
    |> Enum.uniq()
    |> Enum.filter(&Map.has_key?(members, &1))
  end

  @doc "User ids of the active Administrators and Super Admins in `members`."
  def admins(members) do
    for {user_id, %Membership{role: role}} <- members,
        role in ["admin", "super_admin"],
        do: user_id
  end

  @doc """
  The channels a member has turned on and that can reach them: Email,
  and WhatsApp when it is configured, consented to and the user has a
  mobile number.
  """
  @spec channels(Membership.t()) :: [String.t()]
  def channels(%Membership{} = membership) do
    email = if membership.notify_email, do: ["email"], else: []
    if whatsapp?(membership), do: email ++ ["whatsapp"], else: email
  end

  @doc "Whether WhatsApp reminders can reach this member."
  def whatsapp?(%Membership{} = m) do
    m.notify_whatsapp and not is_nil(m.whatsapp_consent_at) and
      is_binary(m.user.mobile_number) and WhatsApp.enabled?()
  end
end

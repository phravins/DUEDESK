defmodule DueDesk.Permissions do
  @moduledoc """
  The single place where DueDesk decides who may do what.

  Roles are account-level (Product Definition §5). Organisations never
  grant or restrict access. Every function takes a `DueDesk.Accounts.Scope`
  and is called from context functions, never only from the UI.

  DueItems follow one visibility rule (Product Definition §6):
  Administrators and Super Admins see every DueItem of the account; Users
  see only active DueItems they are assigned to. `DueDesk.DueItems.Queries`
  applies the same rule in SQL.
  """

  alias DueDesk.Accounts.Scope

  @doc "True when the scope belongs to an active Customer Account."
  def member?(%Scope{customer_account: %{status: "active"}, membership: %{status: "active"}}),
    do: true

  def member?(_), do: false

  @doc "Super Admin of the current account."
  def super_admin?(%Scope{role: :super_admin} = scope), do: member?(scope)
  def super_admin?(_), do: false

  @doc "Administrator or Super Admin: full operational control."
  def admin?(%Scope{role: role} = scope) when role in [:super_admin, :admin], do: member?(scope)
  def admin?(_), do: false

  # Account administration — Super Admin only.
  def can_manage_billing?(scope), do: super_admin?(scope)
  def can_manage_super_admins?(scope), do: super_admin?(scope)
  def can_close_account?(scope), do: super_admin?(scope)
  def can_export?(scope), do: super_admin?(scope)
  def can_edit_account_settings?(scope), do: super_admin?(scope)

  # Operational administration — Administrators and Super Admins.
  def can_manage_organisations?(scope), do: admin?(scope)
  def can_manage_categories?(scope), do: admin?(scope)
  def can_manage_users?(scope), do: admin?(scope)
  def can_view_all_due_items?(scope), do: admin?(scope)
  def can_view_audit_log?(scope), do: admin?(scope)

  # DueItems.

  @doc "Any active member may create a DueItem (Users only for themselves)."
  def can_create_due_item?(scope), do: member?(scope)

  @doc """
  Control of DueItems: Organisation, category, related party, dates after
  creation, recurrence, reminders, responsibility, status overrides,
  archive, restore, decisions on completed DueItems and renewal reviews.
  Administrators and Super Admins only.
  """
  def can_manage_due_items?(scope), do: admin?(scope)

  @doc """
  Whether the scope may see `item`. Needs the item's active assignments
  preloaded.
  """
  def can_view_due_item?(%Scope{} = scope, item) do
    cond do
      not member?(scope) -> false
      item.customer_account_id != scope.customer_account.id -> false
      can_view_all_due_items?(scope) -> true
      true -> assigned_active_item?(item, scope.user.id)
    end
  end

  def can_view_due_item?(_scope, _item), do: false

  @doc """
  Whether the scope may renew or complete `item`: anyone who can see it,
  while it is active and not waiting for an Administrator. Needs the
  item's active assignments preloaded.
  """
  def can_act_on_due_item?(scope, %{status: "active", disposition_state: nil} = item),
    do: can_view_due_item?(scope, item)

  def can_act_on_due_item?(_scope, _item), do: false

  @doc """
  Whether the scope may upload documents to `item`: the same rule as
  renewing or completing it. Archived DueItems are read-only.
  """
  def can_upload_document?(scope, item), do: can_act_on_due_item?(scope, item)

  @doc """
  Whether the scope may remove `document` from `item`: Administrators and
  Super Admins who can see the DueItem, or the person who uploaded it
  while its cycle is still open and they can act on the DueItem. Needs
  the document's cycle preloaded.
  """
  def can_delete_document?(scope, item, document) do
    cond do
      not can_view_due_item?(scope, item) -> false
      document.due_item_id != item.id -> false
      admin?(scope) -> true
      true -> uploader_of_open?(scope, item, document)
    end
  end

  defp uploader_of_open?(%Scope{user: user} = scope, item, document) do
    document.uploaded_by_user_id == user.id and is_nil(document.cycle.completed_at) and
      can_act_on_due_item?(scope, item)
  end

  @doc "Permanently deleting an archived DueItem. Super Admin only."
  def can_delete_due_item?(scope), do: super_admin?(scope)

  @doc "Anyone who can see a DueItem may add a note to it."
  def can_add_note?(scope, item), do: can_view_due_item?(scope, item)

  defp assigned_active_item?(%{status: "active", disposition_state: nil} = item, user_id) do
    Enum.any?(item.active_assignments, &(&1.user_id == user_id and is_nil(&1.ended_at)))
  end

  defp assigned_active_item?(_item, _user_id), do: false

  @doc """
  Super Admins may invite Administrators and Users; Administrators may
  invite Users only.
  """
  def can_invite_role?(scope, "admin"), do: super_admin?(scope)
  def can_invite_role?(scope, "user"), do: admin?(scope)
  def can_invite_role?(_scope, _role), do: false
end

defmodule DueDesk.Permissions do
  @moduledoc """
  The single place where DueDesk decides who may do what.

  Roles are account-level (Product Definition §5). Organisations never
  grant or restrict access. Every function takes a `DueDesk.Accounts.Scope`
  and is called from context functions, never only from the UI.

  DueItem-level checks (assignment-based visibility for Users) are added in
  Phase 2.
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

  @doc """
  Super Admins may invite Administrators and Users; Administrators may
  invite Users only.
  """
  def can_invite_role?(scope, "admin"), do: super_admin?(scope)
  def can_invite_role?(scope, "user"), do: admin?(scope)
  def can_invite_role?(_scope, _role), do: false
end

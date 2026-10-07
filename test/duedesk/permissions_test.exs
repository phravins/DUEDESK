defmodule DueDesk.PermissionsTest do
  use DueDesk.DataCase, async: true

  import DueDesk.AccountsFixtures
  import DueDesk.TenancyFixtures

  alias DueDesk.Permissions
  alias DueDesk.Accounts.Scope

  setup do
    super_admin = account_scope_fixture()

    %{
      super_admin: super_admin,
      admin: member_scope_fixture(super_admin, "admin"),
      user: member_scope_fixture(super_admin, "user")
    }
  end

  @super_admin_only [
    :can_manage_billing?,
    :can_manage_super_admins?,
    :can_close_account?,
    :can_export?,
    :can_edit_account_settings?
  ]

  @admin [
    :can_manage_organisations?,
    :can_manage_categories?,
    :can_manage_users?,
    :can_view_all_due_items?,
    :can_view_audit_log?
  ]

  test "Super Admin can do everything", %{super_admin: s} do
    for check <- @super_admin_only ++ @admin,
        do: assert(apply(Permissions, check, [s]), "#{check}")

    assert Permissions.can_invite_role?(s, "admin")
    assert Permissions.can_invite_role?(s, "user")
  end

  test "Administrator has operational control only", %{admin: a} do
    for check <- @admin, do: assert(apply(Permissions, check, [a]), "#{check}")
    for check <- @super_admin_only, do: refute(apply(Permissions, check, [a]), "#{check}")
    refute Permissions.can_invite_role?(a, "admin")
    assert Permissions.can_invite_role?(a, "user")
  end

  test "User has no administrative permissions", %{user: u} do
    for check <- @super_admin_only ++ @admin,
        do: refute(apply(Permissions, check, [u]), "#{check}")

    refute Permissions.can_invite_role?(u, "user")
    assert Permissions.member?(u)
  end

  test "nobody may invite a Super Admin", %{super_admin: s} do
    refute Permissions.can_invite_role?(s, "super_admin")
  end

  test "suspended accounts and deactivated memberships lose all permissions", %{
    super_admin: s,
    admin: a
  } do
    suspended = %{s | customer_account: %{s.customer_account | status: "suspended"}}
    refute Permissions.super_admin?(suspended)
    refute Permissions.admin?(suspended)

    deactivated = %{a | membership: %{a.membership | status: "deactivated"}}
    refute Permissions.admin?(deactivated)
    refute Permissions.member?(deactivated)
  end

  test "a scope without an account has no permissions" do
    scope = Scope.for_user(user_fixture())
    refute Permissions.member?(scope)
    refute Permissions.admin?(scope)
    refute Permissions.can_manage_users?(scope)
    refute Permissions.admin?(nil)
  end
end

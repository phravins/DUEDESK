defmodule DueDeskWeb.AccountLive.SuperAdminsTest do
  use DueDeskWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DueDesk.TenancyFixtures

  alias DueDesk.Tenancy

  defp recent_log_in(conn, user),
    do: log_in_user(conn, user, token_authenticated_at: DateTime.utc_now(:second))

  defp stale_log_in(conn, user),
    do:
      log_in_user(conn, user,
        token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -20, :minute)
      )

  test "asks for the password again after 10 minutes", %{conn: conn} do
    owner = account_scope_fixture()

    assert {:error, {:redirect, %{to: to}}} =
             live(stale_log_in(conn, owner.user), ~p"/account/super-admins")

    assert to == "/users/confirm-access?to=%2Faccount%2Fsuper-admins"

    conn = get(stale_log_in(build_conn(), owner.user), to)
    assert redirected_to(conn) == ~p"/users/log-in"
    assert get_session(conn, :user_return_to) == "/account/super-admins"
  end

  test "confirm-access only returns to known pages", %{conn: conn} do
    owner = account_scope_fixture()
    conn = get(recent_log_in(conn, owner.user), ~p"/users/confirm-access?to=https://evil.example")
    assert redirected_to(conn) == ~p"/dashboard"
  end

  test "Administrators can't open the page", %{conn: conn} do
    owner = account_scope_fixture()
    admin = member_scope_fixture(owner, "admin")

    assert {:error, {:live_redirect, %{to: "/dashboard"}}} =
             live(recent_log_in(conn, admin.user), ~p"/account/super-admins")
  end

  test "on a single Super Admin plan, ownership is transferred", %{conn: conn} do
    owner = account_scope_fixture() |> put_plan("business")
    admin = member_scope_fixture(owner, "admin")

    conn = recent_log_in(conn, owner.user)
    {:ok, lv, _html} = live(conn, ~p"/account/super-admins")
    assert has_element?(lv, "#super_admins-#{owner.membership.id}")
    refute has_element?(lv, "#appoint")

    assert {:ok, _lv, _html} =
             lv
             |> form("#transfer-form", transfer: %{membership_id: admin.membership.id})
             |> render_submit()
             |> follow_redirect(conn, ~p"/users")

    assert Tenancy.get_current_membership(admin.user).role == "super_admin"
    assert Tenancy.get_current_membership(owner.user).role == "admin"
  end

  test "on a multi Super Admin plan, Administrators are appointed and removed", %{conn: conn} do
    owner = account_scope_fixture() |> put_plan("entrepreneur")
    admin = member_scope_fixture(owner, "admin")

    {:ok, lv, _html} = live(recent_log_in(conn, owner.user), ~p"/account/super-admins")
    refute has_element?(lv, "#transfer")
    refute has_element?(lv, "#remove-super-admin-#{owner.membership.id}")

    lv
    |> form("#appoint-form", appoint: %{membership_id: admin.membership.id})
    |> render_submit()

    assert has_element?(lv, "#super_admins-#{admin.membership.id}")
    assert has_element?(lv, "#appoint-none")

    lv |> element("#remove-super-admin-#{admin.membership.id}") |> render_click()
    refute has_element?(lv, "#super_admins-#{admin.membership.id}")
    assert Tenancy.get_current_membership(admin.user).role == "admin"
  end
end

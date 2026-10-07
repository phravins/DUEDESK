defmodule DueDeskWeb.OnboardingLiveTest do
  use DueDeskWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DueDesk.AccountsFixtures
  import DueDesk.TenancyFixtures

  alias DueDesk.Tenancy

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  test "the dashboard sends users without an account to account setup", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/onboarding/account"}}} = live(conn, ~p"/dashboard")
  end

  test "prefills the mobile number from sign up", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/onboarding/account")
    assert html =~ "Set up your DueDesk account"
    assert html =~ "+919876543210"
  end

  test "creates the account and lands on the dashboard as Super Admin", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/onboarding/account")

    # /dashboard lives in a different live_session, so this is a full redirect.
    {:ok, conn} =
      lv
      |> form("#account_setup_form",
        account: %{name: "Sharma Group", notification_mobile: "98765 43210"}
      )
      |> render_submit()
      |> follow_redirect(conn, ~p"/dashboard")

    html = html_response(conn, 200)
    assert html =~ "Your DueDesk account is ready."
    assert html =~ "Sharma Group"
    assert html =~ "Super Admin"

    membership = Tenancy.get_current_membership(user)
    assert membership.role == "super_admin"
    assert membership.customer_account.name == "Sharma Group"
  end

  test "shows validation errors", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/onboarding/account")

    html =
      lv
      |> form("#account_setup_form", account: %{name: "", notification_mobile: "12"})
      |> render_submit()

    assert html =~ "enter your account name"
    assert html =~ "must be a 10-digit Indian mobile number"
  end

  test "users who already have an account cannot set up another", %{conn: conn} do
    scope = account_scope_fixture()
    conn = log_in_user(conn, scope.user)
    assert {:error, {:redirect, %{to: "/dashboard"}}} = live(conn, ~p"/onboarding/account")
  end
end

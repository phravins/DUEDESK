defmodule DueDeskWeb.OnboardingLiveTest do
  use DueDeskWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DueDesk.AccountsFixtures
  import DueDesk.TenancyFixtures
  import DueDesk.OrganisationsFixtures

  alias DueDesk.{Organisations, Tenancy}

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

  test "creates the account and moves on to the first Organisation", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/onboarding/account")

    # Step 4 lives in the account live_session, so this is a full redirect.
    {:ok, conn} =
      lv
      |> form("#account_setup_form",
        account: %{name: "Sharma Group", notification_mobile: "98765 43210"}
      )
      |> render_submit()
      |> follow_redirect(conn, ~p"/onboarding/organisation")

    assert html_response(conn, 200) =~ "Your DueDesk account is ready."

    membership = Tenancy.get_current_membership(user)
    assert membership.role == "super_admin"
    assert membership.customer_account.name == "Sharma Group"

    {:ok, step4, _html} = live(conn, ~p"/onboarding/organisation")
    assert has_element?(step4, "#onboarding_organisation_form")
    assert has_element?(step4, ~s|#skip-organisation[href="/dashboard"]|)
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

  describe "first Organisation" do
    setup %{conn: conn} do
      scope = account_scope_fixture()
      %{conn: log_in_user(conn, scope.user), scope: scope}
    end

    test "adds the Organisation and lands on the dashboard", %{conn: conn, scope: scope} do
      {:ok, lv, _html} = live(conn, ~p"/onboarding/organisation")

      {:ok, dashboard, _html} =
        lv
        |> form("#onboarding_organisation_form",
          organisation: %{
            name: "Sharma Traders",
            type: "proprietorship",
            identifier: unique_udyam(),
            declaration_accepted: "true"
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/dashboard")

      assert render(dashboard) =~ "Organisation added. Next, create your first DueItem."
      assert [%{name: "Sharma Traders"}] = Organisations.list_organisations(scope)
    end

    test "is skipped once an Organisation exists", %{conn: conn, scope: scope} do
      organisation_fixture(scope)

      assert {:error, {:live_redirect, %{to: "/dashboard"}}} =
               live(conn, ~p"/onboarding/organisation")
    end

    test "is skipped for Users", %{conn: conn, scope: scope} do
      user_scope = member_scope_fixture(scope, "user")
      conn = log_in_user(conn, user_scope.user)

      assert {:error, {:live_redirect, %{to: "/dashboard"}}} =
               live(conn, ~p"/onboarding/organisation")
    end
  end
end

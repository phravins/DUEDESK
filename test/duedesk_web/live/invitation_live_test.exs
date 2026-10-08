defmodule DueDeskWeb.InvitationLiveTest do
  use DueDeskWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DueDesk.AccountsFixtures
  import DueDesk.TenancyFixtures

  alias DueDesk.{Repo, Tenancy}

  setup do
    owner = account_scope_fixture() |> put_plan("business")
    {invitation, token} = invitation_fixture(owner, %{"email" => "neha@example.com"})
    %{owner: owner, invitation: invitation, token: token}
  end

  describe "logged out" do
    test "someone new signs up with the invited email", %{conn: conn, token: token} = ctx do
      {:ok, lv, _html} = live(conn, ~p"/invitations/#{token}")

      assert has_element?(lv, "#invitation-register", ctx.owner.customer_account.name)
      assert has_element?(lv, "#invitation-form input[readonly][value='neha@example.com']")

      assert lv |> form("#invitation-form", user: %{password: "short"}) |> render_change() =~
               "should be at least"

      {:ok, _lv, html} =
        lv
        |> form("#invitation-form",
          user: %{name: "Neha Rao", mobile_number: "98765 43211", password: "a long password"}
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "Log in to get started"
      assert html =~ "neha@example.com"

      user = DueDesk.Accounts.get_user_by_email("neha@example.com")
      assert user.confirmed_at

      assert Tenancy.get_current_membership(user).customer_account_id ==
               ctx.owner.customer_account.id
    end

    test "someone with a login is sent to log in and back", %{conn: conn, token: token} do
      user_fixture(email: "neha@example.com")
      {:ok, lv, _html} = live(conn, ~p"/invitations/#{token}")

      assert has_element?(lv, "#invitation-log-in")
      assert has_element?(lv, "#log-in-to-accept[href='/invitations/#{token}/log-in']")

      conn = get(conn, ~p"/invitations/#{token}/log-in")
      assert redirected_to(conn) == ~p"/users/log-in"
      assert get_session(conn, :user_return_to) == "/invitations/#{token}"
      assert Phoenix.Flash.get(conn.assigns.flash, :email) == "neha@example.com"
    end

    test "the log-in shortcut ignores bad tokens", %{conn: conn} do
      conn = get(conn, ~p"/invitations/nope/log-in")
      assert redirected_to(conn) == ~p"/invitations/nope"
      refute get_session(conn, :user_return_to)
    end

    test "a bad link reveals nothing", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/invitations/nope")
      assert has_element?(lv, "#invitation-invalid")
      refute html =~ "Acme"
    end

    test "closed invitations say why", %{conn: conn, owner: owner, invitation: invitation} do
      {expired, expired_token} = invitation_fixture(owner, %{"email" => "late@example.com"})

      expired
      |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(:second), -60))
      |> Repo.update!()

      {:ok, lv, _} = live(conn, ~p"/invitations/#{expired_token}")
      assert has_element?(lv, "#invitation-expired")

      {revoked, revoked_token} = invitation_fixture(owner, %{"email" => "gone@example.com"})
      {:ok, _} = Tenancy.revoke_invitation(owner, revoked)
      {:ok, lv, _} = live(conn, ~p"/invitations/#{revoked_token}")
      assert has_element?(lv, "#invitation-revoked")

      {_, used_token} = invitation_fixture(owner, %{"email" => invitation.email})

      {:ok, _} =
        Tenancy.register_and_accept_invitation(used_token, %{
          "name" => "Neha Rao",
          "mobile_number" => "98765 43211",
          "password" => "a long password"
        })

      {:ok, lv, _} = live(conn, ~p"/invitations/#{used_token}")
      assert has_element?(lv, "#invitation-accepted")
    end
  end

  describe "logged in" do
    test "the invited person accepts", %{conn: conn, token: token} = ctx do
      user = user_fixture(email: "neha@example.com")
      {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/invitations/#{token}")

      assert {:ok, _lv, html} =
               lv
               |> element("#accept-invitation")
               |> render_click()
               |> follow_redirect(log_in_user(build_conn(), user), ~p"/dashboard")

      assert html =~ "Welcome to #{ctx.owner.customer_account.name}"
      assert Tenancy.get_current_membership(user).role == "user"
    end

    test "someone else is asked to log out", %{conn: conn, token: token} do
      {:ok, lv, _html} = live(log_in_user(conn, user_fixture()), ~p"/invitations/#{token}")
      assert has_element?(lv, "#invitation-wrong-email")
      refute has_element?(lv, "#accept-invitation")
    end

    test "a member of another account can't join", %{conn: conn, token: token} do
      other = account_scope_fixture(user_fixture(email: "neha@example.com"))
      {:ok, lv, _html} = live(log_in_user(conn, other.user), ~p"/invitations/#{token}")
      assert has_element?(lv, "#invitation-already-member")
    end

    test "accepting with no free seat explains it", %{conn: conn, owner: owner, token: token} do
      # The invitation holds one of the 5 seats; members added outside the
      # invitation flow overfill the plan.
      for _ <- 1..5, do: member_scope_fixture(owner, "user")
      user = user_fixture(email: "neha@example.com")
      {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/invitations/#{token}")

      assert lv |> element("#accept-invitation") |> render_click() =~ "has no free seats"
      refute Tenancy.get_current_membership(user)
    end
  end
end

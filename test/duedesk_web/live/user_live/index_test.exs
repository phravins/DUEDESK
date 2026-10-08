defmodule DueDeskWeb.UserLive.IndexTest do
  use DueDeskWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DueDesk.TenancyFixtures
  import DueDesk.DueItemsFixtures

  alias DueDesk.{DueItems, Tenancy}
  alias DueDesk.DueItems.DueItem

  describe "as Super Admin" do
    setup :register_and_log_in_super_admin

    test "lists members, the seat meter and the invite form", %{conn: conn, scope: scope} do
      member = member_scope_fixture(scope, "user")
      {invitation, _} = invitation_fixture(scope, %{"email" => "pending@example.com"})

      {:ok, lv, _html} = live(conn, ~p"/users")

      assert has_element?(lv, "#members-#{scope.membership.id}")
      assert has_element?(lv, "#members-#{member.membership.id}")
      assert has_element?(lv, "#member-assigned-#{member.membership.id}", "0")
      assert has_element?(lv, "#seats", "2 of 2 User seats used")
      assert has_element?(lv, "#invitations-#{invitation.id}", "pending@example.com")
      assert has_element?(lv, "#super-admins-link")

      # Both seats are taken, so the form makes way for the limit notice.
      assert has_element?(lv, "#invite-blocked")
      refute has_element?(lv, "#invite-form")
    end

    test "invites an Administrator", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users")

      assert has_element?(lv, "#invite-form option[value=admin]")
      assert has_element?(lv, "#invitations-empty")

      lv
      |> form("#invite-form", invitation: %{email: "neha@example.com", role: "admin"})
      |> render_submit()

      [invitation] = Tenancy.list_open_invitations(scope_of(lv))
      assert invitation.role == "admin"
      assert has_element?(lv, "#invitations-#{invitation.id}", "neha@example.com")
      assert has_element?(lv, "#seats", "1 of 2 User seats used")
    end

    test "shows invite errors on the form", %{conn: conn, scope: scope} do
      member = member_scope_fixture(scope, "user")
      {:ok, lv, _html} = live(conn, ~p"/users")

      html =
        lv
        |> form("#invite-form", invitation: %{email: member.user.email, role: "user"})
        |> render_submit()

      assert html =~ "is already a member of this account"
      assert Tenancy.list_open_invitations(scope) == []
    end

    test "resends and revokes invitations", %{conn: conn, scope: scope} do
      {invitation, token} = invitation_fixture(scope)
      {:ok, lv, _html} = live(conn, ~p"/users")

      lv |> element("#resend-#{invitation.id}") |> render_click()
      assert Tenancy.get_invitation_by_token(token) == nil
      assert Tenancy.get_invitation!(scope, invitation.id).token_hash != invitation.token_hash

      lv |> element("#revoke-#{invitation.id}") |> render_click()
      refute has_element?(lv, "#invitations-#{invitation.id}")
      assert has_element?(lv, "#invitations-empty")
      assert has_element?(lv, "#seats", "0 of 2 User seats used")
    end

    test "changes a User into an Administrator", %{conn: conn, scope: scope} do
      member = member_scope_fixture(scope, "user")
      {:ok, lv, _html} = live(conn, ~p"/users")

      refute has_element?(lv, "#change-role-#{scope.membership.id}")
      lv |> element("#change-role-#{member.membership.id}") |> render_click()

      assert Tenancy.get_membership!(scope, member.membership.id).role == "admin"
      assert has_element?(lv, "#members-#{member.membership.id}", "Administrator")
    end

    test "deactivating without DueItems asks for a plain confirmation", %{
      conn: conn,
      scope: scope
    } do
      member = member_scope_fixture(scope, "user")
      {:ok, lv, _html} = live(conn, ~p"/users")

      lv |> element("#deactivate-#{member.membership.id}") |> render_click()
      assert has_element?(lv, "#deactivate-count", "0 assigned DueItems")
      refute has_element?(lv, "#deactivate-form")

      lv |> element("#deactivate-confirm") |> render_click()
      refute has_element?(lv, "#deactivate-modal")
      assert has_element?(lv, "#reactivate-#{member.membership.id}")
      assert has_element?(lv, "#seats", "0 of 2 User seats used")

      lv |> element("#reactivate-#{member.membership.id}") |> render_click()
      assert has_element?(lv, "#deactivate-#{member.membership.id}")
    end

    test "Leave Unassigned ends the assignments", %{conn: conn, scope: scope} do
      member = member_scope_fixture(scope, "user")
      item = due_item_fixture(scope, %{"primary_user_id" => member.user.id})
      {:ok, lv, _html} = live(conn, ~p"/users")

      lv |> element("#deactivate-#{member.membership.id}") |> render_click()
      assert has_element?(lv, "#deactivate-count", "1 assigned DueItem")

      lv |> element("#deactivate-unassigned") |> render_click()

      assert DueItem.primary_user(reload(scope, item)) == nil
      assert has_element?(lv, "#reactivate-#{member.membership.id}")
    end
  end

  describe "Journey 6: an Administrator reassigns a leaving User's work" do
    setup %{conn: conn} do
      owner = account_scope_fixture() |> put_plan("business")
      admin = member_scope_fixture(owner, "admin")
      leaver = member_scope_fixture(owner, "user")
      taker = member_scope_fixture(owner, "user")

      items =
        for _ <- 1..3, do: due_item_fixture(owner, %{"primary_user_id" => leaver.user.id})

      %{
        conn: log_in_user(conn, admin.user),
        owner: owner,
        leaver: leaver,
        taker: taker,
        items: items
      }
    end

    test "Reassign Now moves the DueItems and the leaver loses access", ctx do
      leaver_conn = log_in_user(build_conn(), ctx.leaver.user)
      assert {:ok, _lv, _html} = live(leaver_conn, ~p"/dashboard")

      {:ok, lv, _html} = live(ctx.conn, ~p"/users")
      assert has_element?(lv, "#member-assigned-#{ctx.leaver.membership.id}", "3")

      # Administrators can't change roles or touch the Super Admin.
      refute has_element?(lv, "#change-role-#{ctx.leaver.membership.id}")
      refute has_element?(lv, "#deactivate-#{ctx.owner.membership.id}")
      refute has_element?(lv, "#super-admins-link")

      lv |> element("#deactivate-#{ctx.leaver.membership.id}") |> render_click()
      assert has_element?(lv, "#deactivate-count", "3 assigned DueItems")

      # Submitting without a choice asks for one.
      html = lv |> form("#deactivate-form") |> render_submit()
      assert html =~ "choose who takes over"
      assert Tenancy.get_current_membership(ctx.leaver.user)

      lv
      |> form("#deactivate-form", deactivate: %{reassign_to: ctx.taker.user.id})
      |> render_submit()

      refute has_element?(lv, "#deactivate-modal")
      assert has_element?(lv, "#member-assigned-#{ctx.taker.membership.id}", "3")
      assert has_element?(lv, "#reactivate-#{ctx.leaver.membership.id}")

      for item <- ctx.items do
        assert DueItem.primary_user(reload(ctx.owner, item)).id == ctx.taker.user.id
      end

      taker_items = DueItems.list_due_items(ctx.taker, %{})
      assert length(taker_items) == 3

      assert {:error, {:redirect, %{to: "/onboarding/account"}}} =
               live(leaver_conn, ~p"/dashboard")
    end
  end

  describe "as User" do
    setup :register_and_log_in_account_user

    test "cannot open the page", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/dashboard"}}} = live(conn, ~p"/users")
    end
  end

  defp scope_of(lv), do: :sys.get_state(lv.pid).socket.assigns.current_scope
end

defmodule DueDeskWeb.DashboardLiveTest do
  use DueDeskWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DueDesk.TenancyFixtures
  import DueDesk.DueItemsFixtures

  alias DueDesk.DueItems

  @admin_sections ["Organisations", "Users", "Categories", "Account"]

  describe "as Super Admin" do
    setup :register_and_log_in_super_admin

    test "shows account-wide cards, admin navigation and capacity", %{
      conn: conn,
      account: account
    } do
      {:ok, lv, html} = live(conn, ~p"/dashboard")

      assert html =~ account.name
      assert html =~ "Super Admin"
      assert has_element?(lv, "#card-overdue", "Overdue")
      assert has_element?(lv, "#card-unassigned")
      assert has_element?(lv, "#capacity", "Free plan")
      assert has_element?(lv, "#capacity", "100 MB")
      for section <- @admin_sections, do: assert(html =~ section)
    end

    test "shows the welcome card until the first DueItem", %{conn: conn, scope: scope} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard")
      assert has_element?(lv, "#welcome")
      refute has_element?(lv, "#list-overdue")

      due_item_fixture(scope)
      {:ok, lv, _html} = live(conn, ~p"/dashboard")
      refute has_element?(lv, "#welcome")
    end

    test "counts and lists DueItems that need attention", %{conn: conn, scope: scope} do
      member = member_scope_fixture(scope, "user")

      overdue =
        due_item_fixture(scope,
          title: "GST return",
          due_date: days_from_today(scope, -2),
          primary_user_id: member.user.id
        )

      soon = due_item_fixture(scope, title: "Fire NOC", due_date: days_from_today(scope, 7))
      _later = due_item_fixture(scope, due_date: days_from_today(scope, 200))
      archived = due_item_fixture(scope, due_date: days_from_today(scope, -9))
      {:ok, _} = DueItems.archive_due_item(scope, archived)

      {:ok, lv, _html} = live(conn, ~p"/dashboard")

      assert has_element?(lv, "#card-overdue", "1")
      assert has_element?(lv, "#card-due-soon", "1")
      assert has_element?(lv, "#card-unassigned", "2")
      assert has_element?(lv, "#card-up-to-date", "1")

      assert has_element?(lv, "#list-overdue #overdue-#{overdue.id}", "GST return")
      assert has_element?(lv, "#list-due_soon #due_soon-#{soon.id}", "Fire NOC")
      assert has_element?(lv, "#list-unassigned #unassigned-#{soon.id}")
      refute has_element?(lv, "#overdue-#{archived.id}")

      organisation = organisation_for(scope)
      assert has_element?(lv, "#by-organisation-#{organisation.id}", "1 overdue")
      assert has_element?(lv, "#by-person-#{member.user.id}", member.user.name)
      assert has_element?(lv, "#capacity", "3 of 10")
    end

    test "shows the queues waiting for an Administrator and recent completions", %{
      conn: conn,
      scope: scope
    } do
      member = member_scope_fixture(scope, "user")
      one_off = due_item_fixture(scope, title: "Pest control", primary_user_id: member.user.id)
      yearly = due_item_fixture(scope, recurrence: "annual", primary_user_id: member.user.id)

      {:ok, lv, _html} = live(conn, ~p"/dashboard")
      assert has_element?(lv, "#card-awaiting", "0")
      assert has_element?(lv, "#card-reviews", "0")
      refute has_element?(lv, "#recently-completed")

      {:ok, _} = DueItems.complete_due_item(member, one_off, %{})
      {:ok, _} = DueItems.renew_due_item(member, yearly, %{})

      {:ok, lv, _html} = live(conn, ~p"/dashboard")
      assert has_element?(lv, ~s|#card-awaiting a[href="/due-items?view=awaiting"]|, "1")
      assert has_element?(lv, ~s|#card-reviews a[href="/due-items?view=reviews"]|, "1")
      assert has_element?(lv, "#completed-#{one_off.current_cycle.id}", "Pest control")
      assert has_element?(lv, "#completed-#{yearly.current_cycle.id}")
      # The completed one-off no longer appears among the active DueItems.
      refute has_element?(lv, "#unassigned-#{one_off.id}")
    end

    test "status cards link to the filtered DueItems list", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard")
      assert has_element?(lv, ~s|#card-overdue[href="/due-items?status=overdue"]|)
      assert has_element?(lv, ~s|#card-unassigned[href="/due-items?assignment=unassigned"]|)
    end
  end

  describe "as Administrator" do
    setup :register_and_log_in_admin

    test "sees admin navigation but not capacity", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/dashboard")

      assert html =~ "Administrator"
      assert has_element?(lv, "#card-unassigned")
      refute has_element?(lv, "#capacity")
      for section <- @admin_sections, do: assert(html =~ section)
    end
  end

  describe "as User" do
    setup :register_and_log_in_account_user

    test "sees only their own work", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/dashboard")

      assert html =~ "My DueItems"
      assert has_element?(lv, "#card-overdue", "My Overdue")
      refute has_element?(lv, "#card-unassigned")
      refute has_element?(lv, "#capacity")
      refute has_element?(lv, ~s|a[href="/organisations"]|)
      refute has_element?(lv, ~s|a[href="/users"]|)
    end

    test "counts and lists only their own DueItems", %{conn: conn, scope: scope} do
      admin = member_scope_fixture(scope, "admin")
      other = member_scope_fixture(scope, "user")

      mine =
        due_item_fixture(admin,
          title: "My GST return",
          due_date: days_from_today(scope, -2),
          primary_user_id: scope.user.id
        )

      not_mine =
        due_item_fixture(admin,
          due_date: days_from_today(scope, -2),
          primary_user_id: other.user.id
        )

      _unassigned = due_item_fixture(admin, due_date: days_from_today(scope, -2))

      {:ok, lv, _html} = live(conn, ~p"/dashboard")

      assert has_element?(lv, "#card-overdue", "1")
      assert has_element?(lv, "#list-overdue #overdue-#{mine.id}", "My GST return")
      refute has_element?(lv, "#overdue-#{not_mine.id}")
      assert has_element?(lv, "#recently-updated #recent-#{mine.id}")
      refute has_element?(lv, "#list-unassigned")
      refute has_element?(lv, "#by-organisation")
      refute has_element?(lv, "#by-person")
      refute has_element?(lv, "#welcome")
      refute has_element?(lv, "#admin-queues")
    end

    test "sees their own recent renewals", %{conn: conn, scope: scope} do
      admin = member_scope_fixture(scope, "admin")
      item = due_item_fixture(admin, recurrence: "annual", primary_user_id: scope.user.id)
      {:ok, _} = DueItems.renew_due_item(scope, item, %{})

      other = member_scope_fixture(scope, "user")
      theirs = due_item_fixture(admin, recurrence: "annual", primary_user_id: other.user.id)
      {:ok, _} = DueItems.renew_due_item(other, theirs, %{})

      {:ok, lv, _html} = live(conn, ~p"/dashboard")
      assert has_element?(lv, "#completed-#{item.current_cycle.id}")
      refute has_element?(lv, "#completed-#{theirs.current_cycle.id}")
    end

    test "sees the welcome card with nothing assigned", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard")
      assert has_element?(lv, "#welcome")
    end

    test "cannot open admin-only sections", %{conn: conn} do
      for path <- ["/organisations", "/users", "/categories", "/account"] do
        assert {:error, {:live_redirect, %{to: "/dashboard", flash: flash}}} = live(conn, path)
        assert flash["error"] =~ "not available to your account access"
      end
    end

    test "can open sections available to every role", %{conn: conn} do
      assert {:ok, _lv, _html} = live(conn, ~p"/support")
      assert {:ok, _lv, _html} = live(conn, ~p"/due-items")
    end
  end

  test "signed-out visitors are sent to log in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/dashboard")
  end
end

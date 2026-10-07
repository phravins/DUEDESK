defmodule DueDeskWeb.DashboardLiveTest do
  use DueDeskWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

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

defmodule DueDeskWeb.AccountLive.PlansTest do
  use DueDeskWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DueDesk.OrganisationsFixtures

  describe "as Super Admin" do
    setup :register_and_log_in_super_admin

    test "marks the current plan and shows usage", %{conn: conn, scope: scope} do
      organisation_fixture(scope)
      {:ok, lv, _html} = live(conn, ~p"/account/plans")

      assert has_element?(lv, "#plan-free #current-plan")
      refute has_element?(lv, "#plan-business #current-plan")
      assert has_element?(lv, "#plan-entrepreneur")
      assert has_element?(lv, "#plan-usage", "Organisations")
    end
  end

  describe "as User" do
    setup :register_and_log_in_account_user

    test "cannot open the plans", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/dashboard"}}} = live(conn, ~p"/account/plans")
    end
  end
end

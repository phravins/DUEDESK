defmodule DueDeskWeb.DueItemLive.CompleteTest do
  use DueDeskWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DueDesk.TenancyFixtures
  import DueDesk.DueItemsFixtures

  alias DueDesk.DueItems
  alias DueDesk.DueItems.DueItem

  describe "Journey 4" do
    setup :register_and_log_in_account_user

    test "a User completes; an Administrator re-dates and reactivates for someone else", %{
      conn: conn,
      scope: scope
    } do
      admin = member_scope_fixture(scope, "admin")
      colleague = member_scope_fixture(scope, "user")

      item =
        due_item_fixture(admin,
          title: "Pest control contract",
          due_date: days_from_today(scope, 3),
          primary_user_id: scope.user.id
        )

      # The User completes it and it leaves their list.
      {:ok, show, _html} = live(conn, ~p"/due-items/#{item}")
      refute has_element?(show, "#renew-due-item")

      {:ok, lv, _html} =
        show
        |> element("#complete-due-item")
        |> render_click()
        |> follow_redirect(conn, ~p"/due-items/#{item}/complete")

      assert has_element?(lv, "#complete-notice", "An Administrator")

      {:ok, list, _html} =
        lv
        |> form("#complete-form", %{"completion" => %{"note" => "Contract signed"}})
        |> render_submit()
        |> follow_redirect(conn, ~p"/due-items")

      assert has_element?(list, "#flash-info", "DueItem completed.")
      refute has_element?(list, "#due_items-#{item.id}")

      # The Administrator finds it under Awaiting action.
      admin_conn = log_in_user(build_conn(), admin.user)
      {:ok, queue, _html} = live(admin_conn, ~p"/due-items?view=awaiting")
      assert has_element?(queue, "#tab-awaiting", "1")
      assert has_element?(queue, "#due_items-#{item.id}", "Awaiting action")

      {:ok, detail, _html} = live(admin_conn, ~p"/due-items/#{item}")
      assert has_element?(detail, "#awaiting-banner", "Completed on")
      assert has_element?(detail, "#cycles", "Contract signed")

      {:ok, form, _html} =
        detail
        |> element("#reactivate-due-item")
        |> render_click()
        |> follow_redirect(admin_conn, ~p"/due-items/#{item}/reactivate")

      new_due = days_from_today(scope, 365)

      {:ok, detail, _html} =
        form
        |> form("#reactivate-form", %{
          "due_item" => %{"due_date" => new_due, "primary_user_id" => colleague.user.id}
        })
        |> render_submit()
        |> follow_redirect(admin_conn, ~p"/due-items/#{item}")

      assert has_element?(detail, "#flash-info", "DueItem reactivated.")
      assert has_element?(detail, "#primary-responsible", colleague.user.name)
      refute has_element?(detail, "#awaiting-banner")
      assert has_element?(detail, "#history", "re-dated and reactivated this DueItem")

      reactivated = reload(admin, item)
      assert reactivated.current_cycle.sequence == 2
      assert DueItem.primary_user(reactivated).id == colleague.user.id

      # The colleague sees it now; the User who completed it does not.
      assert {:ok, _} = DueItems.get_due_item(colleague, item.id)
      assert {:error, :not_found} = DueItems.get_due_item(scope, item.id)
    end

    test "a recurring DueItem goes to Renew", %{conn: conn, scope: scope} do
      admin = member_scope_fixture(scope, "admin")
      item = due_item_fixture(admin, recurrence: "annual", primary_user_id: scope.user.id)
      path = ~p"/due-items/#{item}/renew"

      assert {:error, {:live_redirect, %{to: ^path}}} =
               live(conn, ~p"/due-items/#{item}/complete")
    end

    test "a completed DueItem cannot be completed again", %{conn: conn, scope: scope} do
      admin = member_scope_fixture(scope, "admin")
      item = due_item_fixture(admin, primary_user_id: scope.user.id)
      {:ok, _} = DueItems.complete_due_item(scope, item, %{})

      assert {:error, {:live_redirect, %{to: "/due-items"}}} =
               live(conn, ~p"/due-items/#{item}/complete")
    end
  end

  describe "as Super Admin" do
    setup :register_and_log_in_super_admin

    test "completes and returns to the DueItem to decide", %{conn: conn, scope: scope} do
      item = due_item_fixture(scope)
      {:ok, lv, _html} = live(conn, ~p"/due-items/#{item}/complete")

      {:ok, show, _html} =
        lv
        |> form("#complete-form", %{"completion" => %{"note" => ""}})
        |> render_submit()
        |> follow_redirect(conn, ~p"/due-items/#{item}")

      assert has_element?(show, "#flash-info", "DueItem completed.")
      assert has_element?(show, "#awaiting-banner")

      show |> element("#archive-awaiting") |> render_click()
      assert has_element?(show, "#archived-banner")
      assert reload(scope, item).status == "archived"
    end
  end
end

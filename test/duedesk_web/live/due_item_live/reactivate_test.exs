defmodule DueDeskWeb.DueItemLive.ReactivateTest do
  use DueDeskWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DueDesk.TenancyFixtures
  import DueDesk.DueItemsFixtures

  alias DueDesk.DueItems

  @not_available "This DueItem is not available to your account access."

  defp assert_not_available(conn, path) do
    assert {:error, {:live_redirect, %{to: "/due-items", flash: flash}}} = live(conn, path)
    assert flash["error"] == @not_available
  end

  describe "as Super Admin" do
    setup :register_and_log_in_super_admin

    test "restores an archived DueItem after reviewing it", %{conn: conn, scope: scope} do
      member = member_scope_fixture(scope, "user")
      item = due_item_fixture(scope, title: "Fire NOC", reminder_offsets: ["-30", "0"])
      {:ok, _} = DueItems.archive_due_item(scope, item)

      {:ok, lv, _html} = live(conn, ~p"/due-items/#{item}/reactivate")

      assert has_element?(lv, "h1", "Restore DueItem")
      assert has_element?(lv, "#reactivate-notice")
      assert has_element?(lv, "#section-dates")
      assert has_element?(lv, "#section-responsibility")
      assert has_element?(lv, "#section-reminders")
      # The open cycle's Due Date is filled in.
      assert has_element?(
               lv,
               ~s|#reactivate-form input[name="due_item[due_date]"][value="#{item.current_cycle.due_date}"]|
             )

      lv
      |> form("#reactivate-form", %{"due_item" => %{"due_date" => "", "expiry_date" => ""}})
      |> render_submit()

      assert has_element?(lv, "#reactivate-form", "enter a Due Date or an Expiry Date")
      assert reload(scope, item).status == "archived"

      new_due = days_from_today(scope, 45)

      {:ok, show, _html} =
        lv
        |> form("#reactivate-form", %{
          "due_item" => %{
            "due_date" => new_due,
            "expiry_date" => "",
            "primary_user_id" => member.user.id
          }
        })
        |> render_submit()
        |> follow_redirect(conn, ~p"/due-items/#{item}")

      assert has_element?(show, "#flash-info", "DueItem restored.")
      assert has_element?(show, "#archive-due-item")
      refute has_element?(show, "#archived-banner")
      assert has_element?(show, "#primary-responsible", member.user.name)
      assert has_element?(show, "#history", "restored this DueItem")

      restored = reload(scope, item)
      assert restored.status == "active"
      assert restored.current_cycle.due_date == Date.from_iso8601!(new_due)
    end

    test "at the plan limit, shows the limit notice instead of the form", %{
      conn: conn,
      scope: scope
    } do
      archived = due_item_fixture(scope)
      {:ok, _} = DueItems.archive_due_item(scope, archived)
      for _ <- 1..10, do: due_item_fixture(scope)

      {:ok, lv, _html} = live(conn, ~p"/due-items/#{archived}/reactivate")

      assert has_element?(lv, "#limit-notice")
      refute has_element?(lv, "#reactivate-form")
      assert reload(scope, archived).status == "archived"
    end

    test "sets new dates for a renewal that had none", %{conn: conn, scope: scope} do
      item = due_item_fixture(scope, recurrence: "custom", recurrence_unit: "explicit")
      {:ok, _} = DueItems.renew_due_item(scope, item, %{})

      {:ok, lv, _html} = live(conn, ~p"/due-items/#{item}/reactivate")
      assert has_element?(lv, "h1", "Set new dates")
      assert has_element?(lv, "#save-reactivation", "Save and reactivate")
      # The closed cycle's dates are not offered again.
      refute has_element?(
               lv,
               ~s|#reactivate-form input[name="due_item[due_date]"][value="#{item.current_cycle.due_date}"]|
             )

      {:ok, show, _html} =
        lv
        |> form("#reactivate-form", %{"due_item" => %{"due_date" => days_from_today(scope, 400)}})
        |> render_submit()
        |> follow_redirect(conn, ~p"/due-items/#{item}")

      assert has_element?(show, "#flash-info", "DueItem reactivated.")
      assert reload(scope, item).disposition_state == nil
    end

    test "an active DueItem has nothing to reactivate", %{conn: conn, scope: scope} do
      assert_not_available(conn, ~p"/due-items/#{due_item_fixture(scope)}/reactivate")
    end
  end

  describe "as User" do
    setup :register_and_log_in_account_user

    test "cannot reactivate or restore", %{conn: conn, scope: scope} do
      admin = member_scope_fixture(scope, "admin")
      item = due_item_fixture(admin, primary_user_id: scope.user.id)
      {:ok, _} = DueItems.complete_due_item(scope, item, %{})

      assert_not_available(conn, ~p"/due-items/#{item}/reactivate")

      archived = due_item_fixture(admin, primary_user_id: scope.user.id)
      {:ok, _} = DueItems.archive_due_item(admin, archived)
      assert_not_available(conn, ~p"/due-items/#{archived}/reactivate")
    end
  end
end

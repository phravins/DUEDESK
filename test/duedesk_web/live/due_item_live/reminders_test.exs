defmodule DueDeskWeb.DueItemLive.RemindersTest do
  use DueDeskWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DueDesk.TenancyFixtures
  import DueDesk.DueItemsFixtures

  alias DueDesk.{Notifications, Tenancy}

  defp item_with_reminders(admin, user) do
    item =
      due_item_fixture(admin,
        due_date: days_from_today(admin, 10),
        reminder_offsets: ["-7", "0"],
        primary_user_id: user.user.id
      )

    {:ok, _} =
      Notifications.queue_reminders(admin.customer_account, Date.add(Tenancy.today(admin), 3))

    item
  end

  describe "as Administrator" do
    setup :register_and_log_in_admin

    test "shows the next reminder and the reminder log", %{conn: conn, scope: scope} do
      user = member_scope_fixture(scope, "user")
      item = item_with_reminders(scope, user)
      [latest | _] = Notifications.list_deliveries(scope, item)

      {:ok, lv, _html} = live(conn, ~p"/due-items/#{item}")

      assert has_element?(lv, "#next-reminder", "7 days before")
      assert has_element?(lv, "#reminder-log")
      assert has_element?(lv, "#delivery-#{latest.id}", user.user.name)
      assert has_element?(lv, "#delivery-#{latest.id}", "Queued")
    end

    test "an empty log says nothing was sent", %{conn: conn, scope: scope} do
      item = due_item_fixture(scope, due_date: days_from_today(scope, 200))
      {:ok, lv, _html} = live(conn, ~p"/due-items/#{item}")

      assert has_element?(lv, "#reminder-log", "Nothing sent yet.")
    end
  end

  describe "as User" do
    setup :register_and_log_in_account_user

    test "shows the next reminder but not the log", %{conn: conn, scope: scope} do
      admin = member_scope_fixture(scope, "admin")
      item = item_with_reminders(admin, scope)

      {:ok, lv, _html} = live(conn, ~p"/due-items/#{item}")

      assert has_element?(lv, "#next-reminder", "7 days before")
      refute has_element?(lv, "#reminder-log")
    end
  end
end

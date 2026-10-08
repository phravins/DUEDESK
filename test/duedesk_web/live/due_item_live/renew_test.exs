defmodule DueDeskWeb.DueItemLive.RenewTest do
  use DueDeskWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DueDesk.TenancyFixtures
  import DueDesk.DueItemsFixtures

  alias DueDesk.DueItems
  alias DueDeskWeb.Format

  @not_available "This DueItem is not available to your account access."

  describe "as User (Journey 2)" do
    setup :register_and_log_in_account_user

    setup %{scope: scope} do
      %{admin: member_scope_fixture(scope, "admin")}
    end

    test "renews without documents and sees the next cycle", %{
      conn: conn,
      scope: scope,
      admin: admin
    } do
      due = scope |> DueDesk.Tenancy.today() |> Date.add(5)
      next_due = Date.shift(due, month: 1)

      item =
        due_item_fixture(admin,
          title: "GSTR-3B",
          recurrence: "monthly",
          due_date: Date.to_iso8601(due),
          primary_user_id: scope.user.id
        )

      {:ok, show, _html} = live(conn, ~p"/due-items/#{item}")

      {:ok, lv, _html} =
        show
        |> element("#renew-due-item")
        |> render_click()
        |> follow_redirect(conn, ~p"/due-items/#{item}/renew")

      assert has_element?(lv, "#current-cycle", Format.date(due))
      assert has_element?(lv, "#next-dates", Format.date(next_due))
      refute has_element?(lv, "#renew-form input[name='completion[next_due_date]']")

      {:ok, show, _html} =
        lv
        |> form("#renew-form", %{"completion" => %{"note" => "Filed, ARN AA270125"}})
        |> render_submit()
        |> follow_redirect(conn, ~p"/due-items/#{item}")

      assert has_element?(show, "#flash-info", "The next cycle has been created.")
      assert has_element?(show, "#due-item-due-date", Format.date(next_due))
      assert has_element?(show, "#cycles #cycle-#{item.current_cycle.id}", "Filed, ARN AA270125")
      assert has_element?(show, "#renew-due-item")
      assert DueItems.count_renewal_reviews(admin) == 1
    end

    test "the date it was done cannot be in the future", %{
      conn: conn,
      scope: scope,
      admin: admin
    } do
      item = due_item_fixture(admin, recurrence: "annual", primary_user_id: scope.user.id)
      {:ok, lv, _html} = live(conn, ~p"/due-items/#{item}/renew")

      lv
      |> form("#renew-form", %{"completion" => %{"completed_on" => days_from_today(scope, 2)}})
      |> render_submit()

      assert has_element?(lv, "#renew-form", "cannot be in the future")
      assert reload(admin, item).current_cycle.completed_at == nil
    end

    test "renewing without the next date leaves it for an Administrator", %{
      conn: conn,
      scope: scope,
      admin: admin
    } do
      item =
        due_item_fixture(admin,
          recurrence: "custom",
          recurrence_unit: "explicit",
          primary_user_id: scope.user.id
        )

      {:ok, lv, _html} = live(conn, ~p"/due-items/#{item}/renew")
      assert has_element?(lv, "#renew-form input[name='completion[next_due_date]']")
      refute has_element?(lv, "#next-dates")

      {:ok, list, _html} =
        lv
        |> form("#renew-form", %{"completion" => %{"next_due_date" => ""}})
        |> render_submit()
        |> follow_redirect(conn, ~p"/due-items")

      assert has_element?(list, "#flash-info", "An Administrator will set the next dates.")
      refute has_element?(list, "#due_items-#{item.id}")
      assert reload(admin, item).disposition_state == "awaiting_new_dates"
    end

    test "cannot renew a DueItem assigned to someone else", %{
      conn: conn,
      scope: scope,
      admin: admin
    } do
      other = member_scope_fixture(scope, "user")
      item = due_item_fixture(admin, recurrence: "annual", primary_user_id: other.user.id)

      assert {:error, {:live_redirect, %{to: "/due-items", flash: flash}}} =
               live(conn, ~p"/due-items/#{item}/renew")

      assert flash["error"] == @not_available
    end

    test "a DueItem that does not repeat goes to Mark as completed", %{
      conn: conn,
      scope: scope,
      admin: admin
    } do
      item = due_item_fixture(admin, primary_user_id: scope.user.id)
      path = ~p"/due-items/#{item}/complete"

      assert {:error, {:live_redirect, %{to: ^path}}} = live(conn, ~p"/due-items/#{item}/renew")
    end
  end

  describe "as Super Admin" do
    setup :register_and_log_in_super_admin

    test "enters the next dates when they are set at each renewal", %{conn: conn, scope: scope} do
      item =
        due_item_fixture(scope,
          recurrence: "custom",
          recurrence_unit: "explicit",
          due_date: days_from_today(scope, 10)
        )

      {:ok, lv, _html} = live(conn, ~p"/due-items/#{item}/renew")
      next_due = days_from_today(scope, 100)

      {:ok, show, _html} =
        lv
        |> form("#renew-form", %{"completion" => %{"next_due_date" => next_due}})
        |> render_submit()
        |> follow_redirect(conn, ~p"/due-items/#{item}")

      assert has_element?(show, "#due-item-due-date", Format.date(Date.from_iso8601!(next_due)))
      refute has_element?(show, "#awaiting-banner")
    end

    test "without next dates, goes to the DueItem to set them", %{conn: conn, scope: scope} do
      item = due_item_fixture(scope, recurrence: "custom", recurrence_unit: "explicit")
      {:ok, lv, _html} = live(conn, ~p"/due-items/#{item}/renew")

      {:ok, show, _html} =
        lv
        |> form("#renew-form", %{"completion" => %{"note" => ""}})
        |> render_submit()
        |> follow_redirect(conn, ~p"/due-items/#{item}")

      assert has_element?(show, "#flash-info", "Set the next dates")
      assert has_element?(show, "#awaiting-banner")
      assert has_element?(show, "#due-item-status", "Needs new dates")
      assert has_element?(show, "#reactivate-due-item", "Set new dates")
    end

    test "a second submit after the DueItem moved on is refused", %{conn: conn, scope: scope} do
      item = due_item_fixture(scope, recurrence: "annual")
      {:ok, lv, _html} = live(conn, ~p"/due-items/#{item}/renew")

      {:ok, _} = DueItems.renew_due_item(scope, item, %{})

      {:ok, show, _html} =
        lv
        |> form("#renew-form", %{"completion" => %{"note" => ""}})
        |> render_submit()
        |> follow_redirect(conn, ~p"/due-items/#{item}")

      assert has_element?(show, "#flash-error", "already been updated")
      assert length(DueItems.list_cycles(scope, item)) == 1
    end
  end
end

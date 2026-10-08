defmodule DueDeskWeb.DueItemLive.IndexTest do
  use DueDeskWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DueDesk.TenancyFixtures
  import DueDesk.OrganisationsFixtures
  import DueDesk.DueItemsFixtures

  alias DueDesk.DueItems

  defp row(item), do: "#due_items-#{item.id}"

  describe "as Super Admin" do
    setup :register_and_log_in_super_admin

    test "lists active DueItems with the admin tabs", %{conn: conn, scope: scope} do
      item = due_item_fixture(scope, title: "Trade Licence renewal")

      {:ok, lv, _html} = live(conn, ~p"/due-items")

      assert has_element?(lv, "h1", "DueItems")
      assert has_element?(lv, "#new-due-item")
      assert has_element?(lv, "#tab-active")
      assert has_element?(lv, "#tab-unassigned")
      assert has_element?(lv, "#tab-archived")
      assert has_element?(lv, row(item), "Trade Licence renewal")
      refute has_element?(lv, "#due-items-empty")
    end

    test "shows an empty state with no DueItems", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/due-items")
      assert has_element?(lv, "#due-items-empty")
    end

    test "searches by title and reference number", %{conn: conn, scope: scope} do
      licence = due_item_fixture(scope, title: "Trade Licence renewal")
      insurance = due_item_fixture(scope, title: "Fire insurance", reference_number: "POL-77")

      {:ok, lv, _html} = live(conn, ~p"/due-items")

      lv |> form("#due-item-filters", %{"q" => "licence"}) |> render_change()
      assert_patch(lv, ~p"/due-items?q=licence")
      assert has_element?(lv, row(licence))
      refute has_element?(lv, row(insurance))

      lv |> form("#due-item-filters", %{"q" => "pol-77"}) |> render_change()
      assert has_element?(lv, row(insurance))
      refute has_element?(lv, row(licence))

      lv |> element("#clear-filters") |> render_click()
      assert_patch(lv, ~p"/due-items")
      assert has_element?(lv, row(licence))
      assert has_element?(lv, row(insurance))
    end

    test "the sidebar search link opens the list filtered", %{conn: conn, scope: scope} do
      licence = due_item_fixture(scope, title: "Trade Licence renewal")
      other = due_item_fixture(scope, title: "Fire insurance")

      {:ok, lv, _html} = live(conn, ~p"/due-items?q=Trade")
      assert has_element?(lv, row(licence))
      refute has_element?(lv, row(other))
    end

    test "filters by status from a dashboard link", %{conn: conn, scope: scope} do
      overdue = due_item_fixture(scope, due_date: days_from_today(scope, -3))
      soon = due_item_fixture(scope, due_date: days_from_today(scope, 5))
      later = due_item_fixture(scope, due_date: days_from_today(scope, 200))

      {:ok, lv, _html} = live(conn, ~p"/due-items?status=overdue")
      assert has_element?(lv, row(overdue))
      refute has_element?(lv, row(soon))
      refute has_element?(lv, row(later))

      lv |> form("#due-item-filters", %{"status" => "due_soon"}) |> render_change()
      assert has_element?(lv, row(soon))
      refute has_element?(lv, row(overdue))
    end

    test "filters by Primary Responsible", %{conn: conn, scope: scope} do
      member = member_scope_fixture(scope, "user")
      mine = due_item_fixture(scope, primary_user_id: member.user.id)
      other = due_item_fixture(scope)

      {:ok, lv, _html} = live(conn, ~p"/due-items?primary_user_id=#{member.user.id}")
      assert has_element?(lv, row(mine))
      refute has_element?(lv, row(other))
    end

    test "the Unassigned and Archived tabs", %{conn: conn, scope: scope} do
      member = member_scope_fixture(scope, "user")
      assigned = due_item_fixture(scope, primary_user_id: member.user.id)
      unassigned = due_item_fixture(scope)
      archived = due_item_fixture(scope, primary_user_id: member.user.id)
      {:ok, _} = DueItems.archive_due_item(scope, archived)

      {:ok, lv, _html} = live(conn, ~p"/due-items")
      assert has_element?(lv, row(assigned))
      assert has_element?(lv, row(unassigned))
      refute has_element?(lv, row(archived))
      assert has_element?(lv, "#tab-unassigned", "1")

      lv |> element("#tab-unassigned") |> render_click()
      assert_patch(lv, ~p"/due-items?assignment=unassigned")
      assert has_element?(lv, row(unassigned))
      refute has_element?(lv, row(assigned))

      lv |> element("#tab-archived") |> render_click()
      assert_patch(lv, ~p"/due-items?view=archived")
      assert has_element?(lv, row(archived))
      refute has_element?(lv, row(assigned))
      refute has_element?(lv, row(unassigned))
    end

    test "the Awaiting action tab", %{conn: conn, scope: scope} do
      waiting = due_item_fixture(scope, title: "Pest control")
      active = due_item_fixture(scope)
      {:ok, _} = DueItems.complete_due_item(scope, waiting, %{})

      {:ok, lv, _html} = live(conn, ~p"/due-items")
      refute has_element?(lv, row(waiting))
      assert has_element?(lv, "#tab-awaiting", "1")

      lv |> element("#tab-awaiting") |> render_click()
      assert_patch(lv, ~p"/due-items?view=awaiting")
      assert has_element?(lv, row(waiting), "Awaiting action")
      refute has_element?(lv, row(active))
    end

    test "the Renewal reviews tab lists Users' renewals until dismissed", %{
      conn: conn,
      scope: scope
    } do
      member = member_scope_fixture(scope, "user")

      item =
        due_item_fixture(scope,
          title: "Shop licence",
          recurrence: "annual",
          primary_user_id: member.user.id
        )

      {:ok, _} = DueItems.renew_due_item(member, item, %{})
      cycle_id = item.current_cycle.id

      {:ok, lv, _html} = live(conn, ~p"/due-items")
      assert has_element?(lv, "#tab-reviews", "1")

      lv |> element("#tab-reviews") |> render_click()
      assert_patch(lv, ~p"/due-items?view=reviews")

      assert has_element?(lv, "#renewal_reviews-#{cycle_id}", "Shop licence")
      assert has_element?(lv, "#renewal_reviews-#{cycle_id}", member.user.name)
      assert has_element?(lv, "#review-#{cycle_id}")
      assert has_element?(lv, "#edit-dates-#{cycle_id}")
      refute has_element?(lv, "#due-item-filters")

      lv |> element("#dismiss-#{cycle_id}") |> render_click()

      refute has_element?(lv, "#renewal_reviews-#{cycle_id}")
      assert has_element?(lv, "#renewal-reviews-empty")
      assert DueItems.count_renewal_reviews(scope) == 0
    end

    test "loads more past the first page", %{conn: conn, scope: scope} do
      scope = put_plan(scope, "entrepreneur")
      organisation = organisation_fixture(scope)

      items =
        for _ <- 1..(DueItems.per_page() + 1),
            do: due_item_fixture(scope, organisation_id: organisation.id)

      {:ok, lv, _html} = live(conn, ~p"/due-items")
      assert has_element?(lv, "#load-more")

      lv |> element("#load-more") |> render_click()
      refute has_element?(lv, "#load-more")
      for item <- items, do: assert(has_element?(lv, row(item)))
    end

    test "does not list another account's DueItems", %{conn: conn} do
      other = account_scope_fixture()
      item = due_item_fixture(other, title: "Someone else's licence")

      {:ok, lv, html} = live(conn, ~p"/due-items")
      refute has_element?(lv, row(item))
      refute html =~ "Someone else"
    end
  end

  describe "as User" do
    setup :register_and_log_in_account_user

    test "sees only DueItems assigned to them, without admin tabs", %{conn: conn, scope: scope} do
      admin = member_scope_fixture(scope, "admin")
      other_user = member_scope_fixture(scope, "user")

      primary = due_item_fixture(admin, primary_user_id: scope.user.id)

      additional =
        due_item_fixture(admin,
          primary_user_id: other_user.user.id,
          additional_user_ids: [scope.user.id]
        )

      not_mine = due_item_fixture(admin, primary_user_id: other_user.user.id)
      unassigned = due_item_fixture(admin)
      archived = due_item_fixture(admin, primary_user_id: scope.user.id)
      {:ok, _} = DueItems.archive_due_item(admin, archived)

      {:ok, lv, _html} = live(conn, ~p"/due-items")

      assert has_element?(lv, "h1", "My DueItems")
      refute has_element?(lv, "#due-item-tabs")
      assert has_element?(lv, row(primary))
      assert has_element?(lv, row(additional))
      refute has_element?(lv, row(not_mine))
      refute has_element?(lv, row(unassigned))
      refute has_element?(lv, row(archived))
    end

    test "cannot reach other DueItems through the query string", %{conn: conn, scope: scope} do
      admin = member_scope_fixture(scope, "admin")
      archived = due_item_fixture(admin, primary_user_id: scope.user.id)
      {:ok, _} = DueItems.archive_due_item(admin, archived)
      unassigned = due_item_fixture(admin)

      {:ok, lv, _html} = live(conn, ~p"/due-items?view=archived")
      refute has_element?(lv, row(archived))

      {:ok, lv, _html} = live(conn, ~p"/due-items?assignment=unassigned")
      refute has_element?(lv, row(unassigned))

      completed = due_item_fixture(admin, primary_user_id: scope.user.id)
      {:ok, _} = DueItems.complete_due_item(scope, completed, %{})

      {:ok, lv, _html} = live(conn, ~p"/due-items?view=awaiting")
      refute has_element?(lv, row(completed))

      renewed = due_item_fixture(admin, recurrence: "annual", primary_user_id: scope.user.id)
      {:ok, _} = DueItems.renew_due_item(scope, renewed, %{})

      {:ok, lv, _html} = live(conn, ~p"/due-items?view=reviews")
      refute has_element?(lv, "#renewal-reviews")
      assert has_element?(lv, row(renewed))
    end
  end
end

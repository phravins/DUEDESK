defmodule DueDeskWeb.DueItemLive.FormTest do
  use DueDeskWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DueDesk.TenancyFixtures
  import DueDesk.DueItemsFixtures

  alias DueDesk.DueItems
  alias DueDesk.DueItems.DueItem

  defp find_item(scope, title) do
    [item] = DueItems.list_due_items(%{scope | role: :super_admin}, %{"q" => title})
    reload(scope, item)
  end

  defp offsets(item), do: item.reminder_rules |> Enum.map(& &1.offset_days) |> Enum.sort()

  describe "as Super Admin" do
    setup :register_and_log_in_super_admin

    test "shows every section", %{conn: conn, scope: scope} do
      organisation_for(scope)
      {:ok, lv, _html} = live(conn, ~p"/due-items/new")

      for section <- ~w(basic dates responsibility recurrence reminders),
          do: assert(has_element?(lv, "#section-#{section}"))

      refute has_element?(lv, "#user-create-note")

      for offset <- [-90, -30, -7, 0, 1],
          do: assert(has_element?(lv, "#reminder-#{offset}[checked]"))
    end

    test "creates a DueItem with responsibility, recurrence and reminders", %{
      conn: conn,
      scope: scope
    } do
      organisation = organisation_for(scope)
      category = category_for(scope)
      primary = member_scope_fixture(scope, "user")
      additional = member_scope_fixture(scope, "admin")

      {:ok, lv, _html} = live(conn, ~p"/due-items/new")

      lv
      |> form("#due-item-form", %{
        "due_item" => %{
          "due_date" => days_from_today(scope, 60),
          "expiry_date" => days_from_today(scope, 75),
          "primary_user_id" => primary.user.id
        }
      })
      |> render_change()

      assert has_element?(lv, "#dates-hint")
      assert has_element?(lv, "#additional-#{additional.user.id}")
      refute has_element?(lv, "#additional-#{primary.user.id}")

      lv
      |> form("#due-item-form", %{"custom_reminder" => %{"days" => "14", "direction" => "before"}})
      |> render_change()

      lv |> element("#add-reminder") |> render_click()
      assert has_element?(lv, "#reminder--14[checked]")

      {:ok, _show, html} =
        lv
        |> form("#due-item-form", %{
          "due_item" => %{
            "title" => "Fire safety NOC",
            "organisation_id" => organisation.id,
            "category_id" => category.id,
            "related_party" => "Fire Department",
            "due_date" => days_from_today(scope, 60),
            "expiry_date" => days_from_today(scope, 75),
            "primary_user_id" => primary.user.id,
            "additional_user_ids" => ["", additional.user.id],
            "recurrence" => "annual",
            "reminder_offsets" => ["", "-30", "-14", "0"]
          }
        })
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "DueItem created."

      item = find_item(scope, "Fire safety NOC")
      assert item.related_party == "Fire Department"
      assert item.recurrence == "annual"
      assert DueItem.primary_user(item).id == primary.user.id
      assert Enum.map(DueItem.additional_users(item), & &1.id) == [additional.user.id]
      assert offsets(item) == [-30, -14, 0]
    end

    test "custom recurrence asks for a unit and interval", %{conn: conn, scope: scope} do
      organisation_for(scope)
      {:ok, lv, _html} = live(conn, ~p"/due-items/new")

      refute has_element?(lv, "#due_item_recurrence_unit")

      lv
      |> form("#due-item-form", %{"due_item" => %{"recurrence" => "custom"}})
      |> render_change()

      assert has_element?(lv, "#due_item_recurrence_unit")

      lv
      |> form("#due-item-form", %{
        "due_item" => %{"recurrence" => "custom", "recurrence_unit" => "month"}
      })
      |> render_change()

      assert has_element?(lv, "#due_item_recurrence_interval")
    end

    test "rejects an invalid custom reminder", %{conn: conn, scope: scope} do
      organisation_for(scope)
      {:ok, lv, _html} = live(conn, ~p"/due-items/new")

      lv
      |> form("#due-item-form", %{"custom_reminder" => %{"days" => "400"}})
      |> render_change()

      lv |> element("#add-reminder") |> render_click()
      assert has_element?(lv, "#custom-reminder-error")
    end

    test "requires a title and at least one date", %{conn: conn, scope: scope} do
      organisation = organisation_for(scope)
      {:ok, lv, _html} = live(conn, ~p"/due-items/new")

      lv
      |> form("#due-item-form", %{
        "due_item" => %{
          "title" => "",
          "organisation_id" => organisation.id,
          "category_id" => category_for(scope).id
        }
      })
      |> render_submit()

      assert has_element?(lv, "#due-item-form", "enter a title")
      assert has_element?(lv, "#due-item-form", "enter a Due Date or an Expiry Date")
      assert DueItems.list_due_items(scope, %{}) == []
    end

    test "asks for an Organisation first", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/due-items/new")
      assert has_element?(lv, "#no-organisations")
      assert has_element?(lv, ~s|#no-organisations a[href="/organisations/new"]|)
      refute has_element?(lv, "#due-item-form")
    end

    test "shows the plan limit instead of the form", %{conn: conn, scope: scope} do
      organisation = organisation_for(scope)
      for _ <- 1..10, do: due_item_fixture(scope, organisation_id: organisation.id)

      {:ok, lv, _html} = live(conn, ~p"/due-items/new")
      assert has_element?(lv, "#limit-notice", "Free Plan limit of 10 DueItems")
      assert has_element?(lv, ~s|#limit-notice a[href="/account/plans"]|)
      refute has_element?(lv, "#due-item-form")
    end

    test "edits a DueItem", %{conn: conn, scope: scope} do
      item = due_item_fixture(scope, title: "Old title")
      {:ok, lv, _html} = live(conn, ~p"/due-items/#{item}/edit")

      refute has_element?(lv, "#section-responsibility")
      assert has_element?(lv, "#section-recurrence")

      new_due = days_from_today(scope, 45)

      {:ok, _show, html} =
        lv
        |> form("#due-item-form", %{
          "due_item" => %{"title" => "New title", "due_date" => new_due}
        })
        |> render_submit()
        |> follow_redirect(conn, ~p"/due-items/#{item}")

      assert html =~ "DueItem updated."
      item = reload(scope, item)
      assert item.title == "New title"
      assert Date.to_iso8601(item.current_cycle.due_date) == new_due
    end

    test "another account's DueItem cannot be edited", %{conn: conn} do
      item = due_item_fixture(account_scope_fixture())

      assert {:error, {:live_redirect, %{to: "/due-items", flash: flash}}} =
               live(conn, ~p"/due-items/#{item}/edit")

      assert flash["error"] == "This DueItem is not available to your account access."
    end
  end

  describe "as Administrator on the Free plan" do
    setup :register_and_log_in_admin

    test "is told to ask the Super Admin at the limit", %{conn: conn, scope: scope} do
      organisation = organisation_for(scope)
      for _ <- 1..10, do: due_item_fixture(scope, organisation_id: organisation.id)

      {:ok, lv, _html} = live(conn, ~p"/due-items/new")
      assert has_element?(lv, "#limit-notice", "Ask your Super Admin to upgrade the plan.")
      refute has_element?(lv, ~s|#limit-notice a[href="/account/plans"]|)
    end
  end

  describe "as User" do
    setup :register_and_log_in_account_user

    test "sees the shorter form", %{conn: conn, scope: scope} do
      organisation_for(scope)
      {:ok, lv, _html} = live(conn, ~p"/due-items/new")

      assert has_element?(lv, "#section-basic")
      assert has_element?(lv, "#section-dates")
      assert has_element?(lv, "#user-create-note")
      refute has_element?(lv, "#section-responsibility")
      refute has_element?(lv, "#section-recurrence")
      refute has_element?(lv, "#section-reminders")
      refute has_element?(lv, "#due_item_related_party")
    end

    test "creates a DueItem and becomes its Primary Responsible", %{conn: conn, scope: scope} do
      organisation = organisation_for(scope)
      {:ok, lv, _html} = live(conn, ~p"/due-items/new")

      {:ok, show, _html} =
        lv
        |> form("#due-item-form", %{
          "due_item" => %{
            "title" => "Shop licence",
            "organisation_id" => organisation.id,
            "category_id" => category_for(scope).id,
            "due_date" => days_from_today(scope, 20)
          }
        })
        |> render_submit()
        |> follow_redirect(conn)

      assert has_element?(show, "#primary-responsible", scope.user.name)

      item = find_item(scope, "Shop licence")
      assert DueItem.primary_user(item).id == scope.user.id
      assert item.recurrence == "none"
      assert offsets(item) == [-90, -30, -7, 0, 1]
    end

    test "asks an Administrator for an Organisation", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/due-items/new")
      assert has_element?(lv, "#no-organisations", "Ask an Administrator")
      refute has_element?(lv, ~s|#no-organisations a[href="/organisations/new"]|)
    end

    test "cannot edit, even their own DueItem", %{conn: conn, scope: scope} do
      item = due_item_fixture(scope)

      assert {:error, {:live_redirect, %{to: "/due-items", flash: flash}}} =
               live(conn, ~p"/due-items/#{item}/edit")

      assert flash["error"] == "This DueItem is not available to your account access."
    end
  end
end

defmodule DueDeskWeb.DueItemLive.ShowTest do
  use DueDeskWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DueDesk.TenancyFixtures
  import DueDesk.DueItemsFixtures

  alias DueDesk.{Audit, DueItems}
  alias DueDesk.DueItems.DueItem

  @not_available "This DueItem is not available to your account access."

  defp assert_not_available(conn, path) do
    assert {:error, {:live_redirect, %{to: "/due-items", flash: flash}}} = live(conn, path)
    assert flash["error"] == @not_available
  end

  describe "as Super Admin" do
    setup :register_and_log_in_super_admin

    test "shows dates, details, responsibility and schedule", %{conn: conn, scope: scope} do
      member = member_scope_fixture(scope, "user")

      item =
        due_item_fixture(scope,
          title: "Fire insurance",
          reference_number: "POL-4471",
          related_party: "New India Assurance",
          due_date: days_from_today(scope, 10),
          expiry_date: days_from_today(scope, 25),
          primary_user_id: member.user.id,
          recurrence: "annual"
        )

      {:ok, lv, _html} = live(conn, ~p"/due-items/#{item}")

      assert has_element?(lv, "h1", "Fire insurance")
      assert has_element?(lv, "#due-item-status", "Due Soon")
      assert has_element?(lv, "#due-item-due-date")
      assert has_element?(lv, "#due-item-expiry-date")
      assert has_element?(lv, "#due-item-details", "POL-4471")
      assert has_element?(lv, "#due-item-details", "New India Assurance")
      assert has_element?(lv, "#primary-responsible", member.user.name)
      assert has_element?(lv, "#due-item-recurrence", "Every year")
      assert has_element?(lv, "#due-item-reminders")
      assert has_element?(lv, "#history", "created this DueItem")
      assert has_element?(lv, "#edit-due-item")
      assert has_element?(lv, "#archive-due-item")
      assert has_element?(lv, "#open-override")
      assert has_element?(lv, "#open-assign")
    end

    test "assigns an Unassigned DueItem", %{conn: conn, scope: scope} do
      primary = member_scope_fixture(scope, "user")
      additional = member_scope_fixture(scope, "user")
      item = due_item_fixture(scope)

      {:ok, lv, _html} = live(conn, ~p"/due-items/#{item}")
      assert has_element?(lv, "#unassigned-notice")
      assert has_element?(lv, "#due-item-status", "Unassigned")

      lv |> element("#open-assign") |> render_click()

      lv
      |> form("#assign-form", %{"assignment" => %{"primary_user_id" => primary.user.id}})
      |> render_change()

      refute has_element?(lv, "#assign-additional-#{primary.user.id}")

      lv
      |> form("#assign-form", %{
        "assignment" => %{
          "primary_user_id" => primary.user.id,
          "additional_user_ids" => ["", additional.user.id]
        }
      })
      |> render_submit()

      assert has_element?(lv, "#primary-responsible", primary.user.name)
      assert has_element?(lv, "#additional-assignees", additional.user.name)
      refute has_element?(lv, "#unassigned-notice")
      assert has_element?(lv, "#history", "as Primary Responsible")

      item = reload(scope, item)
      assert DueItem.primary_user(item).id == primary.user.id
      assert Enum.map(DueItem.additional_users(item), & &1.id) == [additional.user.id]
    end

    test "overrides the status with a reason and clears it", %{conn: conn, scope: scope} do
      item = due_item_fixture(scope, due_date: days_from_today(scope, -3))

      {:ok, lv, _html} = live(conn, ~p"/due-items/#{item}")
      assert has_element?(lv, "#due-item-status", "Overdue")

      lv |> element("#open-override") |> render_click()

      lv
      |> form("#override-form", %{"override" => %{"status" => "up_to_date", "reason" => ""}})
      |> render_submit()

      assert has_element?(lv, "#override-form", "enter a reason")
      assert reload(scope, item).current_cycle.status_override == nil

      lv
      |> form("#override-form", %{
        "override" => %{"status" => "up_to_date", "reason" => "Paid on the portal"}
      })
      |> render_submit()

      refute has_element?(lv, "#override-form")
      assert has_element?(lv, "#due-item-status", "Up to Date")
      assert has_element?(lv, "#status-override", "Paid on the portal")
      assert reload(scope, item).current_cycle.status_override == "up_to_date"

      lv |> element("#clear-override") |> render_click()
      assert has_element?(lv, "#due-item-status", "Overdue")
      refute has_element?(lv, "#status-override")
    end

    test "archives and restores", %{conn: conn, scope: scope} do
      item = due_item_fixture(scope)
      {:ok, lv, _html} = live(conn, ~p"/due-items/#{item}")

      lv |> element("#archive-due-item") |> render_click()

      assert has_element?(lv, "#archived-banner")
      assert has_element?(lv, "#restore-due-item")
      refute has_element?(lv, "#edit-due-item")
      refute has_element?(lv, "#note-form")
      assert reload(scope, item).status == "archived"

      lv |> element("#restore-due-item") |> render_click()

      refute has_element?(lv, "#archived-banner")
      assert has_element?(lv, "#archive-due-item")
      assert reload(scope, item).status == "active"
      assert has_element?(lv, "#history", "restored this DueItem")
    end

    test "restore is blocked at the plan limit", %{conn: conn, scope: scope} do
      archived = due_item_fixture(scope)
      {:ok, _} = DueItems.archive_due_item(scope, archived)
      for _ <- 1..10, do: due_item_fixture(scope)

      {:ok, lv, _html} = live(conn, ~p"/due-items/#{archived}")
      lv |> element("#restore-due-item") |> render_click()

      assert has_element?(lv, "#limit-notice")
      assert reload(scope, archived).status == "archived"
    end

    test "adds a note without putting its text in the audit log", %{conn: conn, scope: scope} do
      item = due_item_fixture(scope)
      {:ok, lv, _html} = live(conn, ~p"/due-items/#{item}")

      assert has_element?(lv, "#notes-empty")

      lv
      |> form("#note-form", %{"note" => %{"body" => "Called the municipal office"}})
      |> render_submit()

      assert has_element?(lv, "#notes", "Called the municipal office")
      assert has_element?(lv, "#history", "added a note")

      for event <- Audit.list_events(scope, subject: item) do
        refute inspect(event.changes) =~ "municipal"
        refute inspect(event.metadata) =~ "municipal"
      end
    end

    test "another account's DueItem or a guessed id is not available", %{conn: conn} do
      item = due_item_fixture(account_scope_fixture())

      assert_not_available(conn, ~p"/due-items/#{item}")
      assert_not_available(conn, ~p"/due-items/#{Ecto.UUID.generate()}")
    end
  end

  describe "as User" do
    setup :register_and_log_in_account_user

    setup %{scope: scope} do
      %{admin: member_scope_fixture(scope, "admin")}
    end

    test "sees their DueItem without admin actions", %{conn: conn, scope: scope, admin: admin} do
      item = due_item_fixture(admin, primary_user_id: scope.user.id)
      {:ok, lv, _html} = live(conn, ~p"/due-items/#{item}")

      assert has_element?(lv, "#primary-responsible", scope.user.name)
      assert has_element?(lv, "#note-form")
      refute has_element?(lv, "#edit-due-item")
      refute has_element?(lv, "#archive-due-item")
      refute has_element?(lv, "#open-override")
      refute has_element?(lv, "#open-assign")
    end

    test "admin-only events do nothing", %{conn: conn, scope: scope, admin: admin} do
      item = due_item_fixture(admin, primary_user_id: scope.user.id)
      {:ok, lv, _html} = live(conn, ~p"/due-items/#{item}")

      render_click(lv, "open_panel", %{"panel" => "override"})
      refute has_element?(lv, "#override-form")

      render_click(lv, "open_panel", %{"panel" => "assign"})
      refute has_element?(lv, "#assign-form")

      assert {:error, {:live_redirect, %{to: "/due-items"}}} = render_click(lv, "archive", %{})
      assert reload(admin, item).status == "active"
    end

    test "adds a note", %{conn: conn, scope: scope, admin: admin} do
      item = due_item_fixture(admin, primary_user_id: scope.user.id)
      {:ok, lv, _html} = live(conn, ~p"/due-items/#{item}")

      lv
      |> form("#note-form", %{"note" => %{"body" => "Documents sent to the CA"}})
      |> render_submit()

      assert has_element?(lv, "#notes", "Documents sent to the CA")
    end

    test "cannot open a DueItem assigned to someone else", %{
      conn: conn,
      scope: scope,
      admin: admin
    } do
      other = member_scope_fixture(scope, "user")

      assert_not_available(
        conn,
        ~p"/due-items/#{due_item_fixture(admin, primary_user_id: other.user.id)}"
      )

      assert_not_available(conn, ~p"/due-items/#{due_item_fixture(admin)}")
    end

    test "cannot open an archived DueItem", %{conn: conn, scope: scope, admin: admin} do
      item = due_item_fixture(admin, primary_user_id: scope.user.id)
      {:ok, _} = DueItems.archive_due_item(admin, item)

      assert_not_available(conn, ~p"/due-items/#{item}")
    end

    test "loses access after being reassigned", %{conn: conn, scope: scope, admin: admin} do
      other = member_scope_fixture(scope, "user")
      {:ok, item} = DueItems.create_due_item(scope, valid_due_item_attributes(scope))

      {:ok, lv, _html} = live(conn, ~p"/due-items/#{item}")
      assert has_element?(lv, "#primary-responsible", scope.user.name)

      {:ok, _} =
        DueItems.assign_due_item(admin, reload(admin, item), %{
          "primary_user_id" => other.user.id
        })

      {:ok, list, _html} =
        lv
        |> form("#note-form", %{"note" => %{"body" => "Still working on it"}})
        |> render_submit()
        |> follow_redirect(conn, ~p"/due-items")

      assert has_element?(list, "#flash-error", @not_available)
      assert_not_available(conn, ~p"/due-items/#{item}")
    end
  end
end

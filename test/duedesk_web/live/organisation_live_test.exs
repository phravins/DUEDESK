defmodule DueDeskWeb.OrganisationLiveTest do
  use DueDeskWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DueDesk.TenancyFixtures
  import DueDesk.OrganisationsFixtures
  import DueDesk.DueItemsFixtures

  alias DueDesk.{DueItems, Organisations}

  defp form_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: "Sharma Traders",
      type: "proprietorship",
      identifier: unique_udyam(),
      declaration_accepted: "true"
    })
  end

  describe "as Super Admin" do
    setup :register_and_log_in_super_admin

    setup %{conn: conn, scope: scope} do
      scope = put_plan(scope, "business")
      %{conn: conn, scope: scope}
    end

    test "lists active Organisations and switches to the Archived tab", %{
      conn: conn,
      scope: scope
    } do
      active = organisation_fixture(scope, name: "Active Co")
      archived = organisation_fixture(scope, name: "Archived Co")
      {:ok, _} = Organisations.archive_organisation(scope, archived)

      {:ok, lv, _html} = live(conn, ~p"/organisations")
      assert has_element?(lv, "#organisations-#{active.id}", "Active Co")
      refute has_element?(lv, "#organisations-#{archived.id}")
      assert has_element?(lv, "#add-organisation")

      lv |> element("#tab-archived") |> render_click()
      assert_patch(lv, ~p"/organisations?status=archived")
      assert has_element?(lv, "#organisations-#{archived.id}", "Archived Co")
      refute has_element?(lv, "#organisations-#{active.id}")
    end

    test "counts and lists each Organisation's active DueItems", %{conn: conn, scope: scope} do
      busy = organisation_fixture(scope, name: "Busy Co")
      quiet = organisation_fixture(scope, name: "Quiet Co")
      first = due_item_fixture(scope, organisation_id: busy.id, title: "Trade Licence")
      second = due_item_fixture(scope, organisation_id: busy.id)
      archived = due_item_fixture(scope, organisation_id: busy.id)
      {:ok, _} = DueItems.archive_due_item(scope, archived)

      {:ok, lv, _html} = live(conn, ~p"/organisations")
      assert has_element?(lv, "#organisation-due-item-count-#{busy.id}", "2")
      assert has_element?(lv, "#organisation-due-item-count-#{quiet.id}", "0")

      {:ok, lv, _html} = live(conn, ~p"/organisations/#{busy}")
      assert has_element?(lv, "#organisation-due-item-#{first.id}", "Trade Licence")
      assert has_element?(lv, "#organisation-due-item-#{second.id}")
      refute has_element?(lv, "#organisation-due-item-#{archived.id}")

      assert has_element?(
               lv,
               ~s|#organisation-due-items a[href="/due-items?organisation_id=#{busy.id}"]|
             )

      {:ok, lv, _html} = live(conn, ~p"/organisations/#{quiet}")
      assert has_element?(lv, "#organisation-due-items-empty")
      refute has_element?(lv, "#organisation-due-items")
    end

    test "shows an empty state with no Organisations", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/organisations")
      assert has_element?(lv, "#organisations-empty")
    end

    test "adds an Organisation and opens it", %{conn: conn, scope: scope} do
      {:ok, lv, _html} = live(conn, ~p"/organisations/new")

      {:ok, show, _html} =
        lv
        |> form("#organisation-form", organisation: form_attrs())
        |> render_submit()
        |> follow_redirect(conn)

      [organisation] = Organisations.list_organisations(scope)
      assert has_element?(show, "h1", "Sharma Traders")
      assert has_element?(show, "#organisation-declaration")
      assert render(show) =~ "Organisation added."
      assert Organisations.latest_declaration(scope, organisation)
    end

    test "the identifier field follows the Organisation type", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/organisations/new")

      html =
        lv
        |> form("#organisation-form", organisation: %{type: "llp"})
        |> render_change()

      assert html =~ "LLPIN"

      html =
        lv
        |> form("#organisation-form", organisation: %{type: "private_limited"})
        |> render_change()

      assert html =~ "CIN"
    end

    test "requires the declaration", %{conn: conn, scope: scope} do
      {:ok, lv, _html} = live(conn, ~p"/organisations/new")

      lv
      |> form("#organisation-form", organisation: form_attrs(declaration_accepted: "false"))
      |> render_submit()

      assert has_element?(lv, "#organisation-form")
      assert Organisations.list_organisations(scope) == []
    end

    test "a registered identifier shows only the generic notice", %{conn: conn} do
      other = account_scope_fixture()
      organisation_fixture(other, name: "Hidden Other Co", identifier: "UDYAM-KA-02-0000099")

      {:ok, lv, _html} = live(conn, ~p"/organisations/new")

      html =
        lv
        |> form("#organisation-form",
          organisation: form_attrs(identifier: "udyam-ka-02-0000099")
        )
        |> render_submit()

      assert has_element?(lv, "#duplicate-notice")
      assert has_element?(lv, "#duplicate-support-link")
      refute html =~ "Hidden Other Co"
      refute html =~ other.customer_account.name
    end

    test "edits the name without a new declaration", %{conn: conn, scope: scope} do
      organisation = organisation_fixture(scope)
      {:ok, lv, _html} = live(conn, ~p"/organisations/#{organisation}/edit")

      {:ok, show, _html} =
        lv
        |> form("#organisation-form", organisation: %{name: "Renamed Co"})
        |> render_submit()
        |> follow_redirect(conn)

      assert has_element?(show, "h1", "Renamed Co")
      assert render(show) =~ "Organisation updated."
    end

    test "archives and restores from the Organisation page", %{conn: conn, scope: scope} do
      organisation = organisation_fixture(scope)
      {:ok, lv, _html} = live(conn, ~p"/organisations/#{organisation}")

      lv |> element("#archive-organisation") |> render_click()
      assert has_element?(lv, "#restore-organisation")
      refute has_element?(lv, "#edit-organisation")
      assert Organisations.get_organisation!(scope, organisation.id).status == "archived"

      lv |> element("#restore-organisation") |> render_click()
      assert has_element?(lv, "#archive-organisation")
      assert Organisations.get_organisation!(scope, organisation.id).status == "active"
    end

    test "another account's Organisation is not found", %{conn: conn} do
      other = account_scope_fixture()
      organisation = organisation_fixture(other)

      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/organisations/#{organisation}") end

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/organisations/#{organisation}/edit")
      end
    end
  end

  describe "on the Free plan" do
    setup :register_and_log_in_super_admin

    test "the limit replaces the add button and links to the plans", %{conn: conn, scope: scope} do
      organisation_fixture(scope)

      {:ok, lv, _html} = live(conn, ~p"/organisations")
      refute has_element?(lv, "#add-organisation")
      assert has_element?(lv, "#limit-notice", "Free Plan limit of 1 Organisation")
      assert has_element?(lv, ~s|#limit-notice a[href="/account/plans"]|)

      {:ok, lv, _html} = live(conn, ~p"/organisations/new")
      assert has_element?(lv, "#limit-notice")
      refute has_element?(lv, "#organisation-form")
    end

    test "restore is blocked at the limit", %{conn: conn, scope: scope} do
      archived = organisation_fixture(scope)
      {:ok, _} = Organisations.archive_organisation(scope, archived)
      organisation_fixture(scope)

      {:ok, lv, _html} = live(conn, ~p"/organisations/#{archived}")
      lv |> element("#restore-organisation") |> render_click()

      assert has_element?(lv, "#limit-notice")
      assert Organisations.get_organisation!(scope, archived.id).status == "archived"
    end
  end

  describe "as Administrator on the Free plan" do
    setup :register_and_log_in_admin

    test "is told to ask the Super Admin", %{conn: conn, scope: scope} do
      organisation_fixture(scope)

      {:ok, lv, _html} = live(conn, ~p"/organisations")
      assert has_element?(lv, "#limit-notice", "Ask your Super Admin to upgrade the plan.")
      refute has_element?(lv, ~s|#limit-notice a[href="/account/plans"]|)
    end
  end

  describe "as User" do
    setup :register_and_log_in_account_user

    test "cannot open any Organisation page", %{conn: conn, scope: scope} do
      organisation = scope |> member_scope_fixture("admin") |> organisation_fixture()

      for path <- [
            ~p"/organisations",
            ~p"/organisations/new",
            ~p"/organisations/#{organisation}",
            ~p"/organisations/#{organisation}/edit"
          ] do
        assert {:error, {:live_redirect, %{to: "/dashboard", flash: flash}}} = live(conn, path)
        assert flash["error"] =~ "not available to your account access"
      end
    end
  end
end

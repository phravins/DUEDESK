defmodule DueDeskWeb.CategoryLiveTest do
  use DueDeskWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias DueDesk.Categories

  describe "as Administrator" do
    setup :register_and_log_in_admin

    test "lists the default categories, read-only", %{conn: conn, scope: scope} do
      {:ok, lv, _html} = live(conn, ~p"/categories")
      [first | _] = Categories.list_categories(scope)

      assert has_element?(lv, "#system_categories-#{first.id}", first.name)
      refute has_element?(lv, "#rename-#{first.id}")
      assert has_element?(lv, "#custom-categories-empty")
    end

    test "adds a category", %{conn: conn, scope: scope} do
      {:ok, lv, _html} = live(conn, ~p"/categories")

      lv |> form("#category-form", category: %{name: "Trademarks"}) |> render_submit()

      category = Enum.find(Categories.list_categories(scope), &(&1.name == "Trademarks"))
      assert has_element?(lv, "#custom_categories-#{category.id}", "Trademarks")
      assert render(lv) =~ "Category added."
    end

    test "shows a duplicate name error", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/categories")

      html = lv |> form("#category-form", category: %{name: "insurance"}) |> render_submit()
      assert html =~ "a category with this name already exists"
    end

    test "renames, archives and restores a custom category", %{conn: conn, scope: scope} do
      {:ok, category} = Categories.create_category(scope, %{name: "Trademarks"})
      {:ok, lv, _html} = live(conn, ~p"/categories")

      lv |> element("#rename-#{category.id}") |> render_click()

      lv
      |> form("#rename-form-#{category.id}", category: %{name: "Trademarks & IP"})
      |> render_submit()

      assert has_element?(lv, "#custom_categories-#{category.id}", "Trademarks & IP")
      refute has_element?(lv, "#rename-form-#{category.id}")

      lv |> element("#archive-#{category.id}") |> render_click()
      assert has_element?(lv, "#restore-#{category.id}")
      assert Categories.get_category!(scope, category.id).status == "archived"

      lv |> element("#restore-#{category.id}") |> render_click()
      assert has_element?(lv, "#archive-#{category.id}")
      assert Categories.get_category!(scope, category.id).status == "active"
    end
  end

  describe "as User" do
    setup :register_and_log_in_account_user

    test "cannot open categories", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/dashboard", flash: flash}}} =
               live(conn, ~p"/categories")

      assert flash["error"] =~ "not available to your account access"
    end
  end
end

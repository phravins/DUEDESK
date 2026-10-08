defmodule DueDesk.CategoriesTest do
  use DueDesk.DataCase, async: true

  import DueDesk.TenancyFixtures

  alias DueDesk.{Audit, Categories}
  alias DueDesk.DueItems.Category

  setup do
    %{scope: account_scope_fixture()}
  end

  test "every new account gets the default categories in order", %{scope: scope} do
    categories = Categories.list_categories(scope)
    assert Enum.map(categories, & &1.name) == Categories.defaults()
    assert Enum.all?(categories, &(&1.system and &1.status == "active"))
  end

  test "custom categories are listed after the defaults, by name", %{scope: scope} do
    {:ok, _} = Categories.create_category(scope, %{name: "zebra permits"})
    {:ok, _} = Categories.create_category(scope, %{name: "  Trademarks   and  IP "})

    names = scope |> Categories.list_categories() |> Enum.map(& &1.name)
    assert Enum.take(names, -2) == ["Trademarks and IP", "zebra permits"]
  end

  test "names are unique per account, ignoring case", %{scope: scope} do
    {:ok, _} = Categories.create_category(scope, %{name: "Trademarks"})
    {:error, changeset} = Categories.create_category(scope, %{name: "trademarks"})
    assert "a category with this name already exists" in errors_on(changeset).name

    {:error, changeset} = Categories.create_category(scope, %{name: "insurance"})
    assert "a category with this name already exists" in errors_on(changeset).name

    assert {:ok, _} = Categories.create_category(account_scope_fixture(), %{name: "Trademarks"})
  end

  test "custom categories can be renamed, archived and restored", %{scope: scope} do
    {:ok, category} = Categories.create_category(scope, %{name: "Trademarks"})
    {:ok, category} = Categories.rename_category(scope, category, %{name: "Trademarks & IP"})
    assert category.name == "Trademarks & IP"

    {:ok, category} = Categories.archive_category(scope, category)
    assert category.status == "archived"
    assert category.archived_at
    assert [_] = Categories.list_categories(scope, status: "archived")

    {:ok, category} = Categories.restore_category(scope, category)
    assert category.status == "active"

    actions =
      scope
      |> Audit.list_events(subject: category)
      |> Enum.map(& &1.action)
      |> Enum.sort()

    assert actions ==
             ~w(category.archived category.created category.renamed category.restored)
  end

  test "default categories cannot be changed", %{scope: scope} do
    [system | _] = Categories.list_categories(scope)

    assert Categories.rename_category(scope, system, %{name: "Mine"}) ==
             {:error, :system_category}

    assert Categories.archive_category(scope, system) == {:error, :system_category}
  end

  test "Users cannot manage categories", %{scope: scope} do
    user_scope = member_scope_fixture(scope, "user")
    assert Categories.create_category(user_scope, %{name: "X ray"}) == {:error, :unauthorized}
  end

  test "another account's category cannot be fetched or changed", %{scope: scope} do
    other = account_scope_fixture()
    {:ok, category} = Categories.create_category(other, %{name: "Theirs"})

    assert_raise Ecto.NoResultsError, fn -> Categories.get_category!(scope, category.id) end

    assert Categories.rename_category(scope, category, %{name: "Mine"}) ==
             {:error, :unauthorized}
  end

  test "names are required and length-limited", %{scope: scope} do
    {:error, changeset} = Categories.create_category(scope, %{name: " "})
    assert "enter a category name" in errors_on(changeset).name

    {:error, changeset} = Categories.create_category(scope, %{name: String.duplicate("a", 61)})
    assert errors_on(changeset).name != []
    refute Repo.get_by(Category, name: String.duplicate("a", 61))
  end
end

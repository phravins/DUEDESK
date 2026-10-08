defmodule DueDesk.DueItemsFixtures do
  @moduledoc """
  Test helpers for DueItems.
  """

  import DueDesk.OrganisationsFixtures
  import Ecto.Query, only: [from: 2]

  alias DueDesk.{Categories, DueItems, Repo, Tenancy}
  alias DueDesk.Accounts.Scope
  alias DueDesk.Organisations.Organisation

  @doc "The first active category of the scope's account."
  def category_for(%Scope{} = scope) do
    scope |> Categories.list_categories(status: "active") |> hd()
  end

  @doc """
  An active Organisation of the scope's account, created the first time.
  Uses an admin scope of the same account when `scope` is a User.
  """
  def organisation_for(%Scope{} = scope) do
    account_id = Scope.account_id!(scope)

    Repo.one(
      from o in Organisation,
        where: o.customer_account_id == ^account_id and o.status == "active",
        order_by: o.inserted_at,
        limit: 1
    ) || organisation_fixture(%{scope | role: :super_admin})
  end

  def valid_due_item_attributes(scope, attrs \\ %{}) do
    # Organisation and category are only looked up when not given, so a
    # test can use any of several Organisations.
    %{
      "title" => "Trade licence #{System.unique_integer([:positive])}",
      "due_date" => Date.to_iso8601(Date.add(Tenancy.today(scope), 120))
    }
    |> Map.merge(Map.new(attrs))
    |> Map.put_new_lazy("organisation_id", fn -> organisation_for(scope).id end)
    |> Map.put_new_lazy("category_id", fn -> category_for(scope).id end)
  end

  @doc """
  Creates a DueItem in the scope's account and returns it loaded for
  display. String or atom keys are accepted in `attrs`.
  """
  def due_item_fixture(%Scope{} = scope, attrs \\ %{}) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    {:ok, item} = DueItems.create_due_item(scope, valid_due_item_attributes(scope, attrs))
    reload(scope, item)
  end

  @doc "Reloads a DueItem as an Administrator of its account sees it."
  def reload(%Scope{} = scope, item) do
    {:ok, item} = DueItems.get_due_item(%{scope | role: :super_admin}, item.id)
    item
  end

  @doc "An ISO date `days` from today in the scope's account."
  def days_from_today(scope, days),
    do: scope |> Tenancy.today() |> Date.add(days) |> Date.to_iso8601()
end

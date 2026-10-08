defmodule DueDesk.DueItems.StatusTest do
  use DueDesk.DataCase, async: true

  import Ecto.Query
  import DueDesk.TenancyFixtures
  import DueDesk.DueItemsFixtures

  require DueDesk.DueItems.Status

  alias DueDesk.{DueItems, Repo}
  alias DueDesk.DueItems.{Cycle, DueItem, Queries, Status}

  @today ~D[2027-03-15]

  defp status(attrs, cycle_attrs) do
    Status.effective(struct(DueItem, attrs), struct(Cycle, cycle_attrs), @today, 30)
  end

  describe "effective/4" do
    test "archived wins over everything" do
      assert status(%{status: "archived"}, %{due_date: ~D[2020-01-01], status_override: "overdue"}) ==
               :archived
    end

    test "an override wins over the dates" do
      assert status(%{status: "active"}, %{
               due_date: ~D[2020-01-01],
               status_override: "up_to_date"
             }) ==
               :up_to_date
    end

    test "a date before today is overdue" do
      assert status(%{status: "active"}, %{due_date: ~D[2027-03-14]}) == :overdue
    end

    test "today and the last day of the window are due soon" do
      assert status(%{status: "active"}, %{due_date: @today}) == :due_soon
      assert status(%{status: "active"}, %{due_date: ~D[2027-04-14]}) == :due_soon
    end

    test "after the window is up to date" do
      assert status(%{status: "active"}, %{due_date: ~D[2027-04-15]}) == :up_to_date
    end

    test "the Due Date drives status, else the Expiry Date" do
      assert status(%{status: "active"}, %{due_date: ~D[2027-06-01], expiry_date: ~D[2027-01-01]}) ==
               :up_to_date

      assert status(%{status: "active"}, %{expiry_date: ~D[2027-01-01]}) == :overdue
    end
  end

  test "the SQL rule agrees with the Elixir rule" do
    scope = account_scope_fixture() |> put_plan("entrepreneur")
    today = DueDesk.Tenancy.today(scope)
    days = scope.customer_account.due_soon_days

    offsets = [-1, 0, 1, days, days + 1]

    cases =
      for offset <- offsets,
          field <- ["due_date", "expiry_date"],
          override <- [nil, "overdue", "up_to_date"],
          archived? <- [false, true] do
        {offset, field, override, archived?}
      end

    items =
      for {offset, field, override, archived?} <- cases do
        dates = Map.put(%{"due_date" => nil}, field, days_from_today(scope, offset))
        item = due_item_fixture(scope, dates)

        if override do
          {:ok, _} = DueItems.override_status(scope, item, override, "Checked")
        end

        if archived?, do: {:ok, _} = DueItems.archive_due_item(scope, item)
        reload(scope, item)
      end

    soon_until = Date.add(today, days)

    sql =
      scope
      |> Queries.base()
      |> select([item: i, cycle: c], {i.id, Status.sql(i, c, ^today, ^soon_until)})
      |> Repo.all()
      |> Map.new()

    for item <- items do
      expected = Status.effective(item, item.current_cycle, today, days)
      assert sql[item.id] == Atom.to_string(expected)
    end
  end
end

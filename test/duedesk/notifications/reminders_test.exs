defmodule DueDesk.Notifications.RemindersTest do
  use DueDesk.DataCase, async: true

  import Ecto.Query
  import DueDesk.TenancyFixtures
  import DueDesk.DueItemsFixtures

  alias DueDesk.{DueItems, Repo, Tenancy}
  alias DueDesk.DueItems.{Cycle, DueItem, ReminderRule}
  alias DueDesk.Notifications.Reminders

  describe "targets/4" do
    test "puts each rule on the effective date plus its offset, then repeats weekly" do
      cycle = %Cycle{due_date: ~D[2027-03-15]}

      assert Reminders.targets(cycle, [-7, 0, 1], ~D[2027-03-01], ~D[2027-03-31]) == [
               {~D[2027-03-08], -7},
               {~D[2027-03-15], 0},
               {~D[2027-03-16], 1},
               {~D[2027-03-23], 1},
               {~D[2027-03-30], 1}
             ]
    end

    test "uses the Expiry Date when there is no Due Date" do
      cycle = %Cycle{expiry_date: ~D[2027-06-30]}

      assert Reminders.targets(cycle, [-30], ~D[2027-05-31], ~D[2027-05-31]) ==
               [{~D[2027-05-31], -30}]
    end

    test "only returns dates in the range" do
      cycle = %Cycle{due_date: ~D[2027-03-15]}
      assert Reminders.targets(cycle, [-7, 0], ~D[2027-03-09], ~D[2027-03-14]) == []
    end

    test "does not repeat when every rule is before the date" do
      cycle = %Cycle{due_date: ~D[2027-03-15]}
      assert Reminders.targets(cycle, [-30, -7], ~D[2027-03-09], ~D[2027-06-30]) == []
    end

    test "a status override other than Overdue stops reminders after the date" do
      cycle = %Cycle{due_date: ~D[2027-03-15], status_override: "up_to_date"}

      assert Reminders.targets(cycle, [-7, 0, 1], ~D[2027-03-01], ~D[2027-03-31]) ==
               [{~D[2027-03-08], -7}, {~D[2027-03-15], 0}]

      overdue = %{cycle | status_override: "overdue"}
      assert length(Reminders.targets(overdue, [-7, 0, 1], ~D[2027-03-01], ~D[2027-03-31])) == 5
    end

    test "nothing without a date or rules" do
      assert Reminders.targets(%Cycle{}, [0], ~D[2027-01-01], ~D[2027-12-31]) == []

      assert Reminders.targets(
               %Cycle{due_date: ~D[2027-03-15]},
               [],
               ~D[2027-01-01],
               ~D[2027-12-31]
             ) ==
               []
    end
  end

  describe "next/4" do
    setup do
      %{item: %DueItem{status: "active", disposition_state: nil}}
    end

    test "returns the next rule's date", %{item: item} do
      cycle = %Cycle{due_date: ~D[2027-03-15]}

      assert Reminders.next(item, cycle, [-30, -7, 0], ~D[2027-03-01]) ==
               {~D[2027-03-08], -7, false}
    end

    test "finds a reminder months away", %{item: item} do
      cycle = %Cycle{due_date: ~D[2028-03-15]}
      assert Reminders.next(item, cycle, [-7], ~D[2027-03-01]) == {~D[2028-03-08], -7, false}
    end

    test "returns the weekly repeat once overdue", %{item: item} do
      cycle = %Cycle{due_date: ~D[2027-03-15]}
      assert Reminders.next(item, cycle, [-7, 0, 1], ~D[2027-03-20]) == {~D[2027-03-23], 1, true}
    end

    test "nil when nothing is left, or the DueItem is not live", %{item: item} do
      cycle = %Cycle{due_date: ~D[2027-03-15]}
      assert Reminders.next(item, cycle, [-7, -1], ~D[2027-03-15]) == nil
      assert Reminders.next(%{item | status: "archived"}, cycle, [-7], ~D[2027-03-01]) == nil

      assert Reminders.next(
               %{item | disposition_state: "awaiting_new_dates"},
               cycle,
               [-7],
               ~D[2027-03-01]
             ) ==
               nil
    end
  end

  describe "occurrences/2" do
    setup do
      owner = account_scope_fixture() |> put_plan("business")
      %{owner: owner, today: Tenancy.today(owner)}
    end

    defp item(owner, days, offsets, attrs \\ %{}) do
      due_item_fixture(
        owner,
        Map.merge(
          %{
            due_date: days_from_today(owner, days),
            reminder_offsets: Enum.map(offsets, &to_string/1)
          },
          attrs
        )
      )
    end

    defp found(owner, today) do
      for occ <- Reminders.occurrences(owner.customer_account, today),
          do: {occ.item.id, occ.offset_days, occ.target_date, occ.escalated}
    end

    test "finds reminders in the catch-up window", %{owner: owner, today: today} do
      item = item(owner, 10, [-7, 0, 1])

      assert found(owner, Date.add(today, 2)) == []
      assert found(owner, Date.add(today, 3)) == [{item.id, -7, Date.add(today, 3), false}]
      assert found(owner, Date.add(today, 5)) == [{item.id, -7, Date.add(today, 3), false}]
      assert found(owner, Date.add(today, 6)) == []
    end

    test "marks reminders after the date as escalated", %{owner: owner, today: today} do
      item = item(owner, 10, [0, 1])

      assert found(owner, Date.add(today, 11)) == [
               {item.id, 0, Date.add(today, 10), false},
               {item.id, 1, Date.add(today, 11), true}
             ]
    end

    test "skips reminders that fell before the cycle began", %{owner: owner, today: today} do
      _item = item(owner, 5, [-7])
      assert found(owner, today) == []
    end

    test "skips archived DueItems and inactive rules", %{owner: owner, today: today} do
      archived = item(owner, 10, [-7])
      {:ok, _} = DueItems.archive_due_item(owner, archived)

      off = item(owner, 10, [-7])

      Repo.update_all(from(r in ReminderRule, where: r.due_item_id == ^off.id),
        set: [active: false]
      )

      assert found(owner, Date.add(today, 3)) == []
    end

    test "skips completed DueItems awaiting a decision", %{owner: owner, today: today} do
      item = item(owner, 10, [-7])
      {:ok, _} = DueItems.complete_due_item(owner, item, %{})
      assert found(owner, Date.add(today, 3)) == []
    end

    test "only looks at the given account", %{owner: owner, today: today} do
      other = account_scope_fixture()
      item(other, 10, [-7])
      assert found(owner, Date.add(today, 3)) == []
    end
  end
end

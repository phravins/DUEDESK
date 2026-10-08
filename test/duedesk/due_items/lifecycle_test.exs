defmodule DueDesk.DueItems.LifecycleTest do
  use DueDesk.DataCase, async: true

  import Ecto.Query
  import DueDesk.TenancyFixtures
  import DueDesk.DueItemsFixtures
  import DueDesk.DocumentsFixtures

  alias DueDesk.{Billing, Documents, DueItems, Repo, Tenancy}
  alias DueDesk.Documents.Document
  alias DueDesk.Audit.AuditEvent
  alias DueDesk.DueItems.{Cycle, DueItem, ReminderRule}

  setup do
    owner = account_scope_fixture() |> put_plan("business")
    admin = member_scope_fixture(owner, "admin")
    user_a = member_scope_fixture(owner, "user")
    user_b = member_scope_fixture(owner, "user")
    %{owner: owner, admin: admin, user_a: user_a, user_b: user_b}
  end

  defp events(item) do
    Repo.all(
      from e in AuditEvent,
        where: e.subject_id == ^item.id,
        order_by: [asc: e.inserted_at]
    )
  end

  # Events written in the same second have no reliable order.
  defp actions(item), do: item |> events() |> Enum.map(& &1.action) |> Enum.sort()

  defp event(item, action), do: Enum.find(events(item), &(&1.action == action))

  defp cycles(item),
    do: Repo.all(from c in Cycle, where: c.due_item_id == ^item.id, order_by: c.sequence)

  defp sentences(scope, item), do: Enum.map(DueItems.history(scope, item), & &1.sentence)

  defp offsets(item) do
    Repo.all(
      from r in ReminderRule,
        where: r.due_item_id == ^item.id and r.active,
        order_by: r.offset_days,
        select: r.offset_days
    )
  end

  defp monthly_item(ctx, attrs \\ %{}) do
    due_item_fixture(
      ctx.admin,
      Map.merge(
        %{
          recurrence: "monthly",
          due_date: "2027-01-31",
          expiry_date: "2027-02-15",
          primary_user_id: ctx.user_a.user.id,
          additional_user_ids: [ctx.user_b.user.id],
          reminder_offsets: ["-7", "0"]
        },
        attrs
      )
    )
  end

  describe "renew_due_item/3" do
    test "closes the cycle and starts the next one with computed dates", ctx do
      item = monthly_item(ctx)
      today = Tenancy.today(ctx.owner)

      assert {:ok, _} =
               DueItems.renew_due_item(ctx.user_a, item, %{"note" => "Paid challan 4471"})

      renewed = reload(ctx.admin, item)
      assert renewed.current_cycle.sequence == 2
      assert renewed.current_cycle.due_date == ~D[2027-02-28]
      assert renewed.current_cycle.expiry_date == ~D[2027-03-15]
      assert renewed.current_cycle.dates_source == "computed"
      assert renewed.current_cycle.status_override == nil
      assert renewed.disposition_state == nil

      assert [previous] = DueItems.list_cycles(ctx.admin, renewed)
      assert previous.id == item.current_cycle.id
      assert previous.completion_type == "renewed"
      assert previous.completed_on == today
      assert previous.completed_by_user.id == ctx.user_a.user.id
      assert previous.completion_note == "Paid challan 4471"
      assert previous.reviewed_at == nil

      # Responsibility and reminders belong to the DueItem and carry over.
      assert DueItem.primary_user(renewed).id == ctx.user_a.user.id
      assert Enum.map(DueItem.additional_users(renewed), & &1.id) == [ctx.user_b.user.id]
      assert offsets(renewed) == [-7, 0]
      assert {:ok, _} = DueItems.get_due_item(ctx.user_a, item.id)

      assert actions(item) == ["due_item.created", "due_item.renewed"]
      renewal = event(item, "due_item.renewed")
      refute inspect(renewal.changes) =~ "challan"
      refute inspect(renewal.metadata) =~ "challan"
      assert renewal.changes["due_date"] == ["2027-01-31", "2027-02-28"]

      assert "#{ctx.user_a.user.name} renewed this DueItem. Next Due Date 28 Feb 2027" in sentences(
               ctx.admin,
               renewed
             )
    end

    test "a User's renewal waits for review until an Administrator dismisses it", ctx do
      item = monthly_item(ctx)
      {:ok, _} = DueItems.renew_due_item(ctx.user_a, item, %{})
      [previous] = cycles(item) |> Enum.filter(& &1.completed_at)

      assert DueItems.count_renewal_reviews(ctx.admin) == 1
      assert [%{id: id}] = DueItems.list_renewal_reviews(ctx.admin)
      assert id == previous.id
      assert DueItems.count_renewal_reviews(ctx.user_a) == 0
      assert DueItems.list_renewal_reviews(ctx.user_a) == []

      assert {:error, :unauthorized} = DueItems.dismiss_renewal_review(ctx.user_a, previous.id)
      assert {:error, :not_found} = DueItems.dismiss_renewal_review(ctx.admin, "nope")

      other = account_scope_fixture()
      assert {:error, :not_found} = DueItems.dismiss_renewal_review(other, previous.id)

      assert {:ok, reviewed} = DueItems.dismiss_renewal_review(ctx.admin, previous.id)
      assert reviewed.reviewed_by_user_id == ctx.admin.user.id
      assert DueItems.count_renewal_reviews(ctx.admin) == 0
      assert event(item, "due_item.renewal_reviewed")
      assert "#{ctx.admin.user.name} reviewed the renewal" in sentences(ctx.admin, item)
    end

    test "an Administrator's renewal needs no review", ctx do
      item = monthly_item(ctx)
      {:ok, _} = DueItems.renew_due_item(ctx.admin, item, %{})

      assert [%Cycle{reviewed_at: %DateTime{}}] = DueItems.list_cycles(ctx.admin, item)
      assert DueItems.count_renewal_reviews(ctx.admin) == 0
    end

    test "with the next date set at each renewal, uses the entered dates", ctx do
      item =
        monthly_item(ctx, %{
          recurrence: "custom",
          recurrence_unit: "explicit",
          due_date: "2027-01-31",
          expiry_date: nil
        })

      assert {:error, changeset} =
               DueItems.renew_due_item(ctx.user_a, item, %{"next_due_date" => "2027-01-15"})

      assert errors_on(changeset).next_due_date |> hd() =~ "must be after the current date"

      assert {:ok, _} =
               DueItems.renew_due_item(ctx.user_a, item, %{"next_due_date" => "2027-07-31"})

      renewed = reload(ctx.admin, item)
      assert renewed.current_cycle.sequence == 2
      assert renewed.current_cycle.due_date == ~D[2027-07-31]
      assert renewed.current_cycle.dates_source == "entered"
      assert renewed.disposition_state == nil
    end

    test "with no next date entered, the DueItem waits for an Administrator", ctx do
      item =
        monthly_item(ctx, %{recurrence: "custom", recurrence_unit: "explicit", expiry_date: nil})

      assert {:ok, _} = DueItems.renew_due_item(ctx.user_a, item, %{})

      waiting = reload(ctx.admin, item)
      assert waiting.disposition_state == "awaiting_new_dates"
      assert waiting.status == "active"
      assert waiting.current_cycle_id == item.current_cycle_id
      assert waiting.current_cycle.completion_type == "renewed"
      assert length(cycles(item)) == 1

      assert {:error, :not_found} = DueItems.get_due_item(ctx.user_a, item.id)
      assert DueItems.count_awaiting(ctx.admin) == 1
      assert DueItems.count_awaiting(ctx.user_a) == 0
      assert event(item, "due_item.renewed").metadata["next_dates"] == "pending"

      assert Enum.any?(
               sentences(ctx.admin, waiting),
               &(&1 =~ "New dates are needed from an Administrator")
             )

      assert {:ok, _} =
               DueItems.reactivate_due_item(ctx.admin, waiting, %{
                 "due_date" => "2027-07-31",
                 "primary_user_id" => ctx.user_a.user.id
               })

      active = reload(ctx.admin, item)
      assert active.disposition_state == nil
      assert active.current_cycle.sequence == 2
      assert active.current_cycle.due_date == ~D[2027-07-31]
      assert {:ok, _} = DueItems.get_due_item(ctx.user_a, item.id)
      assert DueItems.count_awaiting(ctx.admin) == 0
    end

    test "rolls back everything when the next cycle cannot be created", ctx do
      item = monthly_item(ctx)

      Repo.insert!(%Cycle{
        customer_account_id: item.customer_account_id,
        due_item_id: item.id,
        sequence: 2,
        due_date: ~D[2027-02-28]
      })

      assert {:error, :stale} = DueItems.renew_due_item(ctx.user_a, item, %{})

      unchanged = reload(ctx.admin, item)
      assert unchanged.current_cycle_id == item.current_cycle_id
      assert unchanged.current_cycle.completed_at == nil
      assert unchanged.current_cycle.completion_type == nil
      assert actions(item) == ["due_item.created"]
    end

    test "a second submit of the same form is stale", ctx do
      item = monthly_item(ctx)

      assert {:ok, _} = DueItems.renew_due_item(ctx.user_a, item, %{})
      assert {:error, :stale} = DueItems.renew_due_item(ctx.user_a, item, %{})
      assert {:error, :stale} = DueItems.renew_due_item(ctx.admin, item, %{})

      assert length(cycles(item)) == 2
      assert Enum.count(actions(item), &(&1 == "due_item.renewed")) == 1
    end

    test "validates the date it was done", ctx do
      item = monthly_item(ctx)
      tomorrow = days_from_today(ctx.owner, 1)

      assert {:error, changeset} =
               DueItems.renew_due_item(ctx.user_a, item, %{"completed_on" => tomorrow})

      assert "cannot be in the future" in errors_on(changeset).completed_on

      assert {:error, changeset} =
               DueItems.renew_due_item(ctx.user_a, item, %{"completed_on" => ""})

      assert "enter the date it was done" in errors_on(changeset).completed_on
      assert reload(ctx.admin, item).current_cycle.completed_at == nil
    end
  end

  describe "complete_due_item/3" do
    test "closes the cycle and waits for an Administrator; still counts toward the plan",
         ctx do
      item = due_item_fixture(ctx.admin, primary_user_id: ctx.user_a.user.id)

      assert {:error, :not_recurring} = DueItems.renew_due_item(ctx.user_a, item, %{})
      assert {:ok, _} = DueItems.complete_due_item(ctx.user_a, item, %{"note" => "Signed"})

      completed = reload(ctx.admin, item)
      assert completed.status == "active"
      assert completed.disposition_state == "awaiting_admin_disposition"
      assert completed.current_cycle.completion_type == "completed"
      assert completed.current_cycle.completed_by_user_id == ctx.user_a.user.id

      assert Billing.usage(ctx.owner).due_items == 1
      assert {:error, :not_found} = DueItems.get_due_item(ctx.user_a, item.id)
      assert DueItems.list_due_items(ctx.user_a) == []
      assert DueItems.count_awaiting(ctx.admin) == 1
      assert [%{id: id}] = DueItems.list_due_items(ctx.admin, %{"view" => "awaiting"})
      assert id == item.id
      refute item.id in Enum.map(DueItems.list_due_items(ctx.admin), & &1.id)

      assert {:error, :stale} = DueItems.complete_due_item(ctx.admin, item, %{})
      assert {:error, :unauthorized} = DueItems.complete_due_item(ctx.admin, completed, %{})

      assert actions(item) == ["due_item.completed", "due_item.created"]
      refute inspect(event(item, "due_item.completed").changes) =~ "Signed"

      assert "#{ctx.user_a.user.name} marked this DueItem as completed" in sentences(
               ctx.admin,
               completed
             )
    end

    test "is refused for a recurring DueItem", ctx do
      item = monthly_item(ctx)
      assert {:error, :recurring} = DueItems.complete_due_item(ctx.user_a, item, %{})
    end
  end

  describe "who may renew and complete" do
    test "only Users assigned to the DueItem, within the account", ctx do
      item = monthly_item(ctx, %{additional_user_ids: []})

      assert {:error, :unauthorized} = DueItems.renew_due_item(ctx.user_b, item, %{})

      other = account_scope_fixture()
      assert {:error, :unauthorized} = DueItems.renew_due_item(other, item, %{})

      one_off = due_item_fixture(ctx.admin, primary_user_id: ctx.user_a.user.id)
      assert {:error, :unauthorized} = DueItems.complete_due_item(ctx.user_b, one_off, %{})

      archived = due_item_fixture(ctx.admin, primary_user_id: ctx.user_a.user.id)
      {:ok, archived} = DueItems.archive_due_item(ctx.admin, archived)
      assert {:error, :unauthorized} = DueItems.complete_due_item(ctx.admin, archived, %{})

      assert actions(item) == ["due_item.created"]
    end
  end

  describe "reactivate_due_item/3" do
    test "re-dates a completed DueItem with new responsibility and reminders", ctx do
      item = due_item_fixture(ctx.admin, primary_user_id: ctx.user_a.user.id)
      {:ok, _} = DueItems.complete_due_item(ctx.user_a, item, %{})
      completed = reload(ctx.admin, item)

      assert {:error, :unauthorized} =
               DueItems.reactivate_due_item(ctx.user_a, completed, %{"due_date" => "2027-06-30"})

      assert {:error, changeset} =
               DueItems.reactivate_due_item(ctx.admin, completed, %{"due_date" => ""})

      assert errors_on(changeset) != %{}

      assert {:ok, _} =
               DueItems.reactivate_due_item(ctx.admin, completed, %{
                 "due_date" => "2027-06-30",
                 "primary_user_id" => ctx.user_b.user.id,
                 "reminder_offsets" => ["-3"]
               })

      active = reload(ctx.admin, item)
      assert active.status == "active"
      assert active.disposition_state == nil
      assert active.current_cycle.sequence == 2
      assert active.current_cycle.due_date == ~D[2027-06-30]
      assert active.current_cycle.dates_source == "entered"
      assert DueItem.primary_user(active).id == ctx.user_b.user.id
      assert offsets(active) == [-3]

      assert {:error, :not_found} = DueItems.get_due_item(ctx.user_a, item.id)
      assert {:ok, _} = DueItems.get_due_item(ctx.user_b, item.id)

      assert event(item, "due_item.reactivated")

      assert "#{ctx.admin.user.name} re-dated and reactivated this DueItem" in sentences(
               ctx.admin,
               active
             )

      assert {:error, :not_inactive} =
               DueItems.reactivate_due_item(ctx.admin, active, %{"due_date" => "2027-07-31"})
    end

    test "restoring keeps the open cycle, takes the new dates and ends an override", ctx do
      item = due_item_fixture(ctx.admin, due_date: days_from_today(ctx.owner, -3))
      {:ok, _} = DueItems.override_status(ctx.admin, item, "up_to_date", "Paid at the counter")
      {:ok, archived} = DueItems.archive_due_item(ctx.admin, reload(ctx.admin, item))

      assert {:ok, _} =
               DueItems.reactivate_due_item(ctx.admin, archived, %{"due_date" => "2027-06-30"})

      restored = reload(ctx.admin, item)
      assert restored.status == "active"
      assert restored.archived_at == nil
      assert restored.current_cycle_id == item.current_cycle_id
      assert restored.current_cycle.due_date == ~D[2027-06-30]
      assert restored.current_cycle.status_override == nil
      assert event(item, "due_item.restored")
    end

    test "a waiting DueItem reactivates at the plan limit; an archived one cannot be restored" do
      scope = account_scope_fixture()
      [one_off | _] = for _ <- 1..10, do: due_item_fixture(scope)

      {:ok, _} = DueItems.complete_due_item(scope, one_off, %{})
      assert Billing.usage(scope).due_items == 10

      assert {:ok, _} =
               DueItems.reactivate_due_item(scope, reload(scope, one_off), %{
                 "due_date" => days_from_today(scope, 60)
               })

      assert Billing.usage(scope).due_items == 10

      {:ok, archived} = DueItems.archive_due_item(scope, reload(scope, one_off))
      due_item_fixture(scope)

      assert {:error, {:limit_reached, %{limit: 10}}} =
               DueItems.reactivate_due_item(scope, archived, %{
                 "due_date" => days_from_today(scope, 60)
               })

      assert reload(scope, one_off).status == "archived"
    end

    test "a stale form is refused", ctx do
      item = due_item_fixture(ctx.admin)
      {:ok, _} = DueItems.complete_due_item(ctx.admin, item, %{})
      waiting = reload(ctx.admin, item)
      {:ok, _} = DueItems.archive_due_item(ctx.admin, waiting)

      assert {:error, :stale} =
               DueItems.reactivate_due_item(ctx.admin, waiting, %{"due_date" => "2027-06-30"})
    end
  end

  describe "archive_due_item/2 from the awaiting queue" do
    test "clears the waiting state", ctx do
      item = due_item_fixture(ctx.admin)
      {:ok, _} = DueItems.complete_due_item(ctx.admin, item, %{})

      assert {:ok, archived} = DueItems.archive_due_item(ctx.admin, reload(ctx.admin, item))
      assert archived.status == "archived"
      assert archived.disposition_state == nil
      assert DueItems.count_awaiting(ctx.admin) == 0
      assert event(item, "due_item.archived").metadata["from"] == "awaiting_admin_disposition"
    end
  end

  describe "delete_due_item/3" do
    test "a Super Admin deletes an archived DueItem after typing its title", ctx do
      item = monthly_item(ctx, %{title: "Fire NOC"})
      {:ok, _} = DueItems.renew_due_item(ctx.user_a, item, %{})
      {:ok, _} = DueItems.add_note(ctx.admin, reload(ctx.admin, item), %{"body" => "Old"})

      assert {:error, :not_archived} = DueItems.delete_due_item(ctx.owner, item, "Fire NOC")

      {:ok, archived} = DueItems.archive_due_item(ctx.admin, reload(ctx.admin, item))

      assert {:error, :unauthorized} = DueItems.delete_due_item(ctx.admin, archived, "Fire NOC")
      assert {:error, :unauthorized} = DueItems.delete_due_item(ctx.user_a, archived, "Fire NOC")

      assert {:error, :unauthorized} =
               DueItems.delete_due_item(account_scope_fixture(), archived, "Fire NOC")

      assert {:error, :confirmation_mismatch} =
               DueItems.delete_due_item(ctx.owner, archived, "Fire")

      assert {:ok, _} = DueItems.delete_due_item(ctx.owner, archived, " Fire NOC ")

      assert Repo.get(DueItem, item.id) == nil
      assert cycles(item) == []
      assert offsets(item) == []

      deleted = event(item, "due_item.deleted")
      assert deleted.metadata == %{"title" => "Fire NOC", "documents" => 0}
      assert {:error, :not_found} = DueItems.delete_due_item(ctx.owner, archived, "Fire NOC")
    end
  end

  describe "documents through the lifecycle" do
    defp documents(item),
      do: Repo.all(from d in Document, where: d.due_item_id == ^item.id, order_by: d.filename)

    test "a renewal's documents go on the new cycle as current", ctx do
      item = monthly_item(ctx)
      upload = upload_fixture(ctx.user_a, "GSTR-3B-ack.pdf")

      assert {:ok, _} = DueItems.renew_due_item(ctx.user_a, item, %{}, [upload])

      renewed = reload(ctx.admin, item)
      assert [doc] = documents(item)
      assert doc.cycle_id == renewed.current_cycle_id
      assert doc.cycle_id != item.current_cycle_id
      assert doc.role == "current"
      assert storage_used(ctx.owner) == upload.byte_size
      assert "document.uploaded" in actions(item)
    end

    test "with the next dates left for an Administrator, they go on the closed cycle", ctx do
      item =
        monthly_item(ctx, %{recurrence: "custom", recurrence_unit: "explicit", expiry_date: nil})

      upload = upload_fixture(ctx.user_a)
      assert {:ok, _} = DueItems.renew_due_item(ctx.user_a, item, %{}, [upload])

      assert [%Document{role: "completion", cycle_id: cycle_id}] = documents(item)
      assert cycle_id == item.current_cycle_id
    end

    test "completing puts them on the closed cycle as completion documents", ctx do
      item = due_item_fixture(ctx.admin, primary_user_id: ctx.user_a.user.id)
      upload = upload_fixture(ctx.user_a, "signed-contract.pdf")

      assert {:ok, _} = DueItems.complete_due_item(ctx.user_a, item, %{}, [upload])

      assert [%Document{role: "completion", cycle_id: cycle_id}] = documents(item)
      assert cycle_id == item.current_cycle_id
      assert reload(ctx.admin, item).disposition_state == "awaiting_admin_disposition"
    end

    test "a failed renewal or completion leaves no rows and removes the files", ctx do
      item =
        monthly_item(ctx, %{recurrence: "custom", recurrence_unit: "explicit", expiry_date: nil})

      upload = upload_fixture(ctx.user_a)

      assert {:error, %Ecto.Changeset{}} =
               DueItems.renew_due_item(
                 ctx.user_a,
                 item,
                 %{"next_due_date" => "2027-01-01"},
                 [upload]
               )

      refute stored?(upload.storage_key)

      {:ok, _} = DueItems.renew_due_item(ctx.user_a, monthly_item(ctx), %{})
      stale = monthly_item(ctx)
      {:ok, _} = DueItems.renew_due_item(ctx.admin, stale, %{})
      upload = upload_fixture(ctx.user_a)
      assert {:error, :stale} = DueItems.renew_due_item(ctx.user_a, stale, %{}, [upload])
      refute stored?(upload.storage_key)

      one_off = due_item_fixture(ctx.admin, primary_user_id: ctx.user_a.user.id)
      upload = upload_fixture(ctx.user_b)

      assert {:error, :unauthorized} =
               DueItems.complete_due_item(ctx.user_b, one_off, %{}, [upload])

      refute stored?(upload.storage_key)
      assert Repo.aggregate(Document, :count) == 0
      assert storage_used(ctx.owner) == 0
    end

    test "a renewal that does not fit in storage does not happen", ctx do
      item = monthly_item(ctx)
      upload = upload_fixture(ctx.user_a)
      put_storage_used(ctx.owner, Billing.plan(ctx.owner).storage_bytes)

      assert {:error, {:limit_reached, %{resource: :storage}}} =
               DueItems.renew_due_item(ctx.user_a, item, %{}, [upload])

      assert reload(ctx.admin, item).current_cycle_id == item.current_cycle_id
      refute stored?(upload.storage_key)

      # Without files the renewal still goes through.
      assert {:ok, _} = DueItems.renew_due_item(ctx.user_a, item, %{})
    end

    test "renewing twice keeps each cycle's documents", ctx do
      item = monthly_item(ctx)
      first = document_fixture(ctx.user_a, item, filename: "jan.pdf")

      {:ok, _} =
        DueItems.renew_due_item(ctx.user_a, item, %{}, [upload_fixture(ctx.user_a, "feb.pdf")])

      second = reload(ctx.admin, item)

      {:ok, _} =
        DueItems.renew_due_item(ctx.user_a, second, %{}, [upload_fixture(ctx.user_a, "mar.pdf")])

      third = reload(ctx.admin, item)

      assert [feb, jan, mar] = documents(item)
      assert jan.id == first.id and jan.cycle_id == item.current_cycle_id
      assert feb.cycle_id == second.current_cycle_id
      assert mar.cycle_id == third.current_cycle_id
      assert Enum.all?([jan, feb, mar], &stored?(&1.storage_key))
      assert length(Documents.list_documents(ctx.admin, item)) == 3
    end

    test "deleting a DueItem removes its files and frees their storage", ctx do
      item = monthly_item(ctx, %{title: "Fire NOC"})
      a = document_fixture(ctx.user_a, item, contents: "1234")
      b = document_fixture(ctx.admin, item, role: "supporting", contents: "123456")
      other = document_fixture(ctx.admin, monthly_item(ctx), contents: "12")
      assert storage_used(ctx.owner) == 12

      {:ok, archived} = DueItems.archive_due_item(ctx.admin, reload(ctx.admin, item))
      assert {:ok, _} = DueItems.delete_due_item(ctx.owner, archived, "Fire NOC")

      refute stored?(a.storage_key)
      refute stored?(b.storage_key)
      assert stored?(other.storage_key)
      assert storage_used(ctx.owner) == 2

      assert event(item, "due_item.deleted").metadata == %{
               "title" => "Fire NOC",
               "documents" => 2
             }
    end
  end
end

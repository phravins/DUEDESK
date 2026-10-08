defmodule DueDesk.NotificationsTest do
  use DueDesk.DataCase, async: true
  use Oban.Testing, repo: DueDesk.Repo

  @moduletag :capture_log

  import Ecto.Query
  import Swoosh.TestAssertions
  import DueDesk.TenancyFixtures
  import DueDesk.DueItemsFixtures
  import DueDesk.DocumentsFixtures

  alias Ecto.Multi
  alias DueDesk.{DueItems, Notifications, Repo, Tenancy}
  alias DueDesk.Audit.AuditEvent
  alias DueDesk.Notifications.Delivery

  alias DueDesk.Notifications.Workers.{
    AccountReminderWorker,
    EmailDeliveryWorker,
    ReminderScanWorker,
    StorageReconcileWorker
  }

  setup do
    owner = account_scope_fixture() |> put_plan("business")
    admin = member_scope_fixture(owner, "admin")
    user_a = member_scope_fixture(owner, "user")
    user_b = member_scope_fixture(owner, "user")
    flush_emails()

    %{
      owner: owner,
      admin: admin,
      user_a: user_a,
      user_b: user_b,
      account: owner.customer_account,
      today: Tenancy.today(owner)
    }
  end

  defp flush_emails do
    receive do
      {:email, _} -> flush_emails()
    after
      0 -> :ok
    end
  end

  # Due in 10 days; reminders 7 days before, on the day and 1 day after.
  defp item(ctx, attrs \\ %{}) do
    due_item_fixture(
      ctx.admin,
      Map.merge(
        %{
          title: "Fire NOC",
          due_date: days_from_today(ctx.owner, 10),
          reminder_offsets: ["-7", "0", "1"],
          primary_user_id: ctx.user_a.user.id,
          additional_user_ids: [ctx.user_b.user.id]
        },
        attrs
      )
    )
  end

  defp deliveries(item, kind \\ "reminder") do
    Repo.all(
      from d in Delivery,
        where: d.due_item_id == ^item.id and d.kind == ^kind,
        order_by: [asc: d.inserted_at, asc: d.user_id]
    )
  end

  defp delivery_for(item, scope, kind \\ "reminder"),
    do: Enum.find(deliveries(item, kind), &(&1.user_id == scope.user.id))

  defp send!(%Delivery{id: id}, opts \\ []),
    do: perform_job(EmailDeliveryWorker, %{delivery_id: id}, opts)

  defp status(%Delivery{id: id}), do: Repo.get!(Delivery, id).status

  defp queue(ctx, days), do: Notifications.queue_reminders(ctx.account, Date.add(ctx.today, days))

  describe "queue_reminders/2" do
    test "queues each reminder once, with its job", ctx do
      item = item(ctx)

      assert {:ok, 2} = queue(ctx, 3)
      assert {:ok, 0} = queue(ctx, 3)
      assert {:ok, 0} = queue(ctx, 4)

      rows = deliveries(item)
      assert length(rows) == 2
      assert Enum.all?(rows, &(&1.status == "pending" and &1.channel == "email"))
      assert Enum.all?(rows, &(&1.target_date == Date.add(ctx.today, 3) and not &1.escalated))

      for row <- rows,
          do: assert_enqueued(worker: EmailDeliveryWorker, args: %{delivery_id: row.id})
    end

    test "sends the reminder once, even when the job runs again", ctx do
      item = item(ctx)
      {:ok, _} = queue(ctx, 3)
      delivery = delivery_for(item, ctx.user_a)

      assert :ok = send!(delivery)
      assert status(delivery) == "sent"

      assert_email_sent(
        subject: "Fire NOC is due in 7 days (#{DueDeskWeb.Format.date(Date.add(ctx.today, 10))})"
      )

      assert :ok = send!(delivery)
      refute_email_sent()
    end

    test "escalates to Administrators and Super Admins once overdue", ctx do
      item = item(ctx)
      {:ok, _} = queue(ctx, 11)

      escalated = deliveries(item) |> Enum.filter(& &1.escalated) |> Enum.map(& &1.user_id)

      assert Enum.sort(escalated) ==
               Enum.sort([
                 ctx.user_a.user.id,
                 ctx.user_b.user.id,
                 ctx.owner.user.id,
                 ctx.admin.user.id
               ])

      :ok = send!(delivery_for(item, ctx.owner))
      assert_email_sent(fn email -> email.subject =~ "Overdue: Fire NOC was due on" end)
    end

    test "respects the email preference", ctx do
      item = item(ctx)
      ctx.user_b.membership |> Ecto.Changeset.change(notify_email: false) |> Repo.update!()

      {:ok, 1} = queue(ctx, 3)
      assert [%{user_id: user_id}] = deliveries(item)
      assert user_id == ctx.user_a.user.id
    end

    test "never touches another account", ctx do
      other = account_scope_fixture()

      other_item =
        due_item_fixture(other,
          due_date: days_from_today(other, 10),
          reminder_offsets: ["-7"],
          primary_user_id: other.user.id
        )

      _item = item(ctx)

      {:ok, 2} = queue(ctx, 3)
      assert deliveries(other_item) == []
    end

    test "after a renewal, reminders follow the new dates", ctx do
      item = item(ctx, %{recurrence: "monthly"})
      {:ok, _} = DueItems.renew_due_item(ctx.admin, item, %{})
      renewed = reload(ctx.admin, item)
      new_due = renewed.current_cycle.due_date

      assert {:ok, 0} = queue(ctx, 3)

      assert {:ok, 2} =
               Notifications.queue_reminders(ctx.account, Date.add(new_due, -7))

      assert Enum.all?(deliveries(item), &(&1.cycle_id == renewed.current_cycle_id))
    end
  end

  describe "deliver/3 re-checks before sending" do
    test "a reassigned person is skipped; the new one is reminded on the next scan", ctx do
      user_c = member_scope_fixture(ctx.owner, "user")
      flush_emails()
      item = item(ctx)
      {:ok, _} = queue(ctx, 3)
      old = delivery_for(item, ctx.user_a)

      {:ok, _} =
        DueItems.assign_due_item(ctx.admin, item, %{
          "primary_user_id" => user_c.user.id,
          "additional_user_ids" => [ctx.user_b.user.id]
        })

      assert :ok = send!(old)
      assert status(old) == "skipped"
      refute_email_sent()

      assert {:ok, 1} = queue(ctx, 3)
      assert delivery_for(item, user_c)
    end

    test "completing, renewing or archiving stops queued reminders", ctx do
      completed = item(ctx)
      renewed = item(ctx, %{recurrence: "monthly"})
      archived = item(ctx)
      {:ok, 6} = queue(ctx, 3)

      {:ok, _} = DueItems.complete_due_item(ctx.user_a, completed, %{})
      {:ok, _} = DueItems.renew_due_item(ctx.admin, renewed, %{})
      {:ok, _} = DueItems.archive_due_item(ctx.admin, archived)

      for item <- [completed, renewed, archived], delivery <- deliveries(item) do
        assert :ok = send!(delivery)
        assert status(delivery) == "skipped"
      end
    end

    test "a member who turned email off is skipped", ctx do
      item = item(ctx)
      {:ok, _} = queue(ctx, 3)
      ctx.user_a.membership |> Ecto.Changeset.change(notify_email: false) |> Repo.update!()

      delivery = delivery_for(item, ctx.user_a)
      assert :ok = send!(delivery)
      assert status(delivery) == "skipped"
    end
  end

  describe "event notices" do
    test "assignment emails the new assignees, not the person who assigned", ctx do
      item = item(ctx)
      recipients = item |> deliveries("assignment") |> Enum.map(& &1.user_id) |> Enum.sort()
      assert recipients == Enum.sort([ctx.user_a.user.id, ctx.user_b.user.id])

      :ok = send!(delivery_for(item, ctx.user_a, "assignment"))
      assert_email_sent(subject: "You are now responsible for Fire NOC")

      :ok = send!(delivery_for(item, ctx.user_b, "assignment"))
      assert_email_sent(subject: "You have been added to Fire NOC")
    end

    test "a renewal by a User asks the Administrators to review", ctx do
      item = item(ctx, %{recurrence: "monthly"})
      {:ok, _} = DueItems.renew_due_item(ctx.user_a, item, %{})

      recipients = item |> deliveries("renewal_review") |> Enum.map(& &1.user_id) |> Enum.sort()
      assert recipients == Enum.sort([ctx.owner.user.id, ctx.admin.user.id])

      :ok = send!(delivery_for(item, ctx.admin, "renewal_review"))
      assert_email_sent(subject: "Renewal to review: Fire NOC")
    end

    test "a renewal by an Administrator needs no review", ctx do
      item = item(ctx, %{recurrence: "monthly"})
      {:ok, _} = DueItems.renew_due_item(ctx.admin, item, %{})
      assert deliveries(item, "renewal_review") == []
    end

    test "a completed DueItem asks the Administrators for a decision", ctx do
      item = item(ctx)
      {:ok, _} = DueItems.complete_due_item(ctx.user_a, item, %{})

      delivery = delivery_for(item, ctx.owner, "awaiting_disposition")
      assert :ok = send!(delivery)
      assert_email_sent(subject: "Completed: Fire NOC needs your decision")
      assert length(deliveries(item, "awaiting_disposition")) == 2
    end

    test "nothing is queued when the change rolls back", ctx do
      item = item(ctx)
      before = Repo.aggregate(Delivery, :count)

      assert {:error, :boom, :failed, _} =
               Multi.new()
               |> Notifications.multi_notify(:notify, "assignment", ctx.admin, fn _ ->
                 {item, item.current_cycle_id, [{Ecto.UUID.generate(), ctx.user_a.user.id}]}
               end)
               |> Multi.error(:boom, :failed)
               |> Repo.transaction()

      assert Repo.aggregate(Delivery, :count) == before
    end
  end

  describe "workers" do
    test "the scan queues one job per active account, which queues its reminders", ctx do
      item = item(ctx, %{due_date: days_from_today(ctx.owner, 7)})

      assert :ok = perform_job(ReminderScanWorker, %{})
      assert_enqueued(worker: AccountReminderWorker, args: %{account_id: ctx.account.id})

      assert :ok = perform_job(AccountReminderWorker, %{account_id: ctx.account.id})
      assert length(deliveries(item)) == 2
    end

    test "storage reconcile corrects a drifted counter", ctx do
      put_storage_used(ctx.owner, 123_456)
      assert :ok = perform_job(StorageReconcileWorker, %{})
      assert storage_used(ctx.owner) == 0
    end
  end

  describe "list_deliveries/3 and next_reminder/2" do
    test "Administrators see the log; Users see nothing", ctx do
      item = item(ctx)
      {:ok, _} = queue(ctx, 3)

      assert length(Notifications.list_deliveries(ctx.admin, item)) == 4
      assert Notifications.list_deliveries(ctx.user_a, item) == []

      other = account_scope_fixture()
      assert Notifications.list_deliveries(other, item) == []
    end

    test "the next reminder", ctx do
      item = item(ctx)
      assert {date, "7 days before"} = Notifications.next_reminder(item, ctx.today)
      assert date == Date.add(ctx.today, 3)
    end
  end

  describe "notification preferences" do
    test "turning WhatsApp on needs consent; consent is stamped and audited", ctx do
      assert {:error, changeset} =
               Tenancy.update_notification_preferences(ctx.user_a, %{"notify_whatsapp" => "true"})

      assert "agree to WhatsApp messages first" in errors_on(changeset).whatsapp_consent

      assert {:ok, membership} =
               Tenancy.update_notification_preferences(ctx.user_a, %{
                 "notify_whatsapp" => "true",
                 "whatsapp_consent" => "true"
               })

      assert membership.notify_whatsapp
      assert membership.whatsapp_consent_at

      event =
        Repo.one!(
          from e in AuditEvent,
            where:
              e.action == "membership.notifications_changed" and e.subject_id == ^membership.id
        )

      assert event.changes["whatsapp_consent"] == [false, true]

      assert {:ok, membership} =
               Tenancy.update_notification_preferences(
                 %{ctx.user_a | membership: membership},
                 %{"notify_whatsapp" => "false", "whatsapp_consent" => "false"}
               )

      refute membership.whatsapp_consent_at
    end
  end
end

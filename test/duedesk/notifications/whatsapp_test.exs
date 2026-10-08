defmodule DueDesk.Notifications.WhatsAppTest do
  # Changes the WhatsApp adapter in the application environment.
  use DueDesk.DataCase, async: false
  use Oban.Testing, repo: DueDesk.Repo

  @moduletag :capture_log

  import Ecto.Query
  import DueDesk.TenancyFixtures
  import DueDesk.DueItemsFixtures

  alias DueDesk.{Notifications, Repo, Tenancy}
  alias DueDesk.Notifications.{Delivery, WhatsApp}
  alias DueDesk.Notifications.WhatsApp.N8n
  alias DueDesk.Notifications.Workers.WhatsAppDeliveryWorker

  @secret "test-signing-secret-not-real"

  setup do
    previous = Application.fetch_env!(:duedesk, WhatsApp)

    Application.put_env(:duedesk, WhatsApp,
      adapter: N8n,
      url: "http://n8n.test/webhook/duedesk",
      signing_secret: @secret,
      req_options: [plug: {Req.Test, __MODULE__}]
    )

    on_exit(fn -> Application.put_env(:duedesk, WhatsApp, previous) end)

    owner = account_scope_fixture() |> put_plan("business")
    user = member_scope_fixture(owner, "user")

    user.membership
    |> Ecto.Changeset.change(
      notify_whatsapp: true,
      whatsapp_consent_at: DateTime.utc_now(:second)
    )
    |> Repo.update!()

    item =
      due_item_fixture(owner,
        title: "Fire NOC",
        due_date: days_from_today(owner, 10),
        reminder_offsets: ["-7"],
        primary_user_id: user.user.id
      )

    {:ok, 2} =
      Notifications.queue_reminders(owner.customer_account, Date.add(Tenancy.today(owner), 3))

    delivery =
      Repo.one!(from d in Delivery, where: d.due_item_id == ^item.id and d.channel == "whatsapp")

    %{owner: owner, user: user, item: item, delivery: delivery}
  end

  defp send!(delivery, opts \\ []),
    do: perform_job(WhatsAppDeliveryWorker, %{delivery_id: delivery.id}, opts)

  defp reload_delivery(delivery), do: Repo.get!(Delivery, delivery.id)

  test "queues WhatsApp next to email for a member who opted in", %{delivery: delivery} do
    assert delivery.status == "pending"
    assert_enqueued(worker: WhatsAppDeliveryWorker, args: %{delivery_id: delivery.id})
  end

  test "posts a signed request without the secret", %{delivery: delivery, user: user} do
    test_pid = self()

    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      [signature] = Plug.Conn.get_req_header(conn, "x-duedesk-signature")
      send(test_pid, {:webhook, body, signature})
      Req.Test.json(conn, %{"ok" => true})
    end)

    assert :ok = send!(delivery)
    assert reload_delivery(delivery).status == "sent"

    assert_received {:webhook, body, signature}
    ["t=" <> timestamp, _] = String.split(signature, ",")
    assert signature == N8n.signature(timestamp, body, @secret)
    refute body =~ @secret

    payload = Jason.decode!(body)
    assert payload["delivery_id"] == delivery.id
    assert payload["template"] == "duedesk_reminder"
    assert payload["to"] == user.user.mobile_number
    assert payload["title"] == "Fire NOC"
    assert payload["days"] == 7
  end

  test "a failure is retried, then marked failed; the DueItem is unchanged", ctx do
    Req.Test.stub(__MODULE__, &Plug.Conn.send_resp(&1, 500, "error"))

    assert {:error, "http_500"} = send!(ctx.delivery, attempt: 1)
    assert %{status: "pending", error: "http_500", attempts: 1} = reload_delivery(ctx.delivery)

    Req.Test.stub(__MODULE__, &Req.Test.transport_error(&1, :timeout))
    assert {:error, "timeout"} = send!(ctx.delivery, attempt: 5)
    assert %{status: "failed", error: "timeout", attempts: 5} = reload_delivery(ctx.delivery)

    after_failure = reload(ctx.owner, ctx.item)
    assert after_failure.status == ctx.item.status
    assert after_failure.current_cycle_id == ctx.item.current_cycle_id
    assert after_failure.current_cycle.status_override == nil
  end

  test "withdrawn consent skips a queued message", ctx do
    {:ok, _} =
      Tenancy.update_notification_preferences(ctx.user, %{
        "notify_email" => "true",
        "notify_whatsapp" => "false",
        "whatsapp_consent" => "false"
      })

    assert :ok = send!(ctx.delivery)
    assert reload_delivery(ctx.delivery).status == "skipped"
  end

  test "masks mobile numbers" do
    assert WhatsApp.mask("+919876543210") == "******3210"
  end
end

defmodule DueDesk.Notifications do
  @moduledoc """
  Reminders and event notices by Email and WhatsApp.

  Every message is a `DueDesk.Notifications.Delivery` row created together
  with the job that sends it, in one transaction. Its unique `dedupe_key`
  makes each reminder go out at most once per person and channel,
  however often the scan runs, a job retries or two nodes overlap.

  Before sending, a job checks the message still makes sense: the
  DueItem is still live and on the same cycle, the person is still
  responsible (or still an Administrator, for escalations) and still
  wants the channel. Otherwise the delivery is `skipped`. So renewing,
  completing, archiving or reassigning a DueItem stops reminders that
  were already queued. A failed delivery never changes a DueItem.

  Reminders come from `DueDesk.Notifications.Reminders` and go to the
  people chosen by `DueDesk.Notifications.Recipients`. Event notices
  (assignment, renewal to review, completed DueItem awaiting a decision)
  are added to the transaction of the change with `multi_notify/5`, so
  they are only queued if the change commits.
  """

  import Ecto.Query, warn: false

  require Logger

  alias Ecto.Multi
  alias DueDesk.{Mailer, Permissions, Repo, Tenancy}
  alias DueDesk.Accounts.Scope
  alias DueDesk.DueItems.{Cycle, DueItem, ReminderRule}
  alias DueDesk.Notifications.{Delivery, Email, Recipients, Reminders, WhatsApp}
  alias DueDesk.Notifications.Workers.{EmailDeliveryWorker, WhatsAppDeliveryWorker}
  alias DueDesk.Tenancy.{CustomerAccount, Membership}

  @event_kinds ~w(assignment renewal_review awaiting_disposition)

  ## Reminders

  @doc """
  Queues the reminders of the account that fall due by `today` (the
  account's today by default). Returns `{:ok, queued}`; reminders queued
  by an earlier run are not counted again.
  """
  def queue_reminders(%CustomerAccount{} = account, today \\ nil) do
    today = today || Tenancy.today(account)
    members = Recipients.members(account.id)
    now = DateTime.utc_now(:second)

    rows =
      for occ <- Reminders.occurrences(account, today),
          user_id <- Recipients.resolve(occ.item, occ.escalated, members),
          channel <- Recipients.channels(members[user_id]) do
        %{
          id: Ecto.UUID.generate(),
          customer_account_id: account.id,
          user_id: user_id,
          due_item_id: occ.item.id,
          cycle_id: occ.cycle.id,
          reminder_rule_id: occ.rule.id,
          kind: "reminder",
          channel: channel,
          target_date: occ.target_date,
          offset_days: occ.offset_days,
          escalated: occ.escalated,
          status: "pending",
          attempts: 0,
          dedupe_key:
            Enum.join(
              ["reminder", occ.cycle.id, occ.rule.id, occ.target_date, user_id, channel],
              ":"
            ),
          inserted_at: now,
          updated_at: now
        }
      end

    Repo.transaction(fn -> insert_and_enqueue(rows) end)
  end

  @doc """
  Adds an event notice to `multi` under `name`. `fun` receives the
  changes so far and returns `{item, cycle_id, [{ref, user_id}]}`, or nil
  for nothing to send; `ref` identifies the event (an assignment or a
  cycle) so the same notice is never queued twice.

  Event notices go by email only, to active members who want email, and
  never to the person who made the change.
  """
  def multi_notify(%Multi{} = multi, name, kind, %Scope{} = scope, fun)
      when kind in @event_kinds do
    Multi.run(multi, name, fn _repo, changes ->
      case fun.(changes) do
        nil ->
          {:ok, 0}

        {%DueItem{} = item, cycle_id, refs} ->
          members = Recipients.members(item.customer_account_id)
          now = DateTime.utc_now(:second)

          rows =
            for {ref, user_id} <- Enum.uniq_by(refs, &elem(&1, 1)),
                user_id != scope.user.id,
                match?(%Membership{notify_email: true}, members[user_id]) do
              %{
                id: Ecto.UUID.generate(),
                customer_account_id: item.customer_account_id,
                user_id: user_id,
                due_item_id: item.id,
                cycle_id: cycle_id,
                kind: kind,
                channel: "email",
                status: "pending",
                attempts: 0,
                dedupe_key: Enum.join([kind, ref, user_id, "email"], ":"),
                inserted_at: now,
                updated_at: now
              }
            end

          {:ok, insert_and_enqueue(rows)}
      end
    end)
  end

  @doc "User ids of the account's active Administrators and Super Admins."
  def admin_ids(account_id), do: account_id |> Recipients.members() |> Recipients.admins()

  # Rows whose dedupe key exists are ignored; only new rows get a job.
  defp insert_and_enqueue(rows) do
    rows
    |> Enum.chunk_every(1_000)
    |> Enum.reduce(0, fn chunk, count ->
      {_, inserted} =
        Repo.insert_all(Delivery, chunk,
          on_conflict: :nothing,
          conflict_target: :dedupe_key,
          returning: [:id, :channel]
        )

      inserted
      |> Enum.map(fn
        %Delivery{id: id, channel: "email"} -> EmailDeliveryWorker.new(%{delivery_id: id})
        %Delivery{id: id, channel: "whatsapp"} -> WhatsAppDeliveryWorker.new(%{delivery_id: id})
      end)
      |> Oban.insert_all()

      count + length(inserted)
    end)
  end

  ## Sending

  @doc """
  Sends a pending delivery, or marks it `skipped` when it no longer
  applies. On failure the delivery stays pending with the error code
  until `attempt` reaches `max_attempts`, then becomes `failed`.

  Returns `:ok` or `{:error, code}` (so the job is retried).
  """
  def deliver(delivery_id, attempt, max_attempts) do
    case load_delivery(delivery_id) do
      %Delivery{status: "pending"} = delivery ->
        if relevant?(delivery) do
          delivery |> transmit() |> record(delivery, attempt, max_attempts)
        else
          finish(delivery, status: "skipped", attempts: attempt)
          :ok
        end

      # Already handled, or deleted with its DueItem.
      _ ->
        :ok
    end
  end

  defp load_delivery(id) do
    from(d in Delivery,
      where: d.id == ^id,
      preload: [
        :user,
        cycle: [:completed_by_user],
        due_item: [
          :organisation,
          :current_cycle,
          :active_assignments,
          reminder_rules: ^from(r in ReminderRule, where: r.active)
        ]
      ]
    )
    |> Repo.one()
  end

  defp relevant?(%Delivery{due_item: nil}), do: false
  defp relevant?(%Delivery{cycle: nil}), do: false

  defp relevant?(%Delivery{} = delivery) do
    case membership(delivery) do
      %Membership{} = membership ->
        wants?(membership, delivery.channel) and still_applies?(delivery, membership)

      nil ->
        false
    end
  end

  defp membership(%Delivery{customer_account_id: account_id, user: user}) do
    from(m in Membership,
      join: a in assoc(m, :customer_account),
      where:
        m.customer_account_id == ^account_id and m.user_id == ^user.id and
          m.status == "active" and a.status == "active"
    )
    |> Repo.one()
    |> then(&(&1 && %{&1 | user: user}))
  end

  defp wants?(membership, "email"), do: membership.notify_email
  defp wants?(membership, "whatsapp"), do: Recipients.whatsapp?(membership)

  defp still_applies?(%Delivery{kind: "reminder", due_item: item} = delivery, membership) do
    offsets = Enum.map(item.reminder_rules, & &1.offset_days)

    live?(item) and item.current_cycle_id == delivery.cycle_id and
      not Cycle.closed?(item.current_cycle) and
      (assigned?(item, delivery.user_id) or (delivery.escalated and admin?(membership))) and
      Reminders.targets(item.current_cycle, offsets, delivery.target_date, delivery.target_date) !=
        []
  end

  defp still_applies?(%Delivery{kind: "assignment", due_item: item} = delivery, _membership),
    do: live?(item) and assigned?(item, delivery.user_id)

  defp still_applies?(%Delivery{kind: "renewal_review", cycle: cycle}, membership),
    do: admin?(membership) and is_nil(cycle.reviewed_at)

  defp still_applies?(%Delivery{kind: "awaiting_disposition", due_item: item}, membership),
    do: admin?(membership) and item.status == "active" and not is_nil(item.disposition_state)

  defp live?(%DueItem{status: status, disposition_state: state}),
    do: status == "active" and is_nil(state)

  defp assigned?(%DueItem{active_assignments: assignments}, user_id),
    do: Enum.any?(assignments, &(&1.user_id == user_id))

  defp admin?(%Membership{role: role}), do: role in ["admin", "super_admin"]

  defp transmit(%Delivery{channel: "email"} = delivery) do
    case delivery |> Email.build() |> Mailer.deliver() do
      {:ok, _} -> :ok
      {:error, {status, _}} when is_integer(status) -> {:error, "http_#{status}"}
      {:error, _} -> {:error, "email_failed"}
    end
  end

  defp transmit(%Delivery{channel: "whatsapp"} = delivery) do
    delivery |> Email.whatsapp_payload() |> WhatsApp.deliver()
  end

  defp record(:ok, delivery, attempt, _max) do
    finish(delivery, status: "sent", attempts: attempt, error: nil, sent_at: now())
    Logger.info("Notification #{delivery.id} sent by #{delivery.channel}")
    :ok
  end

  defp record({:error, code}, delivery, attempt, max) do
    status = if attempt >= max, do: "failed", else: "pending"
    finish(delivery, status: status, attempts: attempt, error: String.slice(code, 0, 64))

    Logger.warning(
      "Notification #{delivery.id} by #{delivery.channel} failed (#{code}), attempt #{attempt} of #{max}"
    )

    {:error, code}
  end

  defp finish(%Delivery{id: id}, fields) do
    Repo.update_all(from(d in Delivery, where: d.id == ^id),
      set: Keyword.put(fields, :updated_at, now())
    )
  end

  defp now, do: DateTime.utc_now(:second)

  ## Display

  @doc """
  The latest deliveries for a DueItem, newest first, with recipients.
  Administrators and Super Admins only; others get an empty list.
  """
  def list_deliveries(%Scope{} = scope, %DueItem{} = item, limit \\ 20) do
    if Permissions.admin?(scope) do
      account_id = Scope.account_id!(scope)

      from(d in Delivery,
        where: d.customer_account_id == ^account_id and d.due_item_id == ^item.id,
        order_by: [desc: d.inserted_at, desc: d.target_date],
        limit: ^limit,
        preload: [:user]
      )
      |> Repo.all()
    else
      []
    end
  end

  @doc """
  The next reminder of a DueItem (with current cycle and reminder rules
  loaded) after `today`: `{date, label}` or nil.
  """
  def next_reminder(%DueItem{} = item, %Date{} = today) do
    offsets = for %ReminderRule{active: true, offset_days: d} <- item.reminder_rules, do: d

    case Reminders.next(item, item.current_cycle, offsets, today) do
      nil -> nil
      {date, _offset, true} -> {date, "weekly while overdue"}
      {date, offset, false} -> {date, ReminderRule.describe(offset)}
    end
  end

  @doc "Whether WhatsApp messages can be sent in this installation."
  defdelegate whatsapp_available?, to: WhatsApp, as: :enabled?
end

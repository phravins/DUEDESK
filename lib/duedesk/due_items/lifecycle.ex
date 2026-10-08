defmodule DueDesk.DueItems.Lifecycle do
  @moduledoc """
  What happens to a DueItem over time (Product Definition §8):

    * a recurring DueItem is **renewed**: its cycle closes and the next
      one starts with dates counted from the previous ones;
    * a one-off DueItem is **completed**: it leaves Users' lists and
      waits for an Administrator, who **archives** it or **re-dates and
      reactivates** it;
    * an archived DueItem is **restored** after a review of its dates,
      responsibility and reminders;
    * Administrators **review** renewals made by Users;
    * a Super Admin may **permanently delete** an archived DueItem.

  Called through `DueDesk.DueItems`. Every write locks the DueItem row and
  checks it is still as the caller loaded it, so a double submit or two
  people acting at once cannot close a cycle twice: the second gets
  `{:error, :stale}`. Completion notes are the person's own text and never
  go into audit events.
  """

  import Ecto.Query, warn: false

  import DueDesk.DueItems.Steps,
    only: [
      lock_account: 2,
      check_limit: 1,
      replace_reminders: 3,
      assignment_plan: 3,
      apply_assignment_plan: 4,
      validate_assignees: 2,
      authorize: 1,
      same_account: 2,
      iso: 1
    ]

  alias Ecto.Changeset
  alias Ecto.Multi
  alias DueDesk.{Audit, Documents, DueItems, Permissions, Repo, Tenancy}
  alias DueDesk.Accounts.Scope
  alias DueDesk.DueItems.{Completion, Cycle, DueItem, Recurrence, ReminderRule}

  ## Renew and complete

  @doc """
  Returns a changeset for the renew and complete forms. The completion
  date defaults to today in the account timezone.
  """
  def change_completion(%Scope{} = scope, %DueItem{} = item, attrs \\ %{}) do
    today = Tenancy.today(scope)

    Completion.changeset(%Completion{completed_on: today}, attrs,
      today: today,
      cycle: item.current_cycle,
      explicit: Recurrence.interval(item) == :explicit
    )
  end

  @doc """
  The dates the next cycle of a recurring DueItem would get. See
  `DueDesk.DueItems.Recurrence.next_dates/2`.
  """
  def next_dates(%Scope{} = scope, %DueItem{} = item) do
    account_id = Scope.account_id!(scope)

    cycles =
      Repo.all(
        from(c in Cycle,
          where: c.due_item_id == ^item.id and c.customer_account_id == ^account_id
        )
      )

    case cycles do
      [] -> :none
      cycles -> Recurrence.next_dates(item, cycles)
    end
  end

  @doc """
  Renews a recurring DueItem: closes its current cycle and starts the
  next one with the next dates. When the next date is set at each renewal
  and none was entered, no cycle starts: the DueItem waits for an
  Administrator to set the dates.

  Anyone who can see the DueItem may renew it while it is active. A
  renewal by a User is queued for an Administrator's review.

  `uploads` (from `DueDesk.Documents.prepare_upload/2`) go on the new
  cycle as its current documents, or, when no cycle starts yet, on the
  closed cycle as completion documents. They are removed from storage
  again if the renewal fails.

  Returns `{:ok, item}`, `{:error, changeset}`, `{:error, :stale}`,
  `{:error, {:limit_reached, info}}`, `{:error, :not_recurring}` or
  `{:error, :unauthorized}`.
  """
  def renew_due_item(%Scope{} = scope, %DueItem{} = item, attrs, uploads \\ []) do
    scope
    |> do_renew(item, attrs, uploads)
    |> Documents.discard_on_error(uploads)
  end

  defp do_renew(scope, item, attrs, uploads) do
    with {:ok, fresh} <- actionable(scope, item),
         :ok <- if(Recurrence.recurring?(fresh), do: :ok, else: {:error, :not_recurring}),
         {:ok, completion} <- apply_completion(scope, fresh, attrs) do
      explicit? = Recurrence.interval(fresh) == :explicit
      pending? = explicit? and not Completion.next_dates?(completion)

      Multi.new()
      |> lock_item(scope, fresh)
      |> Multi.update(:closed, fn %{locked: locked} ->
        close_changeset(scope, locked.current_cycle, completion, "renewed")
      end)
      |> Multi.run(:cycle, fn repo, %{locked: locked} ->
        cond do
          pending? ->
            {:ok, nil}

          explicit? ->
            insert_cycle(repo, locked, Completion.next_dates(completion), "entered")

          true ->
            cycles = repo.all(from(c in Cycle, where: c.due_item_id == ^locked.id))
            {:ok, dates} = Recurrence.next_dates(locked, cycles)
            insert_cycle(repo, locked, dates, "computed")
        end
      end)
      |> Multi.update(:item, fn %{locked: locked, cycle: cycle} ->
        changes =
          if cycle,
            do: [current_cycle_id: cycle.id],
            else: [disposition_state: "awaiting_new_dates"]

        Changeset.change(locked, [{:updated_at, DateTime.utc_now(:second)} | changes])
      end)
      |> then(fn multi ->
        if pending?,
          do: Documents.multi_attach(multi, scope, fresh, & &1.closed, "completion", uploads),
          else: Documents.multi_attach(multi, scope, fresh, & &1.cycle, "current", uploads)
      end)
      |> Audit.multi_log(:audit, scope, "due_item.renewed", fresh,
        changes: fn %{locked: locked, cycle: cycle} ->
          %{"completed_on" => [nil, iso(completion.completed_on)]}
          |> Map.merge(date_changes(locked.current_cycle, cycle))
        end,
        metadata: if(pending?, do: %{"next_dates" => "pending"}, else: %{})
      )
      |> Repo.transaction()
      |> lifecycle_result()
    end
  end

  @doc """
  Completes a DueItem that does not repeat. Its cycle closes and it waits
  for an Administrator to archive it or re-date and reactivate it; until
  then Users no longer see it, but it still counts toward the plan.

  `uploads` go on the closed cycle as completion documents, and are
  removed from storage again if completing fails.

  Returns `{:ok, item}`, `{:error, changeset}`, `{:error, :stale}`,
  `{:error, {:limit_reached, info}}`, `{:error, :recurring}` or
  `{:error, :unauthorized}`.
  """
  def complete_due_item(%Scope{} = scope, %DueItem{} = item, attrs, uploads \\ []) do
    scope
    |> do_complete(item, attrs, uploads)
    |> Documents.discard_on_error(uploads)
  end

  defp do_complete(scope, item, attrs, uploads) do
    with {:ok, fresh} <- actionable(scope, item),
         :ok <- if(Recurrence.recurring?(fresh), do: {:error, :recurring}, else: :ok),
         {:ok, completion} <- apply_completion(scope, fresh, attrs) do
      Multi.new()
      |> lock_item(scope, fresh)
      |> Multi.update(:closed, fn %{locked: locked} ->
        close_changeset(scope, locked.current_cycle, completion, "completed")
      end)
      |> Multi.update(:item, fn %{locked: locked} ->
        Changeset.change(locked,
          disposition_state: "awaiting_admin_disposition",
          updated_at: DateTime.utc_now(:second)
        )
      end)
      |> Documents.multi_attach(scope, fresh, & &1.closed, "completion", uploads)
      |> Audit.multi_log(:audit, scope, "due_item.completed", fresh,
        changes: %{"completed_on" => [nil, iso(completion.completed_on)]}
      )
      |> Repo.transaction()
      |> lifecycle_result()
    end
  end

  # Reloads the item as the scope sees it, checks it has not moved on
  # since the caller loaded it and that the scope may act on it.
  defp actionable(scope, %DueItem{} = item) do
    case DueItems.get_due_item(scope, item.id) do
      {:ok, fresh} ->
        cond do
          not unchanged?(item, fresh) -> {:error, :stale}
          Permissions.can_act_on_due_item?(scope, fresh) -> {:ok, fresh}
          true -> {:error, :unauthorized}
        end

      {:error, :not_found} ->
        {:error, :unauthorized}
    end
  end

  defp unchanged?(item, fresh) do
    item.current_cycle_id == fresh.current_cycle_id and item.status == fresh.status and
      item.disposition_state == fresh.disposition_state
  end

  defp apply_completion(scope, item, attrs) do
    scope |> change_completion(item, attrs) |> Changeset.apply_action(:insert)
  end

  defp close_changeset(scope, cycle, %Completion{} = completion, type) do
    now = DateTime.utc_now(:second)
    # Nothing to review when an Administrator renews.
    reviewed? = type == "renewed" and Permissions.can_manage_due_items?(scope)

    Changeset.change(cycle,
      completed_at: now,
      completed_by_user_id: scope.user.id,
      completed_on: completion.completed_on,
      completion_note: completion.note,
      completion_type: type,
      reviewed_at: if(reviewed?, do: now),
      reviewed_by_user_id: if(reviewed?, do: scope.user.id)
    )
  end

  defp insert_cycle(repo, %DueItem{current_cycle: current} = item, dates, source) do
    %Cycle{
      customer_account_id: item.customer_account_id,
      due_item_id: item.id,
      sequence: current.sequence + 1,
      dates_source: source
    }
    |> Changeset.change(Map.take(dates, [:start_date, :due_date, :expiry_date]))
    |> Changeset.unique_constraint([:due_item_id, :sequence])
    |> repo.insert()
  end

  defp date_changes(_previous, nil), do: %{}

  defp date_changes(previous, %Cycle{} = next) do
    [:start_date, :due_date, :expiry_date]
    |> Enum.map(&{Atom.to_string(&1), previous && Map.get(previous, &1), Map.get(next, &1)})
    |> Enum.reject(fn {_field, old, new} -> old == new end)
    |> Map.new(fn {field, old, new} -> {field, [iso(old), iso(new)]} end)
  end

  # Locks the DueItem row and checks it, and its current cycle, are as the
  # caller loaded them. The locked item carries the current cycle.
  defp lock_item(multi, scope, %DueItem{} = item) do
    account_id = Scope.account_id!(scope)
    expected_completed_at = item.current_cycle && item.current_cycle.completed_at

    Multi.run(multi, :locked, fn repo, _ ->
      locked =
        repo.one(
          from(i in DueItem,
            where: i.id == ^item.id and i.customer_account_id == ^account_id,
            lock: "FOR UPDATE"
          )
        )

      cycle = locked && locked.current_cycle_id && repo.get(Cycle, locked.current_cycle_id)

      if locked && cycle && unchanged?(item, locked) &&
           cycle.completed_at == expected_completed_at do
        {:ok, %{locked | current_cycle: cycle}}
      else
        {:error, :stale}
      end
    end)
  end

  defp lifecycle_result(result) do
    case result do
      {:ok, %{item: item}} -> {:ok, item}
      {:error, :limit, reason, _} -> {:error, reason}
      {:error, :locked, :stale, _} -> {:error, :stale}
      # Another request started the same cycle first.
      {:error, :cycle, %Changeset{}, _} -> {:error, :stale}
      {:error, :storage_lock, :not_found, _} -> {:error, :unauthorized}
      {:error, :storage_lock, reason, _} -> {:error, reason}
    end
  end

  ## Re-date, reactivate and restore

  @doc """
  Loads what the reactivate form starts from: the current cycle's dates
  when it is still open (blank once it is closed), the active
  assignments and the active reminders.
  """
  def prepare_reactivate(%DueItem{} = item) do
    item = Repo.preload(item, [:current_cycle, :reminder_rules, active_assignments: :user])
    cycle = item.current_cycle
    open = if cycle && not Cycle.closed?(cycle), do: cycle, else: %Cycle{}

    %{
      item
      | start_date: open.start_date,
        due_date: open.due_date,
        expiry_date: open.expiry_date,
        primary_user_id: item |> DueItem.primary_user() |> then(&(&1 && &1.id)),
        additional_user_ids: Enum.map(DueItem.additional_users(item), & &1.id),
        reminder_offsets:
          for(%ReminderRule{active: true, offset_days: d} <- item.reminder_rules, do: d)
          |> Enum.sort()
    }
  end

  @doc "Returns a changeset for the reactivate form, from a prepared item."
  def change_reactivation(%Scope{} = scope, %DueItem{} = item, attrs \\ %{}) do
    item
    |> DueItem.reactivate_changeset(attrs)
    |> validate_assignees(scope)
  end

  @doc """
  Makes a DueItem active again with the dates, responsibility and
  reminders in `attrs`: one waiting for an Administrator (completed, or
  renewed without next dates), or an archived one. When its cycle is
  closed a new cycle starts; otherwise the open cycle takes the new dates
  and loses any status override. Administrators and Super Admins only.

  Restoring an archived DueItem needs room in the plan; one that is
  waiting already counts.

  Returns `{:ok, item}`, `{:error, changeset}`,
  `{:error, {:limit_reached, info}}`, `{:error, :stale}`,
  `{:error, :not_inactive}` or `{:error, :unauthorized}`.
  """
  def reactivate_due_item(%Scope{} = scope, %DueItem{} = item, attrs) do
    with :ok <- authorize(Permissions.can_manage_due_items?(scope)),
         :ok <- same_account(scope, item),
         {:ok, fresh} <- reload(scope, item),
         :ok <- if(unchanged?(item, fresh), do: :ok, else: {:error, :stale}),
         :ok <- reactivatable(fresh) do
      archived? = fresh.status == "archived"
      prepared = prepare_reactivate(fresh)
      changeset = change_reactivation(scope, prepared, attrs)

      case Changeset.apply_action(changeset, :update) do
        {:ok, wanted} -> reactivate(scope, prepared, wanted, archived?)
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  defp reload(scope, item) do
    case DueItems.get_due_item(scope, item.id) do
      {:ok, fresh} -> {:ok, fresh}
      {:error, :not_found} -> {:error, :unauthorized}
    end
  end

  defp reactivatable(%DueItem{status: "archived"}), do: :ok
  defp reactivatable(%DueItem{disposition_state: state}) when is_binary(state), do: :ok
  defp reactivatable(%DueItem{}), do: {:error, :not_inactive}

  defp reactivate(scope, prepared, wanted, archived?) do
    plan = assignment_plan(prepared, wanted.primary_user_id, wanted.additional_user_ids)
    {_to_end, _new_rows, assignment_changes} = plan
    dates = Map.take(wanted, [:start_date, :due_date, :expiry_date])
    offsets = wanted.reminder_offsets

    reminder_changes =
      if offsets != prepared.reminder_offsets,
        do: %{"reminders" => [prepared.reminder_offsets, offsets]},
        else: %{}

    Multi.new()
    |> then(fn multi ->
      if archived?,
        do:
          multi
          |> lock_account(scope)
          |> Multi.run(:limit, fn _repo, _ -> check_limit(scope) end),
        else: multi
    end)
    |> lock_item(scope, prepared)
    |> Multi.run(:cycle, fn repo, %{locked: locked} ->
      if Cycle.closed?(locked.current_cycle) do
        insert_cycle(repo, locked, dates, "entered")
      else
        locked.current_cycle
        |> Cycle.clear_override_changeset()
        |> Changeset.change(Map.put(dates, :dates_source, "entered"))
        |> repo.update()
      end
    end)
    |> Multi.update(:item, fn %{locked: locked, cycle: cycle} ->
      Changeset.change(locked,
        status: "active",
        disposition_state: nil,
        archived_at: nil,
        archived_by_user_id: nil,
        current_cycle_id: cycle.id,
        updated_at: DateTime.utc_now(:second)
      )
    end)
    |> Multi.run(:reminders, fn repo, _ -> replace_reminders(repo, prepared, offsets) end)
    |> apply_assignment_plan(scope, prepared, plan)
    |> Audit.multi_log(
      :audit,
      scope,
      if(archived?, do: "due_item.restored", else: "due_item.reactivated"),
      prepared,
      changes: fn %{locked: locked, cycle: cycle} ->
        locked.current_cycle
        |> date_changes(cycle)
        |> Map.merge(assignment_changes)
        |> Map.merge(reminder_changes)
      end,
      metadata: if(archived?, do: %{}, else: %{"from" => prepared.disposition_state})
    )
    |> Repo.transaction()
    |> lifecycle_result()
  end

  ## Renewal reviews

  @doc """
  Marks a User's renewal as reviewed, taking it off the Renewal reviews
  queue. Administrators and Super Admins only.
  """
  def dismiss_renewal_review(%Scope{} = scope, cycle_id) do
    with :ok <- authorize(Permissions.can_manage_due_items?(scope)),
         {:ok, cycle} <- renewed_cycle(scope, cycle_id) do
      if cycle.reviewed_at do
        {:ok, cycle}
      else
        now = DateTime.utc_now(:second)

        Multi.new()
        |> Multi.update(
          :cycle,
          Changeset.change(cycle, reviewed_at: now, reviewed_by_user_id: scope.user.id)
        )
        |> Audit.multi_log(:audit, scope, "due_item.renewal_reviewed", cycle.due_item,
          metadata: %{"cycle" => cycle.sequence}
        )
        |> Repo.transaction()
        |> case do
          {:ok, %{cycle: cycle}} -> {:ok, cycle}
        end
      end
    end
  end

  defp renewed_cycle(scope, cycle_id) do
    account_id = Scope.account_id!(scope)

    with {:ok, id} <- Ecto.UUID.cast(cycle_id),
         %Cycle{} = cycle <-
           Repo.one(
             from(c in Cycle,
               where:
                 c.id == ^id and c.customer_account_id == ^account_id and
                   c.completion_type == "renewed",
               preload: :due_item
             )
           ) do
      {:ok, cycle}
    else
      _ -> {:error, :not_found}
    end
  end

  ## Permanent delete

  @doc """
  Permanently deletes an archived DueItem with its cycles, assignments,
  reminders, notes and documents. `confirmation` must be the DueItem's
  title. The documents' storage is released in the same transaction and
  their files are removed after it commits. The audit event keeps only
  the title and the number of documents. Super Admin only.

  Returns `{:ok, item}`, `{:error, :not_archived}`,
  `{:error, :confirmation_mismatch}`, `{:error, :not_found}` or
  `{:error, :unauthorized}`.
  """
  def delete_due_item(%Scope{} = scope, %DueItem{} = item, confirmation) do
    account_id = Scope.account_id!(scope)

    with :ok <- authorize(Permissions.can_delete_due_item?(scope)),
         :ok <- same_account(scope, item),
         %DueItem{} = fresh <-
           Repo.one(
             from(i in DueItem, where: i.id == ^item.id and i.customer_account_id == ^account_id)
           ) || {:error, :not_found},
         :ok <- if(fresh.status == "archived", do: :ok, else: {:error, :not_archived}),
         :ok <- confirm_title(fresh, confirmation) do
      Multi.new()
      |> Documents.multi_release(fresh)
      |> Multi.delete(:item, fresh, stale_error_field: :id)
      |> Audit.multi_log(:audit, scope, "due_item.deleted", fresh,
        metadata: fn %{released_documents: released} ->
          %{"title" => fresh.title, "documents" => released.count}
        end
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{item: item, released_documents: released}} ->
          Documents.remove_objects(released.keys)
          {:ok, item}

        {:error, :item, _changeset, _} ->
          {:error, :not_found}
      end
    end
  end

  defp confirm_title(%DueItem{title: title}, confirmation) when is_binary(confirmation) do
    if String.trim(confirmation) == title, do: :ok, else: {:error, :confirmation_mismatch}
  end

  defp confirm_title(_item, _confirmation), do: {:error, :confirmation_mismatch}
end

defmodule DueDesk.DueItems.Steps do
  @moduledoc false
  # Building blocks shared by `DueDesk.DueItems` and
  # `DueDesk.DueItems.Lifecycle`: account locking, limit checks, reminder
  # and assignment rows, and the permission helpers.

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias DueDesk.{Billing, Repo}
  alias DueDesk.Accounts.Scope
  alias DueDesk.DueItems.{Assignment, DueItem, ReminderRule}
  alias DueDesk.Tenancy.{CustomerAccount, Membership}

  @doc """
  Serialises limit checks for one account, so two requests cannot both
  add the last allowed DueItem.
  """
  def lock_account(multi, scope) do
    account_id = Scope.account_id!(scope)

    Multi.run(multi, :lock, fn repo, _ ->
      from(a in CustomerAccount, where: a.id == ^account_id, lock: "FOR UPDATE", select: a.id)
      |> repo.one()
      |> case do
        nil -> {:error, :not_found}
        id -> {:ok, id}
      end
    end)
  end

  def check_limit(scope) do
    with :ok <- Billing.check(scope, :due_item), do: {:ok, :within_limit}
  end

  @doc "Turns reminders off rather than deleting them, so a rule keeps its id."
  def replace_reminders(repo, item, offsets) do
    now = DateTime.utc_now(:second)

    {_, _} =
      repo.update_all(
        from(r in ReminderRule,
          where: r.due_item_id == ^item.id and r.offset_days not in ^offsets and r.active
        ),
        set: [active: false, updated_at: now]
      )

    repo.insert_all(ReminderRule, reminder_rows(item, offsets),
      on_conflict: [set: [active: true, updated_at: now]],
      conflict_target: [:due_item_id, :offset_days]
    )
    |> then(&{:ok, &1})
  end

  def reminder_rows(item, offsets) do
    now = DateTime.utc_now(:second)

    for offset <- offsets do
      %{
        id: Ecto.UUID.generate(),
        customer_account_id: item.customer_account_id,
        due_item_id: item.id,
        offset_days: offset,
        active: true,
        inserted_at: now,
        updated_at: now
      }
    end
  end

  def assignment_rows(scope, item, primary, additional) do
    now = DateTime.utc_now(:second)
    rows = if primary, do: [assignment_row(scope, item, primary, "primary", now)], else: []
    rows ++ for(id <- additional || [], do: assignment_row(scope, item, id, "additional", now))
  end

  def assignment_row(scope, item, user_id, role, now) do
    %{
      id: Ecto.UUID.generate(),
      customer_account_id: item.customer_account_id,
      due_item_id: item.id,
      user_id: user_id,
      role: role,
      assigned_by_user_id: scope.user.id,
      assigned_at: now,
      ended_at: nil,
      inserted_at: now,
      updated_at: now
    }
  end

  @doc """
  Works out how to get from the item's active assignments (preloaded) to
  the wanted ones. Returns `{ids_to_end, [{user_id, role}], audit_changes}`;
  the changes map is empty when nothing changes.
  """
  def assignment_plan(%DueItem{} = item, primary, additional) do
    additional = additional || []

    current_primary =
      Enum.find_value(item.active_assignments, &(&1.role == "primary" && &1.user_id))

    current_additional =
      for %Assignment{role: "additional", user_id: id} <- item.active_assignments, do: id

    to_end =
      for a <- item.active_assignments,
          (a.role == "primary" and a.user_id != primary) or
            (a.role == "additional" and a.user_id not in additional),
          do: a.id

    kept_additional = current_additional -- (current_additional -- additional)

    new_rows =
      if(primary && primary != current_primary, do: [{primary, "primary"}], else: []) ++
        for(id <- additional -- kept_additional, do: {id, "additional"})

    changes =
      %{}
      |> then(fn c ->
        if primary != current_primary,
          do: Map.put(c, "primary", [current_primary, primary]),
          else: c
      end)
      |> then(fn c ->
        if Enum.sort(additional) != Enum.sort(current_additional),
          do: Map.put(c, "additional", [Enum.sort(current_additional), Enum.sort(additional)]),
          else: c
      end)

    {to_end, new_rows, changes}
  end

  @doc "Ends and inserts assignments per `assignment_plan/3`, inside a Multi."
  def apply_assignment_plan(multi, scope, item, {to_end, new_rows, _changes}) do
    now = DateTime.utc_now(:second)

    multi
    |> Multi.update_all(:ended, from(a in Assignment, where: a.id in ^to_end),
      set: [ended_at: now, updated_at: now]
    )
    |> Multi.insert_all(:assigned, Assignment, fn _ ->
      for {user_id, role} <- new_rows, do: assignment_row(scope, item, user_id, role, now)
    end)
  end

  @doc "Assignees must be active members of the account."
  def validate_assignees(changeset, scope) do
    primary = Ecto.Changeset.get_field(changeset, :primary_user_id)
    additional = Ecto.Changeset.get_field(changeset, :additional_user_ids) || []
    ids = Enum.reject([primary | additional], &is_nil/1)

    if ids == [] do
      changeset
    else
      account_id = Scope.account_id!(scope)

      active =
        from(m in Membership,
          where:
            m.customer_account_id == ^account_id and m.status == "active" and m.user_id in ^ids,
          select: m.user_id
        )
        |> Repo.all()

      cond do
        primary && primary not in active ->
          Ecto.Changeset.add_error(changeset, :primary_user_id, "choose an active member")

        Enum.any?(additional, &(&1 not in active)) ->
          Ecto.Changeset.add_error(changeset, :additional_user_ids, "choose active members")

        true ->
          changeset
      end
    end
  end

  def authorize(true), do: :ok
  def authorize(false), do: {:error, :unauthorized}

  def same_account(scope, %DueItem{customer_account_id: account_id}) do
    if account_id == Scope.account_id!(scope), do: :ok, else: {:error, :unauthorized}
  end

  def iso(nil), do: nil
  def iso(%Date{} = date), do: Date.to_iso8601(date)
end

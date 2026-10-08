defmodule DueDesk.DueItems do
  @moduledoc """
  DueItems: what an account must renew, file or complete, who is
  responsible and when reminders go out.

  Every function takes a `DueDesk.Accounts.Scope`, filters by its account
  and checks `DueDesk.Permissions` itself. Users see and act only on the
  DueItems they are assigned to; control fields are changed only by
  Administrators and Super Admins. Every change is audited in the same
  transaction.
  """

  import Ecto.Query, warn: false

  import DueDesk.DueItems.Steps,
    only: [
      lock_account: 2,
      check_limit: 1,
      replace_reminders: 3,
      reminder_rows: 2,
      assignment_rows: 4,
      assignment_plan: 3,
      apply_assignment_plan: 4,
      validate_assignees: 2,
      authorize: 1,
      same_account: 2,
      iso: 1
    ]

  alias Ecto.Multi
  alias DueDesk.{Audit, Permissions, Repo, Tenancy}
  alias DueDesk.Accounts.Scope
  alias DueDesk.DueItems.{Assignment, Category, Cycle, DueItem, Lifecycle, Note, Queries}
  alias DueDesk.DueItems.{ReminderRule, Status}
  alias DueDesk.Organisations.Organisation

  require DueDesk.DueItems.Status

  @per_page 50

  ## Reading

  @doc "How many DueItems a list page shows."
  def per_page, do: @per_page

  @doc """
  Lists the DueItems the scope may see, filtered by string-keyed `params`
  (see `DueDesk.DueItems.Queries.filter/5`), soonest first.

  ## Options

    * `:limit` - default `per_page/0`
    * `:offset` - default 0
  """
  def list_due_items(%Scope{} = scope, params \\ %{}, opts \\ []) do
    {today, soon_until} = window(scope)

    scope
    |> Queries.base()
    |> Queries.visible(scope)
    |> Queries.filter(params, scope, today, soon_until)
    |> Queries.ordered()
    |> limit(^Keyword.get(opts, :limit, @per_page))
    |> offset(^Keyword.get(opts, :offset, 0))
    |> preload_list()
    |> Repo.all()
  end

  @doc """
  The DueItems the scope may see that changed most recently.
  """
  def list_recently_updated(%Scope{} = scope, limit \\ 5) do
    scope
    |> Queries.base()
    |> Queries.visible(scope)
    |> Queries.active()
    |> order_by([item: i], desc: i.updated_at, desc: i.id)
    |> limit(^limit)
    |> preload_list()
    |> Repo.all()
  end

  defp preload_list(query) do
    preload(query, [item: i, cycle: c, organisation: o, category: cat],
      current_cycle: c,
      organisation: o,
      category: cat,
      active_assignments: :user
    )
  end

  @doc """
  Gets a DueItem the scope may see, with its Organisation, category,
  current cycle, active assignments and reminder rules.

  Returns `{:error, :not_found}` for anything the scope may not see: a
  DueItem of another account, one the User is not assigned to, an
  archived one for a User, or an id that does not exist. The caller
  cannot tell these apart.
  """
  def get_due_item(%Scope{} = scope, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %DueItem{} = item <-
           scope
           |> Queries.base()
           |> Queries.visible(scope)
           |> where([item: i], i.id == ^id)
           |> preload_list()
           |> Repo.one() do
      {:ok, Repo.preload(item, reminder_rules: from(r in ReminderRule, order_by: r.offset_days))}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "The effective status of a DueItem loaded with its current cycle."
  def status(%Scope{customer_account: account} = scope, %DueItem{} = item) do
    Status.effective(item, item.current_cycle, Tenancy.today(scope), account.due_soon_days)
  end

  @doc """
  Counts the active DueItems the scope may see by status. Administrators
  and Super Admins also get the number of unassigned DueItems.
  """
  def count_by_status(%Scope{} = scope) do
    {today, soon_until} = window(scope)

    statuses =
      scope
      |> Queries.base()
      |> Queries.visible(scope)
      |> Queries.active()
      |> select([item: i, cycle: c], %{status: Status.sql(i, c, ^today, ^soon_until)})

    counts =
      from(s in subquery(statuses), group_by: s.status, select: {s.status, count()})
      |> Repo.all()
      |> Map.new()

    unassigned =
      if Permissions.can_view_all_due_items?(scope) do
        scope
        |> Queries.base()
        |> Queries.active()
        |> Queries.unassigned()
        |> select([item: i], count(i.id))
        |> Repo.one()
      else
        0
      end

    %{
      overdue: Map.get(counts, "overdue", 0),
      due_soon: Map.get(counts, "due_soon", 0),
      up_to_date: Map.get(counts, "up_to_date", 0),
      unassigned: unassigned
    }
  end

  @doc """
  Active DueItems per Organisation, with how many are overdue or due
  soon. Administrators and Super Admins only; others get `[]`.
  """
  def counts_by_organisation(%Scope{} = scope) do
    if Permissions.can_view_all_due_items?(scope) do
      {today, soon_until} = window(scope)

      scope
      |> Queries.base()
      |> Queries.active()
      |> group_by([organisation: o], [o.id, o.name])
      |> order_by([item: i, organisation: o], desc: count(i.id), asc: o.name)
      |> select([item: i, cycle: c, organisation: o], %{
        id: o.id,
        name: o.name,
        total: count(i.id),
        overdue: filter(count(i.id), Status.sql(i, c, ^today, ^soon_until) == "overdue"),
        due_soon: filter(count(i.id), Status.sql(i, c, ^today, ^soon_until) == "due_soon")
      })
      |> Repo.all()
    else
      []
    end
  end

  @doc """
  Active DueItems per Primary Responsible, with how many are overdue.
  Administrators and Super Admins only; others get `[]`.
  """
  def counts_by_user(%Scope{} = scope) do
    if Permissions.can_view_all_due_items?(scope) do
      {today, soon_until} = window(scope)

      scope
      |> Queries.base()
      |> Queries.active()
      |> join(:inner, [item: i], a in Assignment,
        on: a.due_item_id == i.id and a.role == "primary" and is_nil(a.ended_at),
        as: :assignment
      )
      |> join(:inner, [assignment: a], u in assoc(a, :user), as: :user)
      |> group_by([user: u], [u.id, u.name])
      |> order_by([item: i, user: u], desc: count(i.id), asc: u.name)
      |> select([item: i, cycle: c, user: u], %{
        id: u.id,
        name: u.name,
        total: count(i.id),
        overdue: filter(count(i.id), Status.sql(i, c, ^today, ^soon_until) == "overdue")
      })
      |> Repo.all()
    else
      []
    end
  end

  @doc """
  Counts of active DueItems the scope may see per effective date, for
  each of the `days` days from today: `[%{date: date, count: n}]`.
  """
  def due_timeline(%Scope{} = scope, days) do
    today = Tenancy.today(scope)
    last = Date.add(today, days - 1)

    counts =
      scope
      |> Queries.base()
      |> Queries.visible(scope)
      |> Queries.active()
      |> where(
        [cycle: c],
        Status.effective_date_sql(c) >= ^today and Status.effective_date_sql(c) <= ^last
      )
      |> group_by([cycle: c], Status.effective_date_sql(c))
      |> select([item: i, cycle: c], {Status.effective_date_sql(c), count(i.id)})
      |> Repo.all()
      |> Map.new()

    for offset <- 0..(days - 1) do
      date = Date.add(today, offset)
      %{date: date, count: Map.get(counts, date, 0)}
    end
  end

  @doc "Active DueItems the scope may see, counted per Organisation id."
  def count_active_by_organisation(%Scope{} = scope) do
    scope
    |> Queries.base()
    |> Queries.visible(scope)
    |> Queries.active()
    |> group_by([item: i], i.organisation_id)
    |> select([item: i], {i.organisation_id, count(i.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Counts active DueItems waiting for an Administrator: completed ones and
  ones renewed without next dates. Administrators and Super Admins only;
  others get 0.
  """
  def count_awaiting(%Scope{} = scope) do
    if Permissions.can_view_all_due_items?(scope) do
      scope
      |> Queries.base()
      |> Queries.awaiting()
      |> select([item: i], count(i.id))
      |> Repo.one()
    else
      0
    end
  end

  @doc """
  Renewals by Users that an Administrator has not reviewed yet, newest
  first, as cycles with their DueItem (Organisation and current cycle
  loaded) and who renewed. Administrators and Super Admins only; others
  get `[]`.
  """
  def list_renewal_reviews(%Scope{} = scope) do
    if Permissions.can_view_all_due_items?(scope) do
      scope
      |> renewal_reviews()
      |> order_by([cycle: c], desc: c.completed_at, desc: c.id)
      |> preload([item: i], [:completed_by_user, due_item: {i, [:organisation, :current_cycle]}])
      |> Repo.all()
    else
      []
    end
  end

  @doc "How many renewals wait for review; 0 for Users."
  def count_renewal_reviews(%Scope{} = scope) do
    if Permissions.can_view_all_due_items?(scope) do
      scope |> renewal_reviews() |> select([cycle: c], count(c.id)) |> Repo.one()
    else
      0
    end
  end

  defp renewal_reviews(scope) do
    account_id = Scope.account_id!(scope)

    from(c in Cycle,
      as: :cycle,
      join: i in assoc(c, :due_item),
      as: :item,
      where: c.customer_account_id == ^account_id and i.customer_account_id == ^account_id,
      where: c.completion_type == "renewed" and is_nil(c.reviewed_at) and i.status == "active"
    )
  end

  @doc """
  Cycles renewed or completed in the last 30 days on DueItems the scope
  may see, newest first, with their DueItem and who closed them.
  """
  def list_recently_completed(%Scope{} = scope, limit \\ 5) do
    account_id = Scope.account_id!(scope)
    since = DateTime.add(DateTime.utc_now(:second), -30, :day)
    visible = scope |> Queries.base() |> Queries.visible(scope) |> select([item: i], i.id)

    from(c in Cycle,
      join: i in assoc(c, :due_item),
      where: c.customer_account_id == ^account_id and c.due_item_id in subquery(visible),
      where: not is_nil(c.completed_at) and c.completed_at >= ^since,
      order_by: [desc: c.completed_at, desc: c.sequence],
      limit: ^limit,
      preload: [:completed_by_user, due_item: i]
    )
    |> Repo.all()
  end

  @doc """
  The closed (renewed or completed) cycles of a DueItem the scope may
  see, newest first, with who closed and reviewed them.
  """
  def list_cycles(%Scope{} = scope, %DueItem{} = item) do
    case visible_item(scope, item) do
      {:ok, item} ->
        from(c in Cycle,
          where: c.due_item_id == ^item.id and c.customer_account_id == ^item.customer_account_id,
          where: not is_nil(c.completed_at),
          order_by: [desc: c.sequence],
          preload: [:completed_by_user, :reviewed_by_user]
        )
        |> Repo.all()

      _ ->
        []
    end
  end

  # Today and the last day that counts as due soon, in the account timezone.
  defp window(%Scope{customer_account: account} = scope) do
    today = Tenancy.today(scope)
    {today, Date.add(today, account.due_soon_days)}
  end

  @doc """
  The members a DueItem can be assigned to: active Administrators, Users
  and Super Admins of the account, by name.
  """
  def assignable_members(%Scope{} = scope) do
    scope
    |> Tenancy.list_memberships()
    |> Enum.filter(&(&1.status == "active"))
  end

  ## Forms

  @doc "A new DueItem with the default reminders, for the create form."
  def new_due_item do
    %DueItem{reminder_offsets: ReminderRule.defaults()}
  end

  @doc """
  Returns a changeset for the create form. Users' changesets ignore the
  control fields.
  """
  def change_new_due_item(%Scope{} = scope, %DueItem{} = item, attrs \\ %{}) do
    DueItem.create_changeset(item, attrs, control: Permissions.can_manage_due_items?(scope))
  end

  @doc """
  Loads the dates and active reminders of a DueItem into its virtual
  fields, for the edit form.
  """
  def prepare_edit(%DueItem{current_cycle: %Cycle{} = cycle} = item) do
    item = Repo.preload(item, :reminder_rules)

    %{
      item
      | start_date: cycle.start_date,
        due_date: cycle.due_date,
        expiry_date: cycle.expiry_date,
        reminder_offsets:
          for(%ReminderRule{active: true, offset_days: d} <- item.reminder_rules, do: d)
          |> Enum.sort()
    }
  end

  @doc "Returns a changeset for the edit form."
  def change_due_item(%DueItem{} = item, attrs \\ %{}) do
    DueItem.update_changeset(item, attrs)
  end

  ## Writing

  @doc """
  Creates a DueItem with its first cycle, reminder rules and assignments.

  Administrators and Super Admins may set every field and choose the
  Primary Responsible and Additional Assignees, or leave it unassigned.
  A User sets only the operational fields: the User becomes Primary
  Responsible, the recurrence is "Does not repeat" and the default
  reminders apply, whatever the input says.

  Returns `{:ok, item}`, `{:error, changeset}`,
  `{:error, {:limit_reached, info}}` or `{:error, :unauthorized}`.
  """
  def create_due_item(%Scope{} = scope, attrs) do
    with :ok <- authorize(Permissions.can_create_due_item?(scope)) do
      control? = Permissions.can_manage_due_items?(scope)
      account_id = Scope.account_id!(scope)

      changeset =
        %DueItem{
          new_due_item()
          | customer_account_id: account_id,
            created_by_user_id: scope.user.id
        }
        |> DueItem.create_changeset(attrs, control: control?)
        |> force_user_fields(scope, control?)
        |> validate_references(scope)
        |> validate_assignees(scope)

      Multi.new()
      |> lock_account(scope)
      |> Multi.run(:limit, fn _repo, _ -> check_limit(scope) end)
      |> Multi.insert(:inserted, changeset)
      |> Multi.insert(:cycle, fn %{inserted: item} ->
        %Cycle{
          customer_account_id: account_id,
          due_item_id: item.id,
          sequence: 1,
          start_date: item.start_date,
          due_date: item.due_date,
          expiry_date: item.expiry_date
        }
      end)
      |> Multi.update(:item, fn %{inserted: item, cycle: cycle} ->
        Ecto.Changeset.change(item, current_cycle_id: cycle.id)
      end)
      |> Multi.insert_all(:reminders, ReminderRule, fn %{item: item} ->
        reminder_rows(item, item.reminder_offsets)
      end)
      |> Multi.insert_all(:assignments, Assignment, fn %{item: item} ->
        assignment_rows(scope, item, item.primary_user_id, item.additional_user_ids)
      end)
      |> Audit.multi_log(:audit, scope, "due_item.created", & &1.item,
        changes: fn %{item: item} ->
          %{
            "title" => [nil, item.title],
            "due_date" => [nil, iso(item.due_date)],
            "expiry_date" => [nil, iso(item.expiry_date)],
            "primary" => [nil, item.primary_user_id]
          }
        end
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{item: item}} -> {:ok, item}
        {:error, :limit, reason, _} -> {:error, reason}
        {:error, :inserted, changeset, _} -> {:error, changeset}
      end
    end
  end

  # A User's own DueItem: the User is Primary Responsible and nothing else
  # is assigned.
  defp force_user_fields(changeset, _scope, true), do: changeset

  defp force_user_fields(changeset, scope, false) do
    Ecto.Changeset.change(changeset,
      primary_user_id: scope.user.id,
      additional_user_ids: [],
      reminder_offsets: ReminderRule.defaults()
    )
  end

  @doc """
  Updates a DueItem's fields, the dates of its current cycle and its
  reminders. Administrators and Super Admins only.
  """
  def update_due_item(%Scope{} = scope, %DueItem{} = item, attrs) do
    with :ok <- authorize(Permissions.can_manage_due_items?(scope)),
         :ok <- same_account(scope, item) do
      item = item |> Repo.preload([:organisation, :category, :current_cycle]) |> prepare_edit()

      changeset =
        item
        |> DueItem.update_changeset(attrs)
        |> validate_references(scope)

      cycle_changeset =
        Cycle.dates_changeset(item.current_cycle, %{
          start_date: Ecto.Changeset.get_field(changeset, :start_date),
          due_date: Ecto.Changeset.get_field(changeset, :due_date),
          expiry_date: Ecto.Changeset.get_field(changeset, :expiry_date)
        })

      offsets = Ecto.Changeset.get_field(changeset, :reminder_offsets)

      changes =
        if changeset.valid?, do: update_audit_changes(item, changeset, offsets), else: %{}

      Multi.new()
      |> Multi.update(:item, changeset)
      |> Multi.update(:cycle, cycle_changeset)
      |> Multi.run(:reminders, fn repo, _ -> replace_reminders(repo, item, offsets) end)
      |> maybe_audit(changes == %{}, fn multi ->
        Audit.multi_log(multi, :audit, scope, "due_item.updated", item, changes: changes)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{item: updated}} -> {:ok, updated}
        {:error, :item, changeset, _} -> {:error, changeset}
        {:error, :cycle, _cycle_changeset, _} -> {:error, %{changeset | valid?: false}}
      end
    end
  end

  defp update_audit_changes(item, changeset, offsets) do
    fields =
      for field <- [:title, :reference_number, :related_party, :recurrence],
          Map.has_key?(changeset.changes, field),
          into: %{} do
        {Atom.to_string(field), [Map.get(item, field), Map.get(changeset.changes, field)]}
      end

    fields
    |> put_if_changed("description", item.description, changeset.changes[:description], fn
      _old, _new -> "changed"
    end)
    |> put_name_change("organisation", item.organisation, changeset.changes[:organisation_id])
    |> put_name_change("category", item.category, changeset.changes[:category_id])
    |> put_recurrence_detail(item, changeset)
    |> put_date_change("start_date", item.start_date, changeset)
    |> put_date_change("due_date", item.due_date, changeset)
    |> put_date_change("expiry_date", item.expiry_date, changeset)
    |> then(fn changes ->
      if offsets != item.reminder_offsets,
        do: Map.put(changes, "reminders", [item.reminder_offsets, offsets]),
        else: changes
    end)
  end

  defp put_if_changed(changes, _key, _old, nil, _fun), do: changes
  defp put_if_changed(changes, key, old, new, fun), do: Map.put(changes, key, fun.(old, new))

  defp put_name_change(changes, _key, _old, nil), do: changes

  defp put_name_change(changes, "organisation", old, id) do
    Map.put(changes, "organisation", [old && old.name, Repo.get(Organisation, id).name])
  end

  defp put_name_change(changes, "category", old, id) do
    Map.put(changes, "category", [old && old.name, Repo.get(Category, id).name])
  end

  defp put_recurrence_detail(changes, item, changeset) do
    unit = Ecto.Changeset.get_field(changeset, :recurrence_unit)
    interval = Ecto.Changeset.get_field(changeset, :recurrence_interval)

    if Map.has_key?(changes, "recurrence") or unit != item.recurrence_unit or
         interval != item.recurrence_interval do
      Map.put(changes, "recurrence", [
        [item.recurrence, item.recurrence_unit, item.recurrence_interval],
        [Ecto.Changeset.get_field(changeset, :recurrence), unit, interval]
      ])
    else
      changes
    end
  end

  defp put_date_change(changes, key, old, changeset) do
    new = Ecto.Changeset.get_field(changeset, String.to_existing_atom(key))
    if old == new, do: changes, else: Map.put(changes, key, [iso(old), iso(new)])
  end

  @doc """
  Sets who is responsible for a DueItem: one Primary Responsible (or
  nobody) and any Additional Assignees. Assignments that are removed are
  ended, never deleted. Administrators and Super Admins only.
  """
  def assign_due_item(%Scope{} = scope, %DueItem{} = item, attrs) do
    with :ok <- authorize(Permissions.can_manage_due_items?(scope)),
         :ok <- same_account(scope, item) do
      item = Repo.preload(item, :active_assignments, force: true)
      changeset = assignment_changeset(scope, attrs)

      if changeset.valid? do
        apply_assignment(scope, item, Ecto.Changeset.apply_changes(changeset))
      else
        {:error, %{changeset | action: :validate}}
      end
    end
  end

  @doc "Returns a changeset for the responsibility form."
  def change_assignment(%Scope{} = scope, %DueItem{} = item, attrs \\ nil) do
    attrs =
      attrs ||
        %{
          "primary_user_id" => item |> DueItem.primary_user() |> then(&(&1 && &1.id)),
          "additional_user_ids" => Enum.map(DueItem.additional_users(item), & &1.id)
        }

    assignment_changeset(scope, attrs)
  end

  @assignment_types %{primary_user_id: :binary_id, additional_user_ids: {:array, :binary_id}}

  defp assignment_changeset(scope, attrs) do
    attrs =
      Map.new(attrs, fn
        {k, v} when is_list(v) -> {to_string(k), Enum.reject(v, &(&1 in ["", nil]))}
        {k, ""} -> {to_string(k), nil}
        {k, v} -> {to_string(k), v}
      end)

    {%{additional_user_ids: []}, @assignment_types}
    |> Ecto.Changeset.cast(attrs, Map.keys(@assignment_types))
    |> then(fn changeset ->
      primary = Ecto.Changeset.get_field(changeset, :primary_user_id)
      additional = Ecto.Changeset.get_field(changeset, :additional_user_ids) || []

      changeset =
        Ecto.Changeset.put_change(
          changeset,
          :additional_user_ids,
          Enum.uniq(additional -- [primary])
        )

      if is_nil(primary) and additional != [],
        do:
          Ecto.Changeset.add_error(
            changeset,
            :primary_user_id,
            "choose a Primary Responsible first"
          ),
        else: changeset
    end)
    |> validate_assignees(scope)
  end

  defp apply_assignment(scope, item, %{} = wanted) do
    {_to_end, _new_rows, changes} =
      plan = assignment_plan(item, wanted[:primary_user_id], wanted.additional_user_ids)

    if changes == %{} do
      {:ok, item}
    else
      Multi.new()
      |> apply_assignment_plan(scope, item, plan)
      |> Multi.update(:item, Ecto.Changeset.change(item, updated_at: DateTime.utc_now(:second)))
      |> Audit.multi_log(:audit, scope, "due_item.assigned", item, changes: changes)
      |> Repo.transaction()
      |> case do
        {:ok, %{item: item}} -> {:ok, item}
      end
    end
  end

  @doc """
  Overrides the computed status of a DueItem until its next cycle. A
  reason is required. Administrators and Super Admins only.
  """
  def override_status(%Scope{} = scope, %DueItem{} = item, status, reason) do
    with :ok <- authorize(Permissions.can_manage_due_items?(scope)),
         :ok <- same_account(scope, item) do
      item = Repo.preload(item, :current_cycle)
      previous = status(scope, item)
      changeset = Cycle.override_changeset(item.current_cycle, status, reason, scope.user.id)

      Multi.new()
      |> Multi.update(:cycle, changeset)
      |> Audit.multi_log(:audit, scope, "due_item.status_overridden", item,
        changes: %{"status" => [Atom.to_string(previous), status]},
        metadata: %{"reason" => Ecto.Changeset.get_field(changeset, :status_override_reason)}
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{cycle: cycle}} -> {:ok, %{item | current_cycle: cycle}}
        {:error, :cycle, changeset, _} -> {:error, changeset}
      end
    end
  end

  @doc "Removes a status override. Administrators and Super Admins only."
  def clear_status_override(%Scope{} = scope, %DueItem{} = item) do
    with :ok <- authorize(Permissions.can_manage_due_items?(scope)),
         :ok <- same_account(scope, item) do
      item = Repo.preload(item, :current_cycle)
      cycle = item.current_cycle

      if is_nil(cycle.status_override) do
        {:ok, item}
      else
        Multi.new()
        |> Multi.update(:cycle, Cycle.clear_override_changeset(cycle))
        |> Audit.multi_log(:audit, scope, "due_item.status_override_cleared", item,
          changes: %{"status" => [cycle.status_override, nil]}
        )
        |> Repo.transaction()
        |> case do
          {:ok, %{cycle: cycle}} -> {:ok, %{item | current_cycle: cycle}}
        end
      end
    end
  end

  @doc """
  Archives a DueItem. It is hidden from Users, no longer counts toward
  the plan limit and keeps its history. An item awaiting an
  Administrator's decision leaves that queue. Administrators and Super
  Admins only.
  """
  def archive_due_item(%Scope{} = scope, %DueItem{status: "active"} = item) do
    with :ok <- authorize(Permissions.can_manage_due_items?(scope)),
         :ok <- same_account(scope, item) do
      changeset =
        Ecto.Changeset.change(item,
          status: "archived",
          disposition_state: nil,
          archived_at: DateTime.utc_now(:second),
          archived_by_user_id: scope.user.id
        )

      metadata = if item.disposition_state, do: %{"from" => item.disposition_state}, else: %{}

      Multi.new()
      |> Multi.update(:item, changeset)
      |> Audit.multi_log(:audit, scope, "due_item.archived", item, metadata: metadata)
      |> Repo.transaction()
      |> case do
        {:ok, %{item: item}} -> {:ok, item}
      end
    end
  end

  def archive_due_item(%Scope{}, %DueItem{}), do: {:error, :not_active}

  ## Lifecycle

  defdelegate change_completion(scope, item, attrs \\ %{}), to: Lifecycle
  defdelegate renew_due_item(scope, item, attrs), to: Lifecycle
  defdelegate complete_due_item(scope, item, attrs), to: Lifecycle
  defdelegate prepare_reactivate(item), to: Lifecycle
  defdelegate change_reactivation(scope, item, attrs \\ %{}), to: Lifecycle
  defdelegate reactivate_due_item(scope, item, attrs), to: Lifecycle
  defdelegate dismiss_renewal_review(scope, cycle_id), to: Lifecycle
  defdelegate delete_due_item(scope, item, confirmation), to: Lifecycle
  defdelegate next_dates(scope, item), to: Lifecycle

  ## Notes

  @doc "The notes on a DueItem the scope may see, oldest first."
  def list_notes(%Scope{} = scope, %DueItem{} = item) do
    case visible_item(scope, item) do
      {:ok, item} ->
        from(n in Note,
          where: n.due_item_id == ^item.id and n.customer_account_id == ^item.customer_account_id,
          order_by: [asc: n.inserted_at],
          preload: [:author_user]
        )
        |> Repo.all()

      _ ->
        []
    end
  end

  @doc "Returns a changeset for the note form."
  def change_note(attrs \\ %{}), do: Note.changeset(%Note{}, attrs)

  @doc """
  Adds a note to a DueItem the scope may see. The audit event records
  that a note was added, never its text.
  """
  def add_note(%Scope{} = scope, %DueItem{} = item, attrs) do
    with {:ok, item} <- visible_item(scope, item),
         :ok <- authorize(Permissions.can_add_note?(scope, item)) do
      changeset =
        %Note{
          customer_account_id: item.customer_account_id,
          due_item_id: item.id,
          cycle_id: item.current_cycle_id,
          author_user_id: scope.user.id
        }
        |> Note.changeset(attrs)

      Multi.new()
      |> Multi.insert(:note, changeset)
      |> Audit.multi_log(:audit, scope, "note.added", item,
        changes: fn %{note: note} -> %{"note_id" => note.id} end
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{note: note}} -> {:ok, Repo.preload(note, :author_user)}
        {:error, :note, changeset, _} -> {:error, changeset}
      end
    end
  end

  # Reloads the item's visibility so a stale struct grants nothing.
  defp visible_item(scope, %DueItem{id: id}) do
    case get_due_item(scope, id) do
      {:ok, item} -> {:ok, item}
      {:error, :not_found} -> {:error, :unauthorized}
    end
  end

  ## History

  @doc "The DueItem's history as readable sentences, newest first."
  def history(%Scope{} = scope, %DueItem{} = item) do
    if Permissions.can_view_audit_log?(scope) or match?({:ok, _}, visible_item(scope, item)) do
      scope
      |> Audit.list_events(subject: item, limit: 200)
      |> Audit.Humanize.describe(scope)
    else
      []
    end
  end

  ## Helpers

  # Organisations and categories must belong to the account and be active.
  # An unchanged reference to one archived later is kept.
  defp validate_references(changeset, scope) do
    account_id = Scope.account_id!(scope)

    changeset
    |> validate_reference(
      :organisation_id,
      Organisation,
      account_id,
      "choose an active Organisation"
    )
    |> validate_reference(:category_id, Category, account_id, "choose an active category")
  end

  defp validate_reference(changeset, field, schema, account_id, message) do
    case Ecto.Changeset.fetch_change(changeset, field) do
      {:ok, id} when not is_nil(id) ->
        active? =
          Repo.exists?(
            from(r in schema,
              where: r.id == ^id and r.customer_account_id == ^account_id and r.status == "active"
            )
          )

        if active?, do: changeset, else: Ecto.Changeset.add_error(changeset, field, message)

      _ ->
        changeset
    end
  end

  defp maybe_audit(multi, true = _no_changes, _fun), do: multi
  defp maybe_audit(multi, false, fun), do: fun.(multi)
end

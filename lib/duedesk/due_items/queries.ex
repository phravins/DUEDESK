defmodule DueDesk.DueItems.Queries do
  @moduledoc """
  Query building blocks for DueItems. Every query starts from `base/1`,
  which filters by the scope's account, and is narrowed by `visible/2`
  to what the scope may see.
  """

  import Ecto.Query, warn: false

  require DueDesk.DueItems.Status

  alias DueDesk.Permissions
  alias DueDesk.Accounts.Scope
  alias DueDesk.DueItems.{Assignment, DueItem, Status}

  @doc """
  The scope's DueItems joined to their current cycle (`:cycle`),
  Organisation (`:organisation`) and category (`:category`).
  """
  def base(%Scope{} = scope) do
    account_id = Scope.account_id!(scope)

    from(i in DueItem,
      as: :item,
      join: c in assoc(i, :current_cycle),
      as: :cycle,
      join: o in assoc(i, :organisation),
      as: :organisation,
      join: cat in assoc(i, :category),
      as: :category,
      where: i.customer_account_id == ^account_id
    )
  end

  @doc """
  Narrows `query` to the DueItems the scope may see. Administrators and
  Super Admins see every DueItem. Users see only active items they are
  assigned to (as Primary Responsible or Additional Assignee) that are
  not awaiting disposition.
  """
  def visible(query, %Scope{} = scope) do
    cond do
      Permissions.can_view_all_due_items?(scope) ->
        query

      Permissions.member?(scope) ->
        user_id = scope.user.id

        from([item: i] in query,
          where: i.status == "active" and is_nil(i.disposition_state),
          where:
            exists(
              from(a in Assignment,
                where:
                  a.due_item_id == parent_as(:item).id and a.user_id == ^user_id and
                    is_nil(a.ended_at),
                select: 1
              )
            )
        )

      true ->
        where(query, false)
    end
  end

  @doc "Only active (not archived) DueItems."
  def active(query), do: where(query, [item: i], i.status == "active")

  @doc "Only DueItems without an active Primary Responsible."
  def unassigned(query) do
    where(
      query,
      [item: i],
      not exists(
        from(a in Assignment,
          where:
            a.due_item_id == parent_as(:item).id and a.role == "primary" and is_nil(a.ended_at),
          select: 1
        )
      )
    )
  end

  @doc "Only DueItems with the given effective status."
  def with_status(query, status, today, soon_until) when is_atom(status) do
    name = Atom.to_string(status)
    where(query, [item: i, cycle: c], Status.sql(i, c, ^today, ^soon_until) == ^name)
  end

  @doc """
  Applies list filters from string-keyed params:

    * `"view"` - `"archived"` for archived items (Administrators only),
      anything else for active items
    * `"q"` - search in title, reference number, related party,
      Organisation and category names
    * `"status"` - `overdue`, `due_soon` or `up_to_date`
    * `"assignment"` - `"unassigned"`
    * `"organisation_id"`, `"category_id"`
    * `"primary_user_id"`, `"assignee_user_id"`
    * `"due_from"`, `"due_to"`, `"expiry_from"`, `"expiry_to"` - ISO dates
  """
  def filter(query, params, %Scope{} = scope, today, soon_until) do
    archived? = params["view"] == "archived" and Permissions.can_view_all_due_items?(scope)

    query =
      if archived?,
        do: where(query, [item: i], i.status == "archived"),
        else: active(query)

    Enum.reduce(params, query, fn
      {"q", term}, q ->
        search(q, term)

      {"status", value}, q ->
        case Status.parse(value) do
          status when status in [:overdue, :due_soon, :up_to_date] ->
            with_status(q, status, today, soon_until)

          _ ->
            q
        end

      {"assignment", "unassigned"}, q ->
        unassigned(q)

      {"organisation_id", id}, q ->
        with_uuid(q, id, fn q, id -> where(q, [item: i], i.organisation_id == ^id) end)

      {"category_id", id}, q ->
        with_uuid(q, id, fn q, id -> where(q, [item: i], i.category_id == ^id) end)

      {"primary_user_id", id}, q ->
        with_uuid(q, id, &assigned_to(&1, &2, "primary"))

      {"assignee_user_id", id}, q ->
        with_uuid(q, id, &assigned_to(&1, &2, nil))

      {"due_from", value}, q ->
        with_date(q, value, fn q, d -> where(q, [cycle: c], c.due_date >= ^d) end)

      {"due_to", value}, q ->
        with_date(q, value, fn q, d -> where(q, [cycle: c], c.due_date <= ^d) end)

      {"expiry_from", value}, q ->
        with_date(q, value, fn q, d -> where(q, [cycle: c], c.expiry_date >= ^d) end)

      {"expiry_to", value}, q ->
        with_date(q, value, fn q, d -> where(q, [cycle: c], c.expiry_date <= ^d) end)

      _, q ->
        q
    end)
  end

  defp search(query, term) when is_binary(term) do
    case String.trim(term) do
      "" ->
        query

      term ->
        like = "%" <> String.replace(term, ["\\", "%", "_"], &("\\" <> &1)) <> "%"

        where(
          query,
          [item: i, organisation: o, category: cat],
          ilike(i.title, ^like) or ilike(i.reference_number, ^like) or
            ilike(i.related_party, ^like) or ilike(o.name, ^like) or ilike(cat.name, ^like)
        )
    end
  end

  defp search(query, _), do: query

  defp assigned_to(query, user_id, role) do
    assignments =
      from(a in Assignment,
        where:
          a.due_item_id == parent_as(:item).id and a.user_id == ^user_id and is_nil(a.ended_at),
        select: 1
      )

    assignments = if role, do: where(assignments, [a], a.role == ^role), else: assignments
    where(query, exists(assignments))
  end

  defp with_uuid(query, value, fun) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> fun.(query, id)
      :error -> query
    end
  end

  defp with_date(query, value, fun) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> fun.(query, date)
      _ -> query
    end
  end

  defp with_date(query, _value, _fun), do: query

  @doc "Orders by effective date (soonest first), then title."
  def ordered(query) do
    order_by(query, [item: i, cycle: c],
      asc: Status.effective_date_sql(c),
      asc: fragment("lower(?)", i.title),
      asc: i.id
    )
  end
end

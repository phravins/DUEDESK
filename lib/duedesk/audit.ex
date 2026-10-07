defmodule DueDesk.Audit do
  @moduledoc """
  The append-only audit log.

  Audit rows are written in the same transaction as the change they
  describe (use `multi_log/6` inside an `Ecto.Multi`). Never put
  passwords, tokens, secrets or document contents in `changes` or
  `metadata`.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias DueDesk.Repo
  alias DueDesk.Accounts.Scope
  alias DueDesk.Audit.AuditEvent

  @type actor :: Scope.t() | {:operator, struct()} | :system

  @doc """
  Writes an audit event immediately.

  ## Options

    * `:changes` - map of `%{field => [old, new]}` or other change details
    * `:metadata` - extra context (e.g. reason)
    * `:customer_account_id` - required when the actor has no account
  """
  def log(actor, action, subject, opts \\ []) do
    actor
    |> build(action, subject, opts)
    |> Repo.insert()
  end

  @doc """
  Adds an audit insert to `multi` under `name`.

  `subject` may be a struct, `nil`, or a 1-arity function receiving the
  multi's changes so far and returning the subject.
  """
  def multi_log(%Multi{} = multi, name, actor, action, subject, opts \\ []) do
    Multi.insert(multi, name, fn changes ->
      subject = if is_function(subject, 1), do: subject.(changes), else: subject
      opts = Keyword.update(opts, :changes, %{}, &resolve(&1, changes))
      opts = Keyword.update(opts, :customer_account_id, nil, &resolve(&1, changes))
      build(actor, action, subject, opts)
    end)
  end

  defp resolve(fun, changes) when is_function(fun, 1), do: fun.(changes)
  defp resolve(value, _changes), do: value

  defp build(actor, action, subject, opts) do
    {actor_type, actor_id, actor_account_id} = actor_fields(actor)
    {subject_type, subject_id} = subject_fields(subject)

    %AuditEvent{
      customer_account_id: Keyword.get(opts, :customer_account_id) || actor_account_id,
      actor_type: actor_type,
      actor_id: actor_id,
      action: to_string(action),
      subject_type: subject_type,
      subject_id: subject_id,
      changes: Keyword.get(opts, :changes) || %{},
      metadata: Keyword.get(opts, :metadata) || %{}
    }
  end

  defp actor_fields(%Scope{user: user, customer_account: account}),
    do: {"user", user && user.id, account && account.id}

  defp actor_fields({:operator, %{id: id}}), do: {"operator", id, nil}
  defp actor_fields(:system), do: {"system", nil, nil}

  defp subject_fields(nil), do: {nil, nil}

  defp subject_fields(%module{id: id}) do
    {module |> Module.split() |> List.last() |> Macro.underscore(), id}
  end

  @doc """
  Lists audit events for the scope's account, newest first.
  """
  def list_events(%Scope{} = scope, opts \\ []) do
    account_id = Scope.account_id!(scope)
    limit = Keyword.get(opts, :limit, 100)

    from(e in AuditEvent,
      where: e.customer_account_id == ^account_id,
      order_by: [desc: e.inserted_at],
      limit: ^limit
    )
    |> maybe_filter_subject(opts[:subject])
    |> Repo.all()
  end

  defp maybe_filter_subject(query, nil), do: query

  defp maybe_filter_subject(query, subject) do
    {type, id} = subject_fields(subject)
    where(query, [e], e.subject_type == ^type and e.subject_id == ^id)
  end
end

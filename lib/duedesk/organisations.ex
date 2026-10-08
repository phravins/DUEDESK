defmodule DueDesk.Organisations do
  @moduledoc """
  Organisations of a Customer Account.

  Every function takes a `DueDesk.Accounts.Scope` and only touches the
  scope's account. Changes are made by Administrators and Super Admins,
  checked against the plan limit and audited in the same transaction.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias DueDesk.{Audit, Billing, Permissions, Repo}
  alias DueDesk.Accounts.Scope
  alias DueDesk.Organisations.{Declaration, Organisation}
  alias DueDesk.Tenancy.CustomerAccount

  @type declaration_meta :: %{optional(:ip) => String.t(), optional(:user_agent) => String.t()}

  ## Reading

  @doc """
  Lists the account's Organisations by name.

  ## Options

    * `:status` - `"active"` (default) or `"archived"`
  """
  def list_organisations(%Scope{} = scope, opts \\ []) do
    account_id = Scope.account_id!(scope)
    status = Keyword.get(opts, :status, "active")

    from(o in Organisation,
      where: o.customer_account_id == ^account_id and o.status == ^status,
      order_by: [asc: fragment("lower(?)", o.name)]
    )
    |> Repo.all()
  end

  @doc "Counts the account's Organisations by status."
  def count_by_status(%Scope{} = scope) do
    account_id = Scope.account_id!(scope)

    counts =
      from(o in Organisation,
        where: o.customer_account_id == ^account_id,
        group_by: o.status,
        select: {o.status, count(o.id)}
      )
      |> Repo.all()
      |> Map.new()

    %{active: Map.get(counts, "active", 0), archived: Map.get(counts, "archived", 0)}
  end

  @doc """
  Gets an Organisation of the scope's account. Raises
  `Ecto.NoResultsError` for another account's Organisation.
  """
  def get_organisation!(%Scope{} = scope, id) do
    account_id = Scope.account_id!(scope)

    from(o in Organisation,
      where: o.id == ^id and o.customer_account_id == ^account_id,
      preload: [:created_by_user]
    )
    |> Repo.one!()
  end

  @doc "The most recent declaration for an Organisation, with its user."
  def latest_declaration(%Scope{} = scope, %Organisation{id: id}) do
    account_id = Scope.account_id!(scope)

    from(d in Declaration,
      where: d.organisation_id == ^id and d.customer_account_id == ^account_id,
      order_by: [desc: d.accepted_at, desc: d.inserted_at],
      limit: 1,
      preload: [:user]
    )
    |> Repo.one()
  end

  @doc "Returns a changeset for the Organisation form."
  def change_organisation(%Organisation{} = organisation, attrs \\ %{}) do
    Organisation.changeset(organisation, attrs)
  end

  ## Writing

  @doc """
  Creates an Organisation and records the declaration.

  Returns `{:ok, organisation}`, `{:error, changeset}`,
  `{:error, {:limit_reached, info}}` or `{:error, :unauthorized}`.
  """
  @spec create_organisation(Scope.t(), map(), declaration_meta()) ::
          {:ok, Organisation.t()}
          | {:error, Ecto.Changeset.t() | :unauthorized | {:limit_reached, map()}}
  def create_organisation(%Scope{} = scope, attrs, meta \\ %{}) do
    with :ok <- authorize(scope) do
      changeset =
        %Organisation{
          customer_account_id: Scope.account_id!(scope),
          created_by_user_id: scope.user.id
        }
        |> Organisation.changeset(attrs)

      Multi.new()
      |> lock_account(scope)
      |> Multi.run(:limit, fn _repo, _ -> check_limit(scope) end)
      |> Multi.insert(:organisation, changeset)
      |> Multi.insert(:declaration, &Declaration.build(scope, &1.organisation, meta))
      |> Audit.multi_log(:audit, scope, "organisation.created", & &1.organisation,
        metadata: %{
          type: Ecto.Changeset.get_field(changeset, :type),
          declaration_version: Declaration.version()
        }
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{organisation: organisation}} -> {:ok, organisation}
        {:error, :limit, reason, _} -> {:error, reason}
        {:error, :organisation, changeset, _} -> {:error, changeset}
      end
    end
  end

  @doc """
  Updates an Organisation. Changing the type or identifier needs the
  declaration again, which is recorded as a new declaration.
  """
  def update_organisation(%Scope{} = scope, %Organisation{} = organisation, attrs, meta \\ %{}) do
    with :ok <- authorize(scope),
         :ok <- same_account(scope, organisation) do
      changeset = Organisation.changeset(organisation, attrs)
      declaration? = Organisation.declaration_required?(changeset)

      Multi.new()
      |> Multi.update(:organisation, changeset)
      |> then(fn multi ->
        if declaration? do
          Multi.insert(multi, :declaration, &Declaration.build(scope, &1.organisation, meta))
        else
          multi
        end
      end)
      |> Audit.multi_log(:audit, scope, "organisation.updated", & &1.organisation,
        changes: audit_changes(changeset),
        metadata: if(declaration?, do: %{declaration_version: Declaration.version()}, else: %{})
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{organisation: organisation}} -> {:ok, organisation}
        {:error, :organisation, changeset, _} -> {:error, changeset}
      end
    end
  end

  # Identifier values stay out of the audit log; only the fact they changed.
  defp audit_changes(changeset) do
    Enum.reduce(changeset.changes, %{}, fn
      {:name, new}, acc -> Map.put(acc, "name", [changeset.data.name, new])
      {:type, new}, acc -> Map.put(acc, "type", [changeset.data.type, new])
      {:normalized_identifier, _}, acc -> Map.put(acc, "identifier", "changed")
      {:gstin, _}, acc -> Map.put(acc, "gstin", "changed")
      _, acc -> acc
    end)
  end

  @doc """
  Archives an active Organisation. Its DueItems and documents are kept;
  it no longer counts toward the plan limit.
  """
  def archive_organisation(%Scope{} = scope, %Organisation{status: "active"} = organisation) do
    with :ok <- authorize(scope),
         :ok <- same_account(scope, organisation) do
      changeset =
        Ecto.Changeset.change(organisation,
          status: "archived",
          archived_at: DateTime.utc_now(:second),
          archived_by_user_id: scope.user.id
        )

      Multi.new()
      |> Multi.update(:organisation, changeset)
      |> Audit.multi_log(:audit, scope, "organisation.archived", & &1.organisation)
      |> Repo.transaction()
      |> case do
        {:ok, %{organisation: organisation}} -> {:ok, organisation}
        {:error, :organisation, changeset, _} -> {:error, changeset}
      end
    end
  end

  def archive_organisation(%Scope{}, %Organisation{}), do: {:error, :not_active}

  @doc """
  Restores an archived Organisation, if the plan has room for it.
  """
  def restore_organisation(%Scope{} = scope, %Organisation{status: "archived"} = organisation) do
    with :ok <- authorize(scope),
         :ok <- same_account(scope, organisation) do
      changeset =
        Ecto.Changeset.change(organisation,
          status: "active",
          archived_at: nil,
          archived_by_user_id: nil
        )

      Multi.new()
      |> lock_account(scope)
      |> Multi.run(:limit, fn _repo, _ -> check_limit(scope) end)
      |> Multi.update(:organisation, changeset)
      |> Audit.multi_log(:audit, scope, "organisation.restored", & &1.organisation)
      |> Repo.transaction()
      |> case do
        {:ok, %{organisation: organisation}} -> {:ok, organisation}
        {:error, :limit, reason, _} -> {:error, reason}
        {:error, :organisation, changeset, _} -> {:error, changeset}
      end
    end
  end

  def restore_organisation(%Scope{}, %Organisation{}), do: {:error, :not_archived}

  # Serialises limit checks for one account, so two requests cannot both
  # add the last allowed Organisation.
  defp lock_account(multi, scope) do
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

  defp check_limit(scope) do
    with :ok <- Billing.check(scope, :organisation), do: {:ok, :within_limit}
  end

  defp authorize(scope) do
    if Permissions.can_manage_organisations?(scope), do: :ok, else: {:error, :unauthorized}
  end

  defp same_account(scope, %Organisation{customer_account_id: account_id}) do
    if account_id == Scope.account_id!(scope), do: :ok, else: {:error, :unauthorized}
  end
end

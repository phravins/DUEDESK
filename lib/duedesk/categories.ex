defmodule DueDesk.Categories do
  @moduledoc """
  Account-level DueItem categories.

  Every new account gets a copy of the default (system) categories.
  Administrators and Super Admins can add custom categories and rename,
  archive or restore them; system categories cannot be changed.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias DueDesk.{Audit, Permissions, Repo}
  alias DueDesk.Accounts.Scope
  alias DueDesk.DueItems.Category

  @defaults [
    "GST & Income Tax",
    "Company / LLP Filings (ROC)",
    "Licences & Permits",
    "Labour Compliance (PF/ESI)",
    "Insurance",
    "Contracts & Agreements",
    "Property & Rent",
    "Vehicles",
    "Certifications",
    "Banking & Loans",
    "Subscriptions & Utilities",
    "Other"
  ]

  @doc "The default category names, in display order."
  def defaults, do: @defaults

  @doc """
  Adds an insert of the default categories to `multi`. `account_fun`
  receives the multi's changes and returns the Customer Account.
  """
  def multi_insert_defaults(%Multi{} = multi, name, account_fun) do
    Multi.insert_all(multi, name, Category, fn changes ->
      account = account_fun.(changes)
      now = DateTime.utc_now(:second)

      @defaults
      |> Enum.with_index(1)
      |> Enum.map(fn {category, position} ->
        %{
          id: Ecto.UUID.generate(),
          customer_account_id: account.id,
          name: category,
          system: true,
          status: "active",
          position: position,
          inserted_at: now,
          updated_at: now
        }
      end)
    end)
  end

  ## Reading

  @doc """
  Lists the account's categories: system categories in their default
  order, then custom categories by name.

  ## Options

    * `:status` - `"active"`, `"archived"` or `:all` (default)
  """
  def list_categories(%Scope{} = scope, opts \\ []) do
    account_id = Scope.account_id!(scope)

    from(c in Category,
      where: c.customer_account_id == ^account_id,
      order_by: [desc: c.system, asc: c.position, asc: fragment("lower(?)", c.name)]
    )
    |> filter_status(Keyword.get(opts, :status, :all))
    |> Repo.all()
  end

  defp filter_status(query, :all), do: query
  defp filter_status(query, status), do: where(query, [c], c.status == ^status)

  @doc """
  Gets a category of the scope's account. Raises `Ecto.NoResultsError`
  for another account's category.
  """
  def get_category!(%Scope{} = scope, id) do
    account_id = Scope.account_id!(scope)
    Repo.one!(from c in Category, where: c.id == ^id and c.customer_account_id == ^account_id)
  end

  @doc "Returns a changeset for a category form."
  def change_category(%Category{} = category, attrs \\ %{}) do
    Category.changeset(category, attrs)
  end

  ## Writing

  @doc "Adds a custom category."
  def create_category(%Scope{} = scope, attrs) do
    with :ok <- authorize(scope) do
      changeset =
        %Category{customer_account_id: Scope.account_id!(scope), system: false, position: 0}
        |> Category.changeset(attrs)

      Multi.new()
      |> Multi.insert(:category, changeset)
      |> Audit.multi_log(:audit, scope, "category.created", & &1.category,
        changes: &%{"name" => [nil, &1.category.name]}
      )
      |> run(:category)
    end
  end

  @doc "Renames a custom category."
  def rename_category(%Scope{} = scope, %Category{} = category, attrs) do
    with :ok <- authorize(scope),
         :ok <- editable(scope, category) do
      changeset = Category.changeset(category, attrs)

      Multi.new()
      |> Multi.update(:category, changeset)
      |> Audit.multi_log(:audit, scope, "category.renamed", & &1.category,
        changes: &%{"name" => [category.name, &1.category.name]}
      )
      |> run(:category)
    end
  end

  @doc "Archives a custom category. It stays on existing DueItems."
  def archive_category(%Scope{} = scope, %Category{status: "active"} = category) do
    set_status(scope, category, "archived", "category.archived")
  end

  def archive_category(%Scope{}, %Category{}), do: {:error, :not_active}

  @doc "Restores an archived custom category."
  def restore_category(%Scope{} = scope, %Category{status: "archived"} = category) do
    set_status(scope, category, "active", "category.restored")
  end

  def restore_category(%Scope{}, %Category{}), do: {:error, :not_archived}

  defp set_status(scope, category, status, action) do
    with :ok <- authorize(scope),
         :ok <- editable(scope, category) do
      archived_at = if status == "archived", do: DateTime.utc_now(:second)

      Multi.new()
      |> Multi.update(
        :category,
        Ecto.Changeset.change(category, status: status, archived_at: archived_at)
      )
      |> Audit.multi_log(:audit, scope, action, & &1.category)
      |> run(:category)
    end
  end

  defp run(multi, key) do
    case Repo.transaction(multi) do
      {:ok, changes} -> {:ok, Map.fetch!(changes, key)}
      {:error, ^key, changeset, _} -> {:error, changeset}
    end
  end

  defp authorize(scope) do
    if Permissions.can_manage_categories?(scope), do: :ok, else: {:error, :unauthorized}
  end

  defp editable(_scope, %Category{system: true}), do: {:error, :system_category}

  defp editable(scope, %Category{customer_account_id: account_id}) do
    if account_id == Scope.account_id!(scope), do: :ok, else: {:error, :unauthorized}
  end
end

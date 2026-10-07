defmodule DueDesk.Admin do
  @moduledoc """
  The internal operator console context.

  Operators can look at accounts for support purposes. They do not edit
  DueItems; any sensitive operator action is written to the audit log.
  """

  import Ecto.Query, warn: false

  alias DueDesk.{Audit, Repo}
  alias DueDesk.Admin.Operator
  alias DueDesk.Tenancy.{CustomerAccount, Membership}

  @doc "Creates an operator. Used by `mix duedesk.create_operator` and seeds."
  def create_operator(attrs) do
    %Operator{}
    |> Operator.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns the active operator for the email and password, or nil.
  """
  def get_operator_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    operator = Repo.get_by(Operator, email: email)
    if Operator.valid_password?(operator, password), do: operator
  end

  def get_active_operator(id) do
    Repo.get_by(Operator, id: id, active: true)
  end

  @doc "Records a successful operator login."
  def record_login(%Operator{} = operator) do
    {:ok, operator} =
      operator
      |> Ecto.Changeset.change(last_login_at: DateTime.utc_now(:second))
      |> Repo.update()

    Audit.log({:operator, operator}, "operator.logged_in", operator)
    operator
  end

  @doc """
  Lists Customer Accounts with member counts, optionally filtered by a
  name search.
  """
  def list_customer_accounts(opts \\ []) do
    search = opts |> Keyword.get(:search, "") |> String.trim()

    member_counts =
      from(m in Membership,
        where: m.status == "active",
        group_by: m.customer_account_id,
        select: %{customer_account_id: m.customer_account_id, count: count(m.id)}
      )

    query =
      from(a in CustomerAccount,
        left_join: mc in subquery(member_counts),
        on: mc.customer_account_id == a.id,
        order_by: [desc: a.inserted_at],
        limit: 200,
        select: %{account: a, member_count: coalesce(mc.count, 0)}
      )

    query =
      if search == "" do
        query
      else
        pattern = "%" <> String.replace(search, ~r/[\\%_]/, "\\\\\\0") <> "%"
        where(query, [a], ilike(a.name, ^pattern))
      end

    Repo.all(query)
  end
end

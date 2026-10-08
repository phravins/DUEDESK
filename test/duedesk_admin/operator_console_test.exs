defmodule DueDeskAdmin.OperatorConsoleTest do
  use DueDeskWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DueDesk.TenancyFixtures

  alias DueDesk.{Admin, Repo}
  alias DueDesk.Audit.AuditEvent

  @password "operator-password-123"

  setup do
    {:ok, operator} =
      Admin.create_operator(%{name: "Ops", email: "ops@duedesk.in", password: @password})

    %{operator: operator}
  end

  defp log_in(conn, password \\ @password) do
    post(conn, ~p"/admin/log-in", %{
      "operator" => %{"email" => "ops@duedesk.in", "password" => password}
    })
  end

  test "the console requires an operator session", %{conn: conn} do
    assert redirected_to(get(conn, ~p"/admin")) == ~p"/admin/log-in"
  end

  test "a customer user session does not open the console", %{conn: conn} do
    scope = account_scope_fixture()
    conn = log_in_user(conn, scope.user)
    assert redirected_to(get(conn, ~p"/admin")) == ~p"/admin/log-in"
  end

  test "rejects a wrong password", %{conn: conn} do
    conn = log_in(conn, "wrong password here")
    assert redirected_to(conn) == ~p"/admin/log-in"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password."
  end

  test "inactive operators cannot log in", %{conn: conn, operator: operator} do
    Repo.update!(Ecto.Changeset.change(operator, active: false))
    assert redirected_to(log_in(conn)) == ~p"/admin/log-in"
    refute Admin.get_operator_by_email_and_password("ops@duedesk.in", @password)
  end

  test "logs in, audits the login, lists and searches accounts", %{conn: conn, operator: op} do
    a = account_scope_fixture(nil, %{name: "Sharma Group"})
    _b = account_scope_fixture(nil, %{name: "Verma Traders"})
    DueDesk.OrganisationsFixtures.organisation_fixture(a)

    conn = log_in(conn)
    assert redirected_to(conn) == ~p"/admin"
    assert Repo.get_by(AuditEvent, action: "operator.logged_in", actor_id: op.id)

    {:ok, lv, html} = live(recycle(conn), ~p"/admin")
    assert html =~ "Customer Accounts"
    assert has_element?(lv, "#account-#{a.customer_account.id}", "Sharma Group")
    assert has_element?(lv, "#account-#{a.customer_account.id}-organisations", "1")
    assert html =~ "Verma Traders"

    html = lv |> form("#account-search", search: "sharma") |> render_change()
    assert html =~ "Sharma Group"
    refute html =~ "Verma Traders"

    html = lv |> form("#account-search", search: "100%_") |> render_change()
    assert html =~ "No accounts found."
  end

  test "logs out", %{conn: conn} do
    conn = conn |> log_in() |> recycle() |> delete(~p"/admin/log-out")
    assert redirected_to(conn) == ~p"/admin/log-in"
    assert redirected_to(get(recycle(conn), ~p"/admin")) == ~p"/admin/log-in"
  end
end

defmodule DueDeskAdmin.SessionController do
  use DueDeskWeb, :controller

  alias DueDesk.Admin
  alias DueDeskAdmin.OperatorAuth

  plug :put_view, html: DueDeskAdmin.SessionHTML

  def new(conn, _params) do
    render(conn, :new,
      form: Phoenix.Component.to_form(%{}, as: "operator"),
      page_title: "Operator log in"
    )
  end

  def create(conn, %{"operator" => %{"email" => email, "password" => password}}) do
    if operator = Admin.get_operator_by_email_and_password(email, password) do
      operator = Admin.record_login(operator)
      OperatorAuth.log_in_operator(conn, operator)
    else
      conn
      |> put_flash(:error, "Invalid email or password.")
      |> redirect(to: ~p"/admin/log-in")
    end
  end

  def delete(conn, _params), do: OperatorAuth.log_out_operator(conn)
end

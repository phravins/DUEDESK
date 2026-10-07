defmodule DueDeskAdmin.OperatorAuth do
  @moduledoc """
  Authentication for the internal operator console.

  Operators are a separate table from customer users. The session holds a
  signed token that expires after 8 hours.
  """
  use DueDeskWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias DueDesk.Admin

  @salt "operator session"
  @max_age 8 * 60 * 60

  def log_in_operator(conn, operator) do
    token = Phoenix.Token.sign(DueDeskWeb.Endpoint, @salt, operator.id)

    conn
    |> configure_session(renew: true)
    |> delete_session(:operator_token)
    |> put_session(:operator_token, token)
    |> redirect(to: ~p"/admin")
  end

  def log_out_operator(conn) do
    conn
    |> delete_session(:operator_token)
    |> configure_session(renew: true)
    |> redirect(to: ~p"/admin/log-in")
  end

  @doc "Plug: assigns `:current_operator` from the session, or nil."
  def fetch_current_operator(conn, _opts) do
    assign(conn, :current_operator, operator_from_token(get_session(conn, :operator_token)))
  end

  @doc "Plug: halts unless an operator is logged in."
  def require_operator(conn, _opts) do
    if conn.assigns[:current_operator] do
      conn
    else
      conn
      |> redirect(to: ~p"/admin/log-in")
      |> halt()
    end
  end

  def on_mount(:require_operator, _params, session, socket) do
    case operator_from_token(session["operator_token"]) do
      nil -> {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/admin/log-in")}
      operator -> {:cont, Phoenix.Component.assign(socket, :current_operator, operator)}
    end
  end

  defp operator_from_token(nil), do: nil

  defp operator_from_token(token) do
    case Phoenix.Token.verify(DueDeskWeb.Endpoint, @salt, token, max_age: @max_age) do
      {:ok, id} -> Admin.get_active_operator(id)
      _ -> nil
    end
  end
end

defmodule DueDeskWeb.PageController do
  use DueDeskWeb, :controller

  def home(conn, _params) do
    case conn.assigns.current_scope do
      %{user: %{}} -> redirect(conn, to: ~p"/dashboard")
      _ -> redirect(conn, to: ~p"/users/log-in")
    end
  end

  def terms(conn, _params), do: render(conn, :terms, page_title: "Terms of service")

  def privacy(conn, _params), do: render(conn, :privacy, page_title: "Privacy policy")
end

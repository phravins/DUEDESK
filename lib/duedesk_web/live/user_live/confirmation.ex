defmodule DueDeskWeb.UserLive.Confirmation do
  @moduledoc """
  Confirms an email address from the link sent after sign up. The user then
  logs in with their password; the link itself never creates a session.
  """
  use DueDeskWeb, :live_view

  alias DueDesk.Accounts

  @impl true
  def render(assigns), do: ~H""

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.confirm_user(token) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email confirmed. Log in to set up your DueDesk account.")

        {:error, _} ->
          put_flash(
            socket,
            :error,
            "This confirmation link is invalid or has expired. Log in to receive a new one."
          )
      end

    target = if socket.assigns.current_scope, do: ~p"/dashboard", else: ~p"/users/log-in"
    {:ok, push_navigate(socket, to: target)}
  end
end

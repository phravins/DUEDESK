defmodule DueDeskWeb.UserSessionController do
  use DueDeskWeb, :controller

  alias DueDesk.{Accounts, Tenancy}
  alias DueDeskWeb.UserAuth

  def create(conn, %{"user" => user_params}) do
    create(conn, user_params, "Welcome back!")
  end

  defp create(conn, %{"email" => email, "password" => password} = user_params, info) do
    case Accounts.get_user_by_email_and_password(email, password) do
      %{confirmed_at: nil} = user ->
        # Correct password, so revealing the unconfirmed state is safe.
        Accounts.deliver_user_confirmation_instructions(user, &url(~p"/users/confirm/#{&1}"))

        conn
        |> put_flash(
          :error,
          "Please confirm your email address before logging in. We have sent a new confirmation link to #{user.email}."
        )
        |> redirect(to: ~p"/users/log-in")

      %{} = user ->
        conn
        |> put_flash(:info, info)
        |> UserAuth.log_in_user(user, user_params)

      nil ->
        # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
        conn
        |> put_flash(:error, "Invalid email or password.")
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def update_password(conn, %{"user" => user_params}) do
    user = conn.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)
    {:ok, {_user, expired_tokens}} = Accounts.update_user_password(user, user_params)

    UserAuth.disconnect_sessions(expired_tokens)

    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create(Map.put(user_params, "email", user.email), "Password updated successfully.")
  end

  # Pages that ask for the password again before they open.
  @confirm_paths ["/account/super-admins"]

  @doc """
  Asks a signed-in user for their password again, then returns them to
  `to` (one of a few known pages).
  """
  def confirm(conn, %{"to" => to}) when to in @confirm_paths do
    conn
    |> put_session(:user_return_to, to)
    |> redirect(to: ~p"/users/log-in")
  end

  def confirm(conn, _params), do: redirect(conn, to: ~p"/dashboard")

  @doc """
  "Log in to accept" on an invitation: logs in, then returns to the
  invitation page with the invited email filled in.
  """
  def invitation(conn, %{"token" => token}) do
    case Tenancy.get_invitation_by_token(token) do
      nil ->
        redirect(conn, to: ~p"/invitations/#{token}")

      invitation ->
        conn
        |> put_session(:user_return_to, ~p"/invitations/#{token}")
        |> put_flash(:email, invitation.email)
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end

defmodule DueDeskWeb.UserLive.ConfirmationTest do
  use DueDeskWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DueDesk.AccountsFixtures

  alias DueDesk.Accounts

  setup do
    user = unconfirmed_user_fixture()

    token =
      extract_user_token(fn url ->
        Accounts.deliver_user_confirmation_instructions(user, url)
      end)

    %{user: user, token: token}
  end

  test "confirms the email and sends the user to log in without a session", %{
    conn: conn,
    user: user,
    token: token
  } do
    {:ok, _lv, html} =
      conn
      |> live(~p"/users/confirm/#{token}")
      |> follow_redirect(conn, ~p"/users/log-in")

    assert html =~ "Email confirmed"
    assert Accounts.get_user!(user.id).confirmed_at
  end

  test "rejects an invalid token", %{conn: conn, user: user} do
    {:ok, _lv, html} =
      conn
      |> live(~p"/users/confirm/oops")
      |> follow_redirect(conn, ~p"/users/log-in")

    assert html =~ "invalid or has expired"
    refute Accounts.get_user!(user.id).confirmed_at
  end

  test "a token works only once", %{conn: conn, token: token} do
    {:ok, _} = Accounts.confirm_user(token)

    {:ok, _lv, html} =
      conn
      |> live(~p"/users/confirm/#{token}")
      |> follow_redirect(conn, ~p"/users/log-in")

    assert html =~ "invalid or has expired"
  end
end

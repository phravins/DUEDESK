defmodule DueDeskWeb.UserLive.ResetPasswordTest do
  use DueDeskWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DueDesk.AccountsFixtures

  alias DueDesk.Accounts

  describe "forgot password" do
    test "sends a reset link to a registered email", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password")

      {:ok, _lv, html} =
        lv
        |> form("#reset_password_form", user: %{email: user.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "If that email is registered"

      assert DueDesk.Repo.get_by(Accounts.UserToken,
               user_id: user.id,
               context: "reset_password"
             )
    end

    test "gives the same answer for unknown emails", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password")

      {:ok, _lv, html} =
        lv
        |> form("#reset_password_form", user: %{email: "nobody@example.com"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "If that email is registered"
    end
  end

  describe "reset password" do
    setup do
      user = user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      %{user: user, token: token}
    end

    test "sets a new password", %{conn: conn, user: user, token: token} do
      {:ok, lv, html} = live(conn, ~p"/users/reset-password/#{token}")
      assert html =~ "Choose a new password"

      {:ok, _lv, html} =
        lv
        |> form("#new_password_form",
          user: %{password: "my new password", password_confirmation: "my new password"}
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "Password reset"
      assert Accounts.get_user_by_email_and_password(user.email, "my new password")
    end

    test "shows validation errors", %{conn: conn, token: token} do
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password/#{token}")

      html =
        lv
        |> form("#new_password_form", user: %{password: "short", password_confirmation: "x"})
        |> render_submit()

      assert html =~ "should be at least 10 character"
      assert html =~ "does not match password"
    end

    test "rejects an invalid token", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/users/reset-password", flash: flash}}} =
               live(conn, ~p"/users/reset-password/oops")

      assert flash["error"] =~ "invalid or has expired"
    end
  end
end

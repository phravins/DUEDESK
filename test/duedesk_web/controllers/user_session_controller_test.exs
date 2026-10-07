defmodule DueDeskWeb.UserSessionControllerTest do
  use DueDeskWeb.ConnCase, async: true

  import DueDesk.AccountsFixtures
  import DueDesk.TenancyFixtures

  setup do
    %{user: account_scope_fixture().user}
  end

  describe "POST /users/log-in" do
    test "logs the user in and lands on the dashboard", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/dashboard"

      conn = get(conn, ~p"/dashboard")
      response = html_response(conn, 200)
      assert response =~ user.name
      assert response =~ ~p"/users/settings"
      assert response =~ ~p"/users/log-out"
    end

    test "logs the user in with remember me", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_due_desk_web_user_remember_me"]
      assert redirected_to(conn) == ~p"/dashboard"
    end

    test "logs the user in with return to", %{conn: conn, user: user} do
      conn =
        conn
        |> init_test_session(user_return_to: "/foo/bar")
        |> post(~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert redirected_to(conn) == "/foo/bar"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome back!"
    end

    test "sends users without an account to onboarding", %{conn: conn} do
      user = user_fixture()

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      conn = get(recycle(conn), ~p"/dashboard")
      assert redirected_to(conn) == ~p"/onboarding/account"
    end

    test "refuses unconfirmed users and resends the confirmation", %{conn: conn} do
      user = unconfirmed_user_fixture()

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "confirm your email"

      assert DueDesk.Repo.get_by(DueDesk.Accounts.UserToken, user_id: user.id, context: "confirm")
    end

    test "redirects to login page with invalid credentials", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => "invalid_password"}
        })

      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password."
      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "does not reveal whether an unconfirmed email exists on a wrong password", %{conn: conn} do
      user = unconfirmed_user_fixture()

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => "wrong password!"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password."
    end
  end

  describe "DELETE /users/log-out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end
  end
end

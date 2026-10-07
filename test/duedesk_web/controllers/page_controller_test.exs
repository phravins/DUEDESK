defmodule DueDeskWeb.PageControllerTest do
  use DueDeskWeb.ConnCase, async: true

  import DueDesk.AccountsFixtures

  test "GET / sends visitors to log in", %{conn: conn} do
    assert conn |> get(~p"/") |> redirected_to() == ~p"/users/log-in"
  end

  test "GET / sends signed-in users to the dashboard", %{conn: conn} do
    conn = conn |> log_in_user(user_fixture()) |> get(~p"/")
    assert redirected_to(conn) == ~p"/dashboard"
  end

  test "GET /pricing no longer exists", %{conn: conn} do
    assert conn |> get("/pricing") |> response(404)
  end
end

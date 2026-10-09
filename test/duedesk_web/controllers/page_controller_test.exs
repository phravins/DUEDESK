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

  test "GET /terms and /privacy are public", %{conn: conn} do
    terms = conn |> get(~p"/terms") |> html_response(200)
    assert terms =~ ~s(id="terms")
    assert terms =~ ~s(href="/privacy")

    privacy = build_conn() |> get(~p"/privacy") |> html_response(200)
    assert privacy =~ ~s(id="privacy")
    assert privacy =~ ~s(href="/terms")
  end
end

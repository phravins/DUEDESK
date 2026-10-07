defmodule DueDeskWeb.UserLive.RegistrationTest do
  use DueDeskWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DueDesk.AccountsFixtures

  describe "Registration page" do
    test "renders registration page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register")

      assert html =~ "Create your DueDesk account"
      assert html =~ "Mobile number"
    end

    test "redirects if already logged in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn
               |> log_in_user(user_fixture())
               |> live(~p"/users/register")
    end

    test "renders errors for invalid data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(
          user: %{"email" => "with spaces", "mobile_number" => "123", "password" => "short"}
        )

      assert result =~ "must be a valid email address"
      assert result =~ "must be a 10-digit Indian mobile number"
      assert result =~ "should be at least 10 character"
    end
  end

  describe "register user" do
    test "creates an unconfirmed account and sends a confirmation email", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()
      form = form(lv, "#registration_form", user: valid_user_attributes(email: email))

      {:ok, _lv, html} =
        render_submit(form)
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "We have sent a confirmation link to #{email}"

      user = DueDesk.Accounts.get_user_by_email(email)
      assert user.mobile_number == "+919876543210"
      refute user.confirmed_at
      assert DueDesk.Repo.get_by(DueDesk.Accounts.UserToken, user_id: user.id, context: "confirm")
    end

    test "renders errors for duplicated email", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      user = user_fixture(%{email: "test@email.com"})

      result =
        lv
        |> form("#registration_form", user: valid_user_attributes(email: user.email))
        |> render_submit()

      assert result =~ "has already been taken"
    end
  end
end

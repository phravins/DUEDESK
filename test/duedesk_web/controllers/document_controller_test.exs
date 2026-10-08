defmodule DueDeskWeb.DocumentControllerTest do
  use DueDeskWeb.ConnCase, async: true

  import DueDesk.TenancyFixtures
  import DueDesk.DueItemsFixtures
  import DueDesk.DocumentsFixtures

  @not_available "This DueItem is not available to your account access."

  setup do
    owner = account_scope_fixture()
    user = member_scope_fixture(owner, "user")
    item = due_item_fixture(owner, primary_user_id: user.user.id)

    document =
      document_fixture(user, item, filename: "Fire NOC <2027>.pdf", contents: "%PDF-1.4 noc")

    %{owner: owner, user: user, item: item, document: document}
  end

  test "an assigned User downloads the file as an attachment", ctx do
    conn = ctx.conn |> log_in_user(ctx.user.user) |> get(~p"/documents/#{ctx.document}/download")

    assert response(conn, 200) == "%PDF-1.4 noc"
    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ ~r/^attachment; /
    assert disposition =~ "filename*=utf-8''Fire%20NOC%20%3C2027%3E.pdf"
    assert get_resp_header(conn, "content-type") |> hd() =~ "application/pdf"
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
  end

  test "an Administrator of the account downloads it", ctx do
    admin = member_scope_fixture(ctx.owner, "admin")
    conn = ctx.conn |> log_in_user(admin.user) |> get(~p"/documents/#{ctx.document}/download")
    assert response(conn, 200) == "%PDF-1.4 noc"
  end

  test "an unassigned User, another account or a guessed id is turned away", ctx do
    colleague = member_scope_fixture(ctx.owner, "user")
    stranger = account_scope_fixture()

    for {scope, id} <- [
          {colleague, ctx.document.id},
          {stranger, ctx.document.id},
          {ctx.owner, Ecto.UUID.generate()},
          {ctx.owner, "not-a-uuid"}
        ] do
      conn = build_conn() |> log_in_user(scope.user) |> get(~p"/documents/#{id}/download")

      assert redirected_to(conn) == ~p"/due-items"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == @not_available
    end
  end

  test "a visitor must log in", ctx do
    conn = get(ctx.conn, ~p"/documents/#{ctx.document}/download")
    assert redirected_to(conn) == ~p"/users/log-in"
  end

  test "someone without an account is sent to create one", ctx do
    user = DueDesk.AccountsFixtures.user_fixture()
    conn = ctx.conn |> log_in_user(user) |> get(~p"/documents/#{ctx.document}/download")
    assert redirected_to(conn) == ~p"/onboarding/account"
  end
end

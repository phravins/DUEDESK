defmodule DueDesk.Notifications.RecipientsTest do
  use DueDesk.DataCase, async: true

  import DueDesk.TenancyFixtures
  import DueDesk.DueItemsFixtures

  alias DueDesk.Repo
  alias DueDesk.Notifications.Recipients

  setup do
    owner = account_scope_fixture() |> put_plan("business")
    admin = member_scope_fixture(owner, "admin")
    user_a = member_scope_fixture(owner, "user")
    user_b = member_scope_fixture(owner, "user")
    %{owner: owner, admin: admin, user_a: user_a, user_b: user_b}
  end

  defp members(ctx), do: Recipients.members(ctx.owner.customer_account.id)

  test "before the date: the Primary first, then the Additional Assignees", ctx do
    item =
      due_item_fixture(ctx.admin,
        primary_user_id: ctx.user_b.user.id,
        additional_user_ids: [ctx.user_a.user.id]
      )

    assert Recipients.resolve(item, false, members(ctx)) == [
             ctx.user_b.user.id,
             ctx.user_a.user.id
           ]
  end

  test "escalated: the assignees plus every Administrator and Super Admin, once each", ctx do
    item = due_item_fixture(ctx.admin, primary_user_id: ctx.admin.user.id)
    [first | rest] = Recipients.resolve(item, true, members(ctx))

    assert first == ctx.admin.user.id
    assert Enum.sort(rest) == [ctx.owner.user.id]
  end

  test "an unassigned DueItem reaches nobody until it is escalated", ctx do
    item = due_item_fixture(ctx.admin, %{})

    assert Recipients.resolve(item, false, members(ctx)) == []

    assert Enum.sort(Recipients.resolve(item, true, members(ctx))) ==
             Enum.sort([ctx.owner.user.id, ctx.admin.user.id])
  end

  test "deactivated members receive nothing", ctx do
    item = due_item_fixture(ctx.admin, primary_user_id: ctx.user_a.user.id)
    ctx.user_a.membership |> Ecto.Changeset.change(status: "deactivated") |> Repo.update!()

    assert Recipients.resolve(item, false, members(ctx)) == []
  end

  test "members of other accounts are never included", ctx do
    other = account_scope_fixture()
    item = due_item_fixture(ctx.admin, %{})
    refute other.user.id in Recipients.resolve(item, true, members(ctx))
  end

  describe "channels/1" do
    test "email when turned on; WhatsApp only when it is available", ctx do
      member = members(ctx)[ctx.user_a.user.id]
      assert Recipients.channels(member) == ["email"]
      assert Recipients.channels(%{member | notify_email: false}) == []

      wants_whatsapp = %{member | notify_whatsapp: true, whatsapp_consent_at: DateTime.utc_now()}
      # WhatsApp is not configured in tests.
      refute Recipients.whatsapp?(wants_whatsapp)
    end
  end
end

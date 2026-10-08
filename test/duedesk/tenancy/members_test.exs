defmodule DueDesk.Tenancy.MembersTest do
  use DueDesk.DataCase, async: true

  import DueDesk.AccountsFixtures
  import DueDesk.TenancyFixtures
  import DueDesk.DueItemsFixtures

  alias DueDesk.{Billing, DueItems, Repo, Tenancy}
  alias DueDesk.Accounts.{Scope, User}
  alias DueDesk.Audit.AuditEvent
  alias DueDesk.DueItems.DueItem
  alias DueDesk.Notifications.Delivery
  alias DueDesk.Tenancy.{Invitation, Membership}

  defp audit(action) do
    Repo.all(from e in AuditEvent, where: e.action == ^action, order_by: e.inserted_at)
  end

  defp url(token), do: "[TOKEN]#{token}[TOKEN]"

  defp register_attrs,
    do: %{"name" => "Neha Rao", "mobile_number" => "98765 43211", "password" => "a long password"}

  describe "invite_member/3" do
    setup do
      %{owner: account_scope_fixture() |> put_plan("business")}
    end

    test "Super Admins invite Administrators and Users; Administrators only Users", %{
      owner: owner
    } do
      admin = member_scope_fixture(owner, "admin")

      assert {:ok, %Invitation{role: "admin"}} =
               Tenancy.invite_member(
                 owner,
                 %{"email" => "a@example.com", "role" => "admin"},
                 &url/1
               )

      assert {:ok, %Invitation{role: "user"}} =
               Tenancy.invite_member(
                 admin,
                 %{"email" => "u@example.com", "role" => "user"},
                 &url/1
               )

      assert {:error, %Ecto.Changeset{} = changeset} =
               Tenancy.invite_member(
                 admin,
                 %{"email" => "b@example.com", "role" => "admin"},
                 &url/1
               )

      assert "choose a role you can invite" in errors_on(changeset).role

      user = member_scope_fixture(owner, "user")

      assert {:error, :unauthorized} =
               Tenancy.invite_member(
                 user,
                 %{"email" => "c@example.com", "role" => "user"},
                 &url/1
               )

      assert {:error, %Ecto.Changeset{}} =
               Tenancy.invite_member(
                 owner,
                 %{"email" => "d@example.com", "role" => "super_admin"},
                 &url/1
               )
    end

    test "emails a link and stores only the token's hash", %{owner: owner} do
      {invitation, token} = invitation_fixture(owner, %{"email" => "neha@example.com"})

      assert invitation.token_hash ==
               :crypto.hash(:sha256, Base.url_decode64!(token, padding: false))

      assert DateTime.diff(invitation.expires_at, DateTime.utc_now(), :day) in 6..7
      assert Tenancy.get_invitation_by_token(token).id == invitation.id

      [event] = audit("invitation.created")

      assert event.metadata == %{
               "email" => "neha@example.com",
               "role" => "user",
               "replaced" => false
             }

      refute inspect(event) =~ token
      refute inspect(Repo.reload!(invitation)) =~ token
    end

    test "inviting a pending address again replaces its link", %{owner: owner} do
      {first, old_token} = invitation_fixture(owner, %{"email" => "neha@example.com"})

      {second, new_token} =
        invitation_fixture(owner, %{"email" => "neha@example.com", "role" => "admin"})

      assert first.id == second.id
      assert second.role == "admin"
      assert Tenancy.get_invitation_by_token(old_token) == nil
      assert Tenancy.get_invitation_by_token(new_token).id == first.id
      assert Repo.aggregate(Invitation, :count) == 1
    end

    test "rejects active and deactivated members' addresses", %{owner: owner} do
      member = member_scope_fixture(owner, "user")

      assert {:error, changeset} =
               Tenancy.invite_member(
                 owner,
                 %{"email" => member.user.email, "role" => "user"},
                 &url/1
               )

      assert "is already a member of this account" in errors_on(changeset).email

      {:ok, _} = Tenancy.deactivate_member(owner, member.membership)

      assert {:error, changeset} =
               Tenancy.invite_member(
                 owner,
                 %{"email" => member.user.email, "role" => "user"},
                 &url/1
               )

      assert [message] = errors_on(changeset).email
      assert message =~ "Reactivate"
    end

    test "pending invitations take a seat" do
      owner = account_scope_fixture()
      _ = member_scope_fixture(owner, "user")
      {_, _} = invitation_fixture(owner)

      assert Billing.seats(owner) == %{used: 2, limit: 2}

      assert {:error, {:limit_reached, %{resource: :member}}} =
               Tenancy.invite_member(
                 owner,
                 %{"email" => "x@example.com", "role" => "user"},
                 &url/1
               )
    end

    test "expired invitations free their seat" do
      owner = account_scope_fixture()
      _ = member_scope_fixture(owner, "user")
      {invitation, _} = invitation_fixture(owner)

      expire(invitation)

      assert {:ok, _} =
               Tenancy.invite_member(
                 owner,
                 %{"email" => "x@example.com", "role" => "user"},
                 &url/1
               )
    end
  end

  defp expire(invitation) do
    invitation
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(:second), -60))
    |> Repo.update!()
  end

  describe "resend_invitation/3 and revoke_invitation/2" do
    setup do
      owner = account_scope_fixture() |> put_plan("business")
      {invitation, token} = invitation_fixture(owner)
      %{owner: owner, invitation: invitation, token: token}
    end

    test "resending sends a new link and the old one stops working", ctx do
      assert {:ok, resent} = Tenancy.resend_invitation(ctx.owner, ctx.invitation, &url/1)
      new_token = invitation_token(resent.email)

      assert new_token != ctx.token
      assert Tenancy.get_invitation_by_token(ctx.token) == nil
      assert Tenancy.get_invitation_by_token(new_token).id == ctx.invitation.id
      assert [_] = audit("invitation.resent")
    end

    test "an expired invitation can be sent again with a fresh expiry", ctx do
      expired = expire(ctx.invitation)

      assert {:error, :expired} =
               Tenancy.accept_invitation(
                 Scope.for_user(user_fixture(email: expired.email)),
                 ctx.token
               )

      assert {:ok, resent} = Tenancy.resend_invitation(ctx.owner, expired, &url/1)
      assert Invitation.state(resent) == :pending
    end

    test "revoking frees the seat and kills the link", ctx do
      assert Billing.seats(ctx.owner).used == 1
      assert {:ok, revoked} = Tenancy.revoke_invitation(ctx.owner, ctx.invitation)
      assert Billing.seats(ctx.owner).used == 0
      assert Invitation.state(revoked) == :revoked
      assert [event] = audit("invitation.revoked")
      assert event.metadata["email"] == ctx.invitation.email

      assert {:error, :revoked} =
               Tenancy.register_and_accept_invitation(ctx.token, register_attrs())

      assert {:error, :closed} = Tenancy.revoke_invitation(ctx.owner, revoked)
      assert {:error, :closed} = Tenancy.resend_invitation(ctx.owner, revoked, &url/1)
    end

    test "Administrators can't touch Administrator invitations", ctx do
      {invitation, _} = invitation_fixture(ctx.owner, %{"role" => "admin"})
      admin = member_scope_fixture(ctx.owner, "admin")

      assert {:error, :unauthorized} = Tenancy.revoke_invitation(admin, invitation)
      assert {:error, :unauthorized} = Tenancy.resend_invitation(admin, invitation, &url/1)
    end

    test "other accounts can't touch the invitation", ctx do
      other = account_scope_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        Tenancy.get_invitation!(other, ctx.invitation.id)
      end

      assert {:error, :unauthorized} = Tenancy.revoke_invitation(other, ctx.invitation)
      assert Tenancy.list_open_invitations(other) == []
    end
  end

  describe "accepting invitations" do
    setup do
      owner = account_scope_fixture() |> put_plan("business")
      {invitation, token} = invitation_fixture(owner, %{"email" => "neha@example.com"})
      %{owner: owner, invitation: invitation, token: token}
    end

    test "a new person signs up, confirmed, with the invited email", ctx do
      attrs = Map.put(register_attrs(), "email", "someone.else@example.com")

      assert {:ok, %User{} = user} = Tenancy.register_and_accept_invitation(ctx.token, attrs)
      assert user.email == "neha@example.com"
      assert user.confirmed_at
      assert %Membership{role: "user", status: "active"} = Tenancy.get_current_membership(user)
      assert Repo.reload!(ctx.invitation).accepted_at
      assert [event] = audit("invitation.accepted")
      assert event.actor_id == user.id
      assert event.customer_account_id == ctx.owner.customer_account.id

      assert {:error, :accepted} =
               Tenancy.register_and_accept_invitation(ctx.token, register_attrs())
    end

    test "sign-up errors come back as a changeset", ctx do
      assert {:error, %Ecto.Changeset{} = changeset} =
               Tenancy.register_and_accept_invitation(ctx.token, %{"name" => "N"})

      assert errors_on(changeset).password
      assert Repo.reload!(ctx.invitation).accepted_at == nil
    end

    test "someone with a login accepts with the matching email", ctx do
      user = user_fixture(email: "neha@example.com")

      assert {:ok, %Membership{role: "user"}} =
               Tenancy.accept_invitation(Scope.for_user(user), ctx.token)

      assert Tenancy.get_current_membership(user).customer_account_id ==
               ctx.owner.customer_account.id
    end

    test "the wrong email is refused", ctx do
      user = user_fixture()

      assert {:error, :wrong_email} = Tenancy.accept_invitation(Scope.for_user(user), ctx.token)
      assert Repo.reload!(ctx.invitation).accepted_at == nil
    end

    test "someone already working in another account is refused", ctx do
      other = account_scope_fixture(user_fixture(email: "neha@example.com"))

      assert {:error, :already_member} = Tenancy.accept_invitation(other, ctx.token)
    end

    test "unknown and malformed tokens reveal nothing" do
      user = user_fixture(email: "neha@example.com")
      bad = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

      for token <- [bad, "nope", ""] do
        assert Tenancy.get_invitation_by_token(token) == nil
        assert {:error, :invalid} = Tenancy.accept_invitation(Scope.for_user(user), token)

        assert {:error, :invalid} =
                 Tenancy.register_and_accept_invitation(token, register_attrs())
      end
    end

    test "accepting re-checks the seats" do
      owner = account_scope_fixture()
      {_invitation, token} = invitation_fixture(owner)
      # Members added outside the invitation flow fill the plan.
      _ = member_scope_fixture(owner, "user")
      _ = member_scope_fixture(owner, "user")

      assert {:error, {:limit_reached, _}} =
               Tenancy.register_and_accept_invitation(token, register_attrs())
    end
  end

  describe "deactivate_member/3" do
    setup do
      owner = account_scope_fixture() |> put_plan("business")
      admin = member_scope_fixture(owner, "admin")
      leaver = member_scope_fixture(owner, "user")
      other = member_scope_fixture(owner, "user")

      as_primary = due_item_fixture(owner, %{"primary_user_id" => leaver.user.id})

      as_additional =
        due_item_fixture(owner, %{
          "primary_user_id" => owner.user.id,
          "additional_user_ids" => [leaver.user.id]
        })

      with_other =
        due_item_fixture(owner, %{
          "primary_user_id" => other.user.id,
          "additional_user_ids" => [leaver.user.id]
        })

      archived = due_item_fixture(owner, %{"primary_user_id" => leaver.user.id})
      {:ok, _} = DueItems.archive_due_item(owner, archived)

      %{
        owner: owner,
        admin: admin,
        leaver: leaver,
        other: other,
        as_primary: as_primary,
        as_additional: as_additional,
        with_other: with_other,
        archived: archived
      }
    end

    defp people(ctx, item) do
      item = reload(ctx.owner, item)
      primary = DueItem.primary_user(item)
      {primary && primary.id, item |> DueItem.additional_users() |> Enum.map(& &1.id)}
    end

    test "counts assigned active DueItems", ctx do
      assert Tenancy.assigned_counts(ctx.owner)[ctx.leaver.user.id] == 3
    end

    test "Reassign Now moves every assignment without duplicates", ctx do
      Repo.delete_all(Delivery)

      assert {:ok, %{membership: membership, due_items: 3}} =
               Tenancy.deactivate_member(ctx.owner, ctx.leaver.membership, ctx.other.user.id)

      assert membership.status == "deactivated"
      assert membership.deactivated_at

      assert people(ctx, ctx.as_primary) == {ctx.other.user.id, []}
      assert people(ctx, ctx.as_additional) == {ctx.owner.user.id, [ctx.other.user.id]}
      assert people(ctx, ctx.with_other) == {ctx.other.user.id, []}
      assert people(ctx, ctx.archived) == {nil, []}

      notified =
        Repo.all(
          from d in Delivery,
            where: d.kind == "assignment" and d.user_id == ^ctx.other.user.id,
            select: d.due_item_id
        )

      assert Enum.sort(notified) == Enum.sort([ctx.as_primary.id, ctx.as_additional.id])

      assert [event] = audit("member.deactivated")
      assert event.metadata["due_items"] == 3
      assert event.metadata["reassigned_to"] == ctx.other.user.id
      assert length(audit("due_item.assigned")) >= 3

      assert Tenancy.get_current_membership(ctx.leaver.user) == nil
      assert Tenancy.assigned_counts(ctx.owner)[ctx.leaver.user.id] == nil
    end

    test "Leave Unassigned ends the assignments", ctx do
      assert {:ok, %{due_items: 3}} = Tenancy.deactivate_member(ctx.owner, ctx.leaver.membership)

      assert people(ctx, ctx.as_primary) == {nil, []}
      assert people(ctx, ctx.as_additional) == {ctx.owner.user.id, []}
      assert people(ctx, ctx.with_other) == {ctx.other.user.id, []}

      unassigned = DueItems.list_due_items(ctx.owner, %{"queue" => "unassigned"})
      assert ctx.as_primary.id in Enum.map(unassigned, & &1.id)
    end

    test "the takeover must be another active member of the account", ctx do
      stranger = account_scope_fixture()

      for target <- [stranger.user.id, ctx.leaver.user.id] do
        assert {:error, :invalid_target} =
                 Tenancy.deactivate_member(ctx.owner, ctx.leaver.membership, target)
      end

      {:ok, _} = Tenancy.deactivate_member(ctx.owner, ctx.other.membership)

      assert {:error, :invalid_target} =
               Tenancy.deactivate_member(ctx.owner, ctx.leaver.membership, ctx.other.user.id)

      assert Tenancy.get_current_membership(ctx.leaver.user)
    end

    test "who can deactivate whom", ctx do
      second_admin = member_scope_fixture(ctx.owner, "admin")

      assert {:error, :unauthorized} =
               Tenancy.deactivate_member(ctx.admin, second_admin.membership)

      assert {:error, :unauthorized} = Tenancy.deactivate_member(ctx.admin, ctx.owner.membership)
      assert {:error, :unauthorized} = Tenancy.deactivate_member(ctx.admin, ctx.admin.membership)
      assert {:error, :unauthorized} = Tenancy.deactivate_member(ctx.owner, ctx.owner.membership)
      assert {:error, :unauthorized} = Tenancy.deactivate_member(ctx.other, ctx.leaver.membership)

      assert {:ok, _} = Tenancy.deactivate_member(ctx.admin, ctx.leaver.membership)
      assert {:ok, _} = Tenancy.deactivate_member(ctx.owner, second_admin.membership)
      assert {:error, :not_active} = Tenancy.deactivate_member(ctx.owner, ctx.leaver.membership)
    end

    test "reactivating needs a free seat", ctx do
      {:ok, %{membership: m}} = Tenancy.deactivate_member(ctx.owner, ctx.leaver.membership)

      # Business has 5 seats: admin and other are active, so fill two more
      # with invitations and one with a member.
      _ = invitation_fixture(ctx.owner)
      _ = invitation_fixture(ctx.owner)
      _ = member_scope_fixture(ctx.owner, "user")

      assert {:error, {:limit_reached, _}} = Tenancy.reactivate_member(ctx.owner, m)

      [invitation | _] = Tenancy.list_open_invitations(ctx.owner)
      {:ok, _} = Tenancy.revoke_invitation(ctx.owner, invitation)

      assert {:ok, %Membership{status: "active", deactivated_at: nil}} =
               Tenancy.reactivate_member(ctx.owner, m)

      assert [_] = audit("member.reactivated")
      assert Tenancy.get_current_membership(ctx.leaver.user)
    end
  end

  describe "change_member_role/3" do
    setup do
      owner = account_scope_fixture()
      %{owner: owner, member: member_scope_fixture(owner, "user")}
    end

    test "Super Admins switch Users and Administrators, who are told by email", ctx do
      assert {:ok, %Membership{role: "admin"}} =
               Tenancy.change_member_role(ctx.owner, ctx.member.membership, "admin")

      subject = "Your role in #{ctx.owner.customer_account.name} is now Administrator"
      assert_received {:email, %Swoosh.Email{subject: ^subject}}
      assert [event] = audit("member.role_changed")
      assert event.changes == %{"role" => ["user", "admin"]}

      member = Tenancy.get_membership!(ctx.owner, ctx.member.membership.id)

      assert {:ok, %Membership{role: "user"}} =
               Tenancy.change_member_role(ctx.owner, member, "user")

      assert {:error, :unchanged} = Tenancy.change_member_role(ctx.owner, member, "user")
    end

    test "Administrators can't change roles", ctx do
      admin = member_scope_fixture(ctx.owner, "admin")

      assert {:error, :unauthorized} =
               Tenancy.change_member_role(admin, ctx.member.membership, "admin")

      assert {:error, :unauthorized} =
               Tenancy.change_member_role(ctx.owner, ctx.owner.membership, "admin")
    end
  end

  describe "Super Admins" do
    test "need a recent password entry" do
      owner = account_scope_fixture() |> put_plan("entrepreneur")
      admin = member_scope_fixture(owner, "admin")

      assert {:error, :reauthenticate} = Tenancy.appoint_super_admin(owner, admin.membership)
      assert {:error, :unauthorized} = Tenancy.appoint_super_admin(sudo(admin), admin.membership)
    end

    test "on multi Super Admin plans, Administrators are appointed up to the limit" do
      owner = account_scope_fixture() |> put_plan("entrepreneur") |> sudo()
      [a, b, c] = for _ <- 1..3, do: member_scope_fixture(owner, "admin")
      user = member_scope_fixture(owner, "user")

      assert {:error, :not_admin} = Tenancy.appoint_super_admin(owner, user.membership)
      assert {:ok, _} = Tenancy.appoint_super_admin(owner, a.membership)
      assert {:ok, _} = Tenancy.appoint_super_admin(owner, b.membership)

      assert {:error, {:limit_reached, %{resource: :super_admin}}} =
               Tenancy.appoint_super_admin(owner, c.membership)

      assert length(Tenancy.list_super_admins(owner)) == 3
      subject = "Your role in #{owner.customer_account.name} is now Super Admin"
      assert_received {:email, %Swoosh.Email{subject: ^subject}}
      assert length(audit("super_admin.appointed")) == 2
    end

    test "any Super Admin but the last can be removed" do
      owner = account_scope_fixture() |> put_plan("entrepreneur") |> sudo()
      admin = member_scope_fixture(owner, "admin")
      {:ok, _} = Tenancy.appoint_super_admin(owner, admin.membership)
      appointed = Tenancy.get_membership!(owner, admin.membership.id)

      assert {:ok, _} = Tenancy.remove_super_admin(owner, appointed)
      assert Tenancy.get_membership!(owner, admin.membership.id).role == "admin"
      assert {:error, :last_super_admin} = Tenancy.remove_super_admin(owner, owner.membership)
      assert [_] = audit("super_admin.removed")
    end

    test "on single Super Admin plans, ownership is transferred" do
      owner = account_scope_fixture() |> put_plan("business") |> sudo()
      user = member_scope_fixture(owner, "user")

      assert {:error, {:limit_reached, _}} =
               Tenancy.appoint_super_admin(owner, member_scope_fixture(owner, "admin").membership)

      assert {:ok, _} = Tenancy.transfer_ownership(owner, user.membership)

      assert Tenancy.get_current_membership(user.user).role == "super_admin"
      assert Tenancy.get_current_membership(owner.user).role == "admin"
      assert [event] = audit("super_admin.transferred")
      assert event.changes[user.user.id] == ["user", "super_admin"]
      assert event.changes[owner.user.id] == ["super_admin", "admin"]
      subject = "Your role in #{owner.customer_account.name} is now Super Admin"
      assert_received {:email, %Swoosh.Email{subject: ^subject}}
    end
  end
end

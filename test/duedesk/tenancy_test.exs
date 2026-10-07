defmodule DueDesk.TenancyTest do
  use DueDesk.DataCase, async: true

  import DueDesk.AccountsFixtures
  import DueDesk.TenancyFixtures

  alias DueDesk.{Audit, Tenancy}
  alias DueDesk.Accounts.Scope
  alias DueDesk.Tenancy.Membership

  describe "create_customer_account/2" do
    test "creates the account with Indian defaults and makes the user Super Admin" do
      user = user_fixture()

      assert {:ok, %{customer_account: account, membership: membership}} =
               Tenancy.create_customer_account(Scope.for_user(user), %{
                 name: "Sharma Group",
                 notification_mobile: "98765 43210"
               })

      assert account.name == "Sharma Group"
      assert account.status == "active"
      assert account.plan_code == "free"
      assert account.timezone == "Asia/Kolkata"
      assert account.currency == "INR"
      assert account.due_soon_days == 30
      assert account.notification_mobile == "+919876543210"

      assert membership.user_id == user.id
      assert membership.role == "super_admin"
      assert membership.notify_email
      refute membership.notify_whatsapp
      refute membership.whatsapp_consent_at
    end

    test "records WhatsApp consent on the membership" do
      user = user_fixture()

      {:ok, %{membership: membership}} =
        Tenancy.create_customer_account(Scope.for_user(user), %{
          name: "Consenting Co",
          notification_mobile: "9876543210",
          whatsapp_consent: "true"
        })

      assert membership.notify_whatsapp
      assert membership.whatsapp_consent_at
    end

    test "writes an account.created audit event in the same transaction" do
      scope = account_scope_fixture()

      assert [event] = Audit.list_events(scope)
      assert event.action == "account.created"
      assert event.actor_type == "user"
      assert event.actor_id == scope.user.id
      assert event.subject_type == "customer_account"
      assert event.subject_id == scope.customer_account.id
    end

    test "validates name and mobile" do
      user = user_fixture()

      assert {:error, changeset} =
               Tenancy.create_customer_account(Scope.for_user(user), %{
                 name: "",
                 notification_mobile: "123"
               })

      assert %{name: [_], notification_mobile: [_]} = errors_on(changeset)
      refute Tenancy.get_current_membership(user)
    end
  end

  describe "get_current_membership/1" do
    test "returns the active membership with the account" do
      scope = account_scope_fixture()
      membership = Tenancy.get_current_membership(scope.user)
      assert membership.customer_account.id == scope.customer_account.id
    end

    test "skips closed accounts and deactivated memberships" do
      scope = account_scope_fixture()
      Repo.update!(Ecto.Changeset.change(scope.customer_account, status: "closed"))
      refute Tenancy.get_current_membership(scope.user)

      other = account_scope_fixture()
      Repo.update!(Ecto.Changeset.change(other.membership, status: "deactivated"))
      refute Tenancy.get_current_membership(other.user)
    end
  end

  describe "account isolation" do
    setup do
      %{a: account_scope_fixture(), b: account_scope_fixture()}
    end

    test "list_memberships/1 only returns the scope's account", %{a: a, b: b} do
      member_scope_fixture(a, "user")

      ids = a |> Tenancy.list_memberships() |> Enum.map(& &1.customer_account_id) |> Enum.uniq()
      assert ids == [a.customer_account.id]
      assert length(Tenancy.list_memberships(a)) == 2
      assert length(Tenancy.list_memberships(b)) == 1
    end

    test "get_membership!/2 cannot reach another account's membership", %{a: a, b: b} do
      assert %Membership{} = Tenancy.get_membership!(a, a.membership.id)

      assert_raise Ecto.NoResultsError, fn ->
        Tenancy.get_membership!(a, b.membership.id)
      end
    end

    test "guessing a random id gives nothing", %{a: a} do
      assert_raise Ecto.NoResultsError, fn ->
        Tenancy.get_membership!(a, Ecto.UUID.generate())
      end
    end

    test "audit events are scoped to the account", %{a: a, b: b} do
      ids = a |> Audit.list_events() |> Enum.map(& &1.customer_account_id) |> Enum.uniq()
      assert ids == [a.customer_account.id]
      refute Enum.any?(Audit.list_events(a), &(&1.subject_id == b.customer_account.id))
    end

    test "scoped reads refuse a scope without an account" do
      scope = Scope.for_user(user_fixture())
      assert_raise FunctionClauseError, fn -> Tenancy.list_memberships(scope) end
    end
  end

  describe "today/1" do
    test "uses the account timezone" do
      scope = account_scope_fixture()
      expected = "Asia/Kolkata" |> DateTime.now!() |> DateTime.to_date()
      assert Tenancy.today(scope) == expected
    end
  end
end

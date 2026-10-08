defmodule DueDesk.BillingTest do
  use DueDesk.DataCase, async: true

  import DueDesk.TenancyFixtures
  import DueDesk.OrganisationsFixtures

  alias DueDesk.{Billing, Organisations}

  test "usage counts active Organisations and Admins and Users, not Super Admins" do
    scope = account_scope_fixture() |> put_plan("business")
    member_scope_fixture(scope, "admin")
    member_scope_fixture(scope, "user")
    organisation_fixture(scope)
    archived = organisation_fixture(scope)
    {:ok, _} = Organisations.archive_organisation(scope, archived)

    usage = Billing.usage(scope)
    assert usage.organisations == 1
    assert usage.members == 2
    assert usage.super_admins == 1
    assert usage.due_items == 0
    assert usage.storage_bytes == 0
  end

  test "check/2 enforces the plan's Organisation and member limits" do
    scope = account_scope_fixture()
    assert Billing.check(scope, :organisation) == :ok
    organisation_fixture(scope)

    assert {:error, {:limit_reached, %{plan: %{name: "Free"}, limit: 1}}} =
             Billing.check(scope, :organisation)

    member_scope_fixture(scope, "admin")
    assert Billing.check(scope, :member) == :ok
    member_scope_fixture(scope, "user")
    assert {:error, {:limit_reached, %{limit: 2}}} = Billing.check(scope, :member)
  end

  test "the Entrepreneur plan has no Organisation limit" do
    scope = account_scope_fixture() |> put_plan("entrepreneur")
    for _ <- 1..4, do: organisation_fixture(scope)
    assert Billing.check(scope, :organisation) == :ok
  end

  test "limit messages point Super Admins to the plans and others to their Super Admin" do
    scope = account_scope_fixture()
    organisation_fixture(scope)
    {:error, {:limit_reached, info}} = Billing.check(scope, :organisation)

    assert Billing.limit_message(scope, info) ==
             "You have reached the Free Plan limit of 1 Organisation. Upgrade your plan to add more."

    admin = member_scope_fixture(scope, "admin")

    assert Billing.limit_message(admin, info) ==
             "You have reached the Free Plan limit of 1 Organisation. Ask your Super Admin to upgrade the plan."
  end
end

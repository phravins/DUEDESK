defmodule DueDesk.AuditTest do
  use DueDesk.DataCase, async: true

  import DueDesk.TenancyFixtures

  alias DueDesk.Audit
  alias DueDesk.Audit.AuditEvent

  test "log/4 records actor, account and subject" do
    scope = account_scope_fixture()

    {:ok, event} =
      Audit.log(scope, "membership.updated", scope.membership,
        changes: %{"role" => ["user", "admin"]},
        metadata: %{"reason" => "promotion"}
      )

    assert event.customer_account_id == scope.customer_account.id
    assert event.actor_type == "user"
    assert event.subject_type == "membership"
    assert event.changes == %{"role" => ["user", "admin"]}

    assert [%{id: id}] = Audit.list_events(scope, subject: scope.membership)
    assert id == event.id
  end

  test "system and operator actors" do
    scope = account_scope_fixture()

    {:ok, event} =
      Audit.log(:system, "reminder.sent", nil, customer_account_id: scope.customer_account.id)

    assert {event.actor_type, event.actor_id} == {"system", nil}

    {:ok, event} = Audit.log({:operator, %{id: Ecto.UUID.generate()}}, "operator.viewed", nil)
    assert event.actor_type == "operator"
  end

  test "audit rows cannot be updated or deleted" do
    scope = account_scope_fixture()
    [event] = Audit.list_events(scope)

    assert_raise Postgrex.Error, ~r/append-only/, fn ->
      event |> Ecto.Changeset.change(action: "tampered") |> Repo.update!()
    end

    assert_raise Postgrex.Error, ~r/append-only/, fn -> Repo.delete!(event) end
    assert Repo.get!(AuditEvent, event.id).action == "account.created"
  end
end

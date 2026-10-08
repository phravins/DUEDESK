defmodule DueDesk.OrganisationsTest do
  use DueDesk.DataCase, async: true

  import DueDesk.TenancyFixtures
  import DueDesk.OrganisationsFixtures

  alias DueDesk.{Audit, Organisations, Repo}
  alias DueDesk.Organisations.{Declaration, Organisation}

  @meta %{ip: "203.0.113.7", user_agent: "Mozilla/5.0 Test"}

  setup do
    %{scope: account_scope_fixture() |> put_plan("business")}
  end

  describe "create_organisation/3" do
    test "stores the normalised identifier and its display form", %{scope: scope} do
      {:ok, organisation} =
        Organisations.create_organisation(
          scope,
          %{
            name: "  Sharma Traders ",
            type: "proprietorship",
            identifier: "udyam mh 01 0001234",
            gstin: "27aapfu0939f1zv",
            declaration_accepted: true
          },
          @meta
        )

      assert organisation.name == "Sharma Traders"
      assert organisation.identifier_type == "udyam"
      assert organisation.identifier == "UDYAM-MH-01-0001234"
      assert organisation.normalized_identifier == "UDYAMMH010001234"
      assert organisation.gstin == "27AAPFU0939F1ZV"
      assert organisation.status == "active"
      assert organisation.created_by_user_id == scope.user.id
    end

    test "the identifier type follows the Organisation type, never the input", %{scope: scope} do
      {:ok, organisation} =
        Organisations.create_organisation(scope, %{
          name: "Verma LLP",
          type: "llp",
          identifier: "AAB-1234",
          identifier_type: "cin",
          declaration_accepted: true
        })

      assert organisation.identifier_type == "llpin"
    end

    test "rejects an identifier in the wrong format for the type", %{scope: scope} do
      {:error, changeset} =
        Organisations.create_organisation(scope, %{
          name: "Iyer Foods",
          type: "private_limited",
          identifier: "AAB-1234",
          declaration_accepted: true
        })

      assert "enter a valid CIN, e.g. U72900KA2015PTC123456" in errors_on(changeset).identifier
    end

    test "rejects an invalid GSTIN", %{scope: scope} do
      {:error, changeset} =
        Organisations.create_organisation(
          scope,
          valid_organisation_attributes(gstin: "27AAPFU0939F1Z")
        )

      assert errors_on(changeset).gstin != []
    end

    test "records the declaration with version, text hash, IP and user agent", %{scope: scope} do
      organisation = organisation_fixture(scope)
      declaration = Repo.get_by!(Declaration, organisation_id: organisation.id)

      assert declaration.customer_account_id == scope.customer_account.id
      assert declaration.user_id == scope.user.id
      assert declaration.version == Declaration.version()
      assert declaration.text_hash == Declaration.text_hash()
      assert declaration.ip == "127.0.0.1"
      assert declaration.user_agent == "ExUnit"
      assert declaration.accepted_at
    end

    test "requires the declaration", %{scope: scope} do
      {:error, changeset} =
        Organisations.create_organisation(
          scope,
          valid_organisation_attributes(declaration_accepted: false)
        )

      assert "confirm the declaration to continue" in errors_on(changeset).declaration_accepted
      assert Repo.aggregate(Organisation, :count) == 0
      assert Repo.aggregate(Declaration, :count) == 0
    end

    test "a registered identifier gives only the generic message, in any account", %{
      scope: scope
    } do
      other = account_scope_fixture()
      organisation_fixture(other, identifier: "UDYAM-KA-02-0000077", name: "Secret Other Co")

      for identifier <- ["udyam-ka-02-0000077", "UDYAM KA 02 0000077"] do
        {:error, changeset} =
          Organisations.create_organisation(
            scope,
            valid_organisation_attributes(identifier: identifier)
          )

        assert errors_on(changeset) == %{identifier: [Organisation.duplicate_message()]}
      end

      organisation_fixture(scope, identifier: "UDYAM-KA-02-0000078")

      {:error, changeset} =
        Organisations.create_organisation(
          scope,
          valid_organisation_attributes(identifier: "UDYAM-KA-02-0000078")
        )

      assert errors_on(changeset) == %{identifier: [Organisation.duplicate_message()]}
    end

    test "the same number under a different identifier type is not a duplicate", %{scope: scope} do
      organisation_fixture(scope, type: "llp", identifier: "AAB-1234")
      assert %Organisation{} = organisation_fixture(scope, type: "llp", identifier: "AAB-1235")
    end

    test "Users cannot add Organisations", %{scope: scope} do
      user_scope = member_scope_fixture(scope, "user")

      assert Organisations.create_organisation(user_scope, valid_organisation_attributes()) ==
               {:error, :unauthorized}
    end

    test "Administrators can add Organisations", %{scope: scope} do
      admin_scope = member_scope_fixture(scope, "admin")
      assert %Organisation{} = organisation_fixture(admin_scope)
    end
  end

  describe "plan limits" do
    test "the Free plan allows one active Organisation" do
      scope = account_scope_fixture()
      organisation_fixture(scope)

      assert {:error, {:limit_reached, %{limit: 1, resource: :organisation}}} =
               Organisations.create_organisation(scope, valid_organisation_attributes())
    end

    test "archiving frees a slot and restoring is blocked at the limit" do
      scope = account_scope_fixture()
      first = organisation_fixture(scope)

      {:ok, first} = Organisations.archive_organisation(scope, first)
      assert first.status == "archived"
      assert first.archived_by_user_id == scope.user.id

      second = organisation_fixture(scope)
      assert second.status == "active"

      assert {:error, {:limit_reached, _}} = Organisations.restore_organisation(scope, first)

      {:ok, _} = Organisations.archive_organisation(scope, second)
      {:ok, first} = Organisations.restore_organisation(scope, first)
      assert first.status == "active"
      assert first.archived_at == nil
    end
  end

  describe "update_organisation/4" do
    test "name and GSTIN change without a new declaration", %{scope: scope} do
      organisation = organisation_fixture(scope)

      {:ok, updated} =
        Organisations.update_organisation(scope, organisation, %{
          name: "Renamed",
          gstin: "27AAPFU0939F1ZV"
        })

      assert updated.name == "Renamed"
      assert Repo.aggregate(Declaration, :count) == 1
    end

    test "changing the identifier needs the declaration again", %{scope: scope} do
      organisation = organisation_fixture(scope)

      {:error, changeset} =
        Organisations.update_organisation(scope, organisation, %{identifier: unique_udyam()})

      assert "confirm the declaration to continue" in errors_on(changeset).declaration_accepted

      {:ok, _} =
        Organisations.update_organisation(
          scope,
          organisation,
          %{identifier: unique_udyam(), declaration_accepted: true},
          @meta
        )

      assert Repo.aggregate(Declaration, :count) == 2
      assert Organisations.latest_declaration(scope, organisation).ip == "203.0.113.7"
    end

    test "cannot change another account's Organisation", %{scope: scope} do
      other = account_scope_fixture()
      organisation = organisation_fixture(other)

      assert Organisations.update_organisation(scope, organisation, %{name: "Mine"}) ==
               {:error, :unauthorized}

      assert Organisations.archive_organisation(scope, organisation) == {:error, :unauthorized}
    end
  end

  describe "reading" do
    test "lists and counts by status, only for the scope's account", %{scope: scope} do
      a = organisation_fixture(scope, name: "Alpha")
      b = organisation_fixture(scope, name: "beta")
      organisation_fixture(account_scope_fixture())
      {:ok, _} = Organisations.archive_organisation(scope, b)

      assert [%{id: id}] = Organisations.list_organisations(scope)
      assert id == a.id
      assert [%{id: ^id}] = Organisations.list_organisations(scope, status: "active")
      assert [_] = Organisations.list_organisations(scope, status: "archived")
      assert Organisations.count_by_status(scope) == %{active: 1, archived: 1}
    end

    test "another account's Organisation cannot be fetched", %{scope: scope} do
      organisation = organisation_fixture(account_scope_fixture())

      assert_raise Ecto.NoResultsError, fn ->
        Organisations.get_organisation!(scope, organisation.id)
      end
    end
  end

  describe "audit" do
    test "each change writes one event without identifiers, IP or user agent", %{scope: scope} do
      organisation = organisation_fixture(scope)

      {:ok, organisation} =
        Organisations.update_organisation(
          scope,
          organisation,
          %{name: "Renamed", identifier: unique_udyam(), declaration_accepted: true},
          @meta
        )

      {:ok, organisation} = Organisations.archive_organisation(scope, organisation)
      {:ok, organisation} = Organisations.restore_organisation(scope, organisation)

      events = Audit.list_events(scope, subject: organisation)

      assert events |> Enum.map(& &1.action) |> Enum.sort() ==
               Enum.sort(~w(organisation.created organisation.updated
                            organisation.archived organisation.restored))

      updated = Enum.find(events, &(&1.action == "organisation.updated"))
      assert ["Org " <> _, "Renamed"] = updated.changes["name"]
      assert updated.changes["identifier"] == "changed"

      for event <- events do
        dump = inspect({event.changes, event.metadata})
        refute dump =~ organisation.normalized_identifier
        refute dump =~ organisation.identifier
        refute dump =~ "203.0.113.7"
        refute dump =~ "127.0.0.1"
        refute dump =~ "Mozilla"
        refute dump =~ "ExUnit"
      end
    end
  end
end

defmodule DueDesk.DueItemsTest do
  use DueDesk.DataCase, async: true

  import Ecto.Query
  import DueDesk.TenancyFixtures
  import DueDesk.OrganisationsFixtures
  import DueDesk.DueItemsFixtures

  alias DueDesk.{Billing, Categories, DueItems, Organisations, Repo}
  alias DueDesk.Audit.AuditEvent
  alias DueDesk.DueItems.{Assignment, DueItem, ReminderRule}

  setup do
    owner = account_scope_fixture() |> put_plan("business")
    admin = member_scope_fixture(owner, "admin")
    user_a = member_scope_fixture(owner, "user")
    user_b = member_scope_fixture(owner, "user")
    %{owner: owner, admin: admin, user_a: user_a, user_b: user_b}
  end

  defp ids(items), do: items |> Enum.map(& &1.id) |> Enum.sort()

  defp events(item) do
    Repo.all(
      from e in AuditEvent,
        where: e.subject_id == ^item.id,
        order_by: [asc: e.inserted_at]
    )
  end

  describe "create_due_item/2" do
    test "an Admin sets every field, responsibility and reminders", ctx do
      attrs =
        valid_due_item_attributes(ctx.admin, %{
          "related_party" => "Municipal Corporation",
          "recurrence" => "custom",
          "recurrence_unit" => "month",
          "recurrence_interval" => "2",
          "primary_user_id" => ctx.user_a.user.id,
          "additional_user_ids" => ["", ctx.user_b.user.id],
          "reminder_offsets" => ["", "-14", "0"]
        })

      assert {:ok, item} = DueItems.create_due_item(ctx.admin, attrs)
      item = reload(ctx.admin, item)

      assert item.related_party == "Municipal Corporation"
      assert item.recurrence == "custom"
      assert item.recurrence_interval == 2
      assert item.current_cycle.sequence == 1
      assert item.current_cycle.due_date == Date.from_iso8601!(attrs["due_date"])
      assert DueItem.primary_user(item).id == ctx.user_a.user.id
      assert Enum.map(DueItem.additional_users(item), & &1.id) == [ctx.user_b.user.id]
      assert Enum.map(item.reminder_rules, & &1.offset_days) == [-14, 0]

      assert [%AuditEvent{action: "due_item.created"}] = events(item)
    end

    test "an Admin may leave it unassigned", ctx do
      item = due_item_fixture(ctx.admin)
      assert DueItem.unassigned?(item)
      assert Enum.map(item.reminder_rules, & &1.offset_days) == ReminderRule.defaults()
    end

    test "a User's create ignores control fields and makes them Primary", ctx do
      attrs =
        valid_due_item_attributes(ctx.user_a, %{
          "related_party" => "Someone",
          "recurrence" => "annual",
          "primary_user_id" => ctx.user_b.user.id,
          "additional_user_ids" => [ctx.user_b.user.id],
          "reminder_offsets" => ["-1"]
        })

      assert {:ok, item} = DueItems.create_due_item(ctx.user_a, attrs)
      item = reload(ctx.owner, item)

      assert item.related_party == nil
      assert item.recurrence == "none"
      assert DueItem.primary_user(item).id == ctx.user_a.user.id
      assert DueItem.additional_users(item) == []
      assert Enum.map(item.reminder_rules, & &1.offset_days) == ReminderRule.defaults()
    end

    test "requires a title, Organisation, category and one of the dates", ctx do
      assert {:error, changeset} =
               DueItems.create_due_item(ctx.admin, %{"title" => "", "due_date" => ""})

      errors = errors_on(changeset)
      assert "enter a title" in errors.title
      assert "choose an Organisation" in errors.organisation_id
      assert "choose a category" in errors.category_id
      assert "enter a Due Date or an Expiry Date" in errors.due_date
    end

    test "an Expiry Date alone is enough", ctx do
      item =
        due_item_fixture(ctx.admin, %{
          "due_date" => nil,
          "expiry_date" => days_from_today(ctx.admin, 10)
        })

      assert item.current_cycle.due_date == nil
      assert DueItems.status(ctx.admin, item) == :due_soon
    end

    test "the start date may not be after the dates", ctx do
      attrs =
        valid_due_item_attributes(ctx.admin, %{"start_date" => days_from_today(ctx.admin, 500)})

      assert {:error, changeset} = DueItems.create_due_item(ctx.admin, attrs)
      assert errors_on(changeset).start_date != []
    end

    test "the Organisation and category must be active and in this account", ctx do
      other = account_scope_fixture()
      other_org = organisation_fixture(other)
      other_category = category_for(other)

      attrs =
        valid_due_item_attributes(ctx.admin, %{
          "organisation_id" => other_org.id,
          "category_id" => other_category.id
        })

      assert {:error, changeset} = DueItems.create_due_item(ctx.admin, attrs)
      assert "choose an active Organisation" in errors_on(changeset).organisation_id
      assert "choose an active category" in errors_on(changeset).category_id

      archived = organisation_fixture(ctx.owner)
      {:ok, _} = Organisations.archive_organisation(ctx.owner, archived)
      {:ok, category} = Categories.create_category(ctx.owner, %{name: "Old"})
      {:ok, _} = Categories.archive_category(ctx.owner, category)

      attrs =
        valid_due_item_attributes(ctx.admin, %{
          "organisation_id" => archived.id,
          "category_id" => category.id
        })

      assert {:error, changeset} = DueItems.create_due_item(ctx.admin, attrs)
      assert "choose an active Organisation" in errors_on(changeset).organisation_id
      assert "choose an active category" in errors_on(changeset).category_id
    end

    test "assignees must be active members of this account", ctx do
      outsider = account_scope_fixture()

      attrs =
        valid_due_item_attributes(ctx.admin, %{"primary_user_id" => outsider.user.id})

      assert {:error, changeset} = DueItems.create_due_item(ctx.admin, attrs)
      assert "choose an active member" in errors_on(changeset).primary_user_id

      attrs =
        valid_due_item_attributes(ctx.admin, %{
          "primary_user_id" => ctx.user_a.user.id,
          "additional_user_ids" => [outsider.user.id]
        })

      assert {:error, changeset} = DueItems.create_due_item(ctx.admin, attrs)
      assert "choose active members" in errors_on(changeset).additional_user_ids
    end

    test "Additional Assignees need a Primary Responsible", ctx do
      attrs =
        valid_due_item_attributes(ctx.admin, %{"additional_user_ids" => [ctx.user_a.user.id]})

      assert {:error, changeset} = DueItems.create_due_item(ctx.admin, attrs)
      assert "choose a Primary Responsible first" in errors_on(changeset).primary_user_id
    end

    test "custom reminders are limited to a year", ctx do
      attrs = valid_due_item_attributes(ctx.admin, %{"reminder_offsets" => ["-400"]})
      assert {:error, changeset} = DueItems.create_due_item(ctx.admin, attrs)
      assert errors_on(changeset).reminder_offsets != []
    end
  end

  describe "plan limits" do
    test "the Free plan blocks the 11th DueItem; archiving frees a slot; restore is blocked" do
      scope = account_scope_fixture()
      items = for _ <- 1..10, do: due_item_fixture(scope)

      assert Billing.usage(scope).due_items == 10

      assert {:error, {:limit_reached, %{limit: 10}}} =
               DueItems.create_due_item(scope, valid_due_item_attributes(scope))

      {:ok, archived} = DueItems.archive_due_item(scope, hd(items))
      assert Billing.usage(scope).due_items == 9
      due_item_fixture(scope)

      assert {:error, {:limit_reached, _}} = DueItems.restore_due_item(scope, archived)
    end
  end

  describe "access" do
    test "User A cannot list or open User B's DueItem", ctx do
      mine = due_item_fixture(ctx.user_a)
      theirs = due_item_fixture(ctx.user_b)

      assert ids(DueItems.list_due_items(ctx.user_a)) == [mine.id]
      assert {:ok, _} = DueItems.get_due_item(ctx.user_a, mine.id)
      assert {:error, :not_found} = DueItems.get_due_item(ctx.user_a, theirs.id)
      assert {:error, :unauthorized} = DueItems.add_note(ctx.user_a, theirs, %{"body" => "Hi"})
      assert DueItems.list_notes(ctx.user_a, theirs) == []
      assert DueItems.history(ctx.user_a, theirs) == []
    end

    test "an Additional Assignee can see the DueItem", ctx do
      item =
        due_item_fixture(ctx.admin, %{
          "primary_user_id" => ctx.user_a.user.id,
          "additional_user_ids" => [ctx.user_b.user.id]
        })

      assert {:ok, _} = DueItems.get_due_item(ctx.user_b, item.id)
    end

    test "the creator loses access after reassignment", ctx do
      item = due_item_fixture(ctx.user_a)

      {:ok, _} =
        DueItems.assign_due_item(ctx.admin, item, %{"primary_user_id" => ctx.user_b.user.id})

      assert {:error, :not_found} = DueItems.get_due_item(ctx.user_a, item.id)
      assert DueItems.list_due_items(ctx.user_a) == []
      assert {:ok, _} = DueItems.get_due_item(ctx.user_b, item.id)
    end

    test "archived DueItems are hidden from Users", ctx do
      item = due_item_fixture(ctx.user_a)
      {:ok, _} = DueItems.archive_due_item(ctx.admin, item)

      assert {:error, :not_found} = DueItems.get_due_item(ctx.user_a, item.id)
      assert DueItems.list_due_items(ctx.user_a, %{"view" => "archived"}) == []
    end

    test "Admins and Super Admins see everything", ctx do
      a = due_item_fixture(ctx.user_a)
      b = due_item_fixture(ctx.user_b)
      unassigned = due_item_fixture(ctx.admin)

      for scope <- [ctx.admin, ctx.owner] do
        assert ids(DueItems.list_due_items(scope)) == Enum.sort([a.id, b.id, unassigned.id])
        assert {:ok, _} = DueItems.get_due_item(scope, b.id)
      end
    end

    test "no access across accounts", ctx do
      item = due_item_fixture(ctx.admin)
      other = account_scope_fixture()

      assert DueItems.list_due_items(other) == []
      assert {:error, :not_found} = DueItems.get_due_item(other, item.id)
      assert {:error, :unauthorized} = DueItems.archive_due_item(other, item)
      assert {:error, :unauthorized} = DueItems.update_due_item(other, item, %{"title" => "X"})
      assert {:error, :unauthorized} = DueItems.add_note(other, item, %{"body" => "Hi"})
    end

    test "a guessed or malformed id is not found", ctx do
      assert {:error, :not_found} = DueItems.get_due_item(ctx.admin, Ecto.UUID.generate())
      assert {:error, :not_found} = DueItems.get_due_item(ctx.admin, "not-a-uuid")
    end

    test "Users cannot use the control actions", ctx do
      item = due_item_fixture(ctx.user_a)

      assert {:error, :unauthorized} =
               DueItems.update_due_item(ctx.user_a, item, %{"title" => "New"})

      assert {:error, :unauthorized} =
               DueItems.assign_due_item(ctx.user_a, item, %{"primary_user_id" => nil})

      assert {:error, :unauthorized} =
               DueItems.override_status(ctx.user_a, item, "up_to_date", "Done")

      assert {:error, :unauthorized} = DueItems.clear_status_override(ctx.user_a, item)
      assert {:error, :unauthorized} = DueItems.archive_due_item(ctx.user_a, item)
    end
  end

  describe "list_due_items/3 filters" do
    test "search, status, Organisation, category, people and tabs", ctx do
      overdue =
        due_item_fixture(ctx.admin, %{
          "title" => "Fire NOC",
          "due_date" => days_from_today(ctx.admin, -3),
          "primary_user_id" => ctx.user_a.user.id
        })

      soon =
        due_item_fixture(ctx.admin, %{
          "title" => "GST return 50%_off",
          "reference_number" => "GSTR-3B",
          "due_date" => days_from_today(ctx.admin, 5),
          "primary_user_id" => ctx.user_b.user.id,
          "additional_user_ids" => [ctx.user_a.user.id]
        })

      later = due_item_fixture(ctx.admin, %{"title" => "Insurance"})
      archived = due_item_fixture(ctx.admin, %{"title" => "Old"})
      {:ok, _} = DueItems.archive_due_item(ctx.admin, archived)

      list = &ids(DueItems.list_due_items(ctx.admin, &1))

      assert list.(%{}) == ids([overdue, soon, later])
      assert list.(%{"q" => "noc"}) == [overdue.id]
      assert list.(%{"q" => "gstr"}) == [soon.id]
      assert list.(%{"q" => "%"}) == [soon.id]
      assert list.(%{"q" => "_off"}) == [soon.id]
      assert list.(%{"status" => "overdue"}) == [overdue.id]
      assert list.(%{"status" => "due_soon"}) == [soon.id]
      assert list.(%{"status" => "up_to_date"}) == [later.id]
      assert list.(%{"status" => "bogus"}) == ids([overdue, soon, later])
      assert list.(%{"assignment" => "unassigned"}) == [later.id]
      assert list.(%{"primary_user_id" => ctx.user_a.user.id}) == [overdue.id]
      assert list.(%{"assignee_user_id" => ctx.user_a.user.id}) == ids([overdue, soon])
      assert list.(%{"view" => "archived"}) == [archived.id]
      assert list.(%{"organisation_id" => overdue.organisation_id}) |> length() == 3
      assert list.(%{"organisation_id" => "junk"}) |> length() == 3
      assert list.(%{"due_to" => days_from_today(ctx.admin, 0)}) == [overdue.id]
      assert list.(%{"due_from" => days_from_today(ctx.admin, 1)}) == ids([soon, later])

      # Soonest first.
      assert Enum.map(DueItems.list_due_items(ctx.admin), & &1.id) ==
               [overdue.id, soon.id, later.id]

      assert ids(DueItems.list_due_items(ctx.admin, %{}, limit: 1, offset: 1)) == [soon.id]
    end
  end

  describe "counts" do
    test "count_by_status/1 and the dashboard breakdowns", ctx do
      due_item_fixture(ctx.admin, %{
        "due_date" => days_from_today(ctx.admin, -1),
        "primary_user_id" => ctx.user_a.user.id
      })

      due_item_fixture(ctx.admin, %{"due_date" => days_from_today(ctx.admin, 3)})
      due_item_fixture(ctx.admin, %{"due_date" => days_from_today(ctx.admin, 200)})

      assert DueItems.count_by_status(ctx.admin) ==
               %{overdue: 1, due_soon: 1, up_to_date: 1, unassigned: 2}

      assert DueItems.count_by_status(ctx.user_a) ==
               %{overdue: 1, due_soon: 0, up_to_date: 0, unassigned: 0}

      assert [%{total: 3, overdue: 1, due_soon: 1}] = DueItems.counts_by_organisation(ctx.admin)
      assert [%{id: id, total: 1, overdue: 1}] = DueItems.counts_by_user(ctx.admin)
      assert id == ctx.user_a.user.id
      assert DueItems.counts_by_organisation(ctx.user_a) == []

      timeline = DueItems.due_timeline(ctx.admin, 30)
      assert length(timeline) == 30
      assert Enum.at(timeline, 3).count == 1
      assert Enum.sum(Enum.map(timeline, & &1.count)) == 1
    end
  end

  describe "update_due_item/3" do
    test "updates fields, dates and reminders and audits the changes", ctx do
      item = due_item_fixture(ctx.admin, %{"title" => "Fire NOC"})
      new_due = days_from_today(ctx.admin, 200)

      assert {:ok, _} =
               DueItems.update_due_item(ctx.admin, item, %{
                 "title" => "Fire NOC renewal",
                 "due_date" => new_due,
                 "recurrence" => "annual",
                 "reminder_offsets" => ["", "-30", "0"]
               })

      item = reload(ctx.admin, item)
      assert item.title == "Fire NOC renewal"
      assert item.recurrence == "annual"
      assert item.current_cycle.due_date == Date.from_iso8601!(new_due)

      active = for r <- item.reminder_rules, r.active, do: r.offset_days
      assert active == [-30, 0]
      assert length(item.reminder_rules) == 5

      [_created, updated] = events(item)
      assert updated.action == "due_item.updated"
      assert updated.changes["title"] == ["Fire NOC", "Fire NOC renewal"]
      assert [_, ^new_due] = updated.changes["due_date"]
      assert updated.changes["reminders"] == [ReminderRule.defaults(), [-30, 0]]

      # Turning a reminder back on reuses its rule.
      {:ok, _} = DueItems.update_due_item(ctx.admin, item, %{"reminder_offsets" => ["-90"]})
      item = reload(ctx.admin, item)
      assert for(r <- item.reminder_rules, r.active, do: r.offset_days) == [-90]
      assert length(item.reminder_rules) == 5
    end

    test "nothing changed writes no audit event", ctx do
      item = due_item_fixture(ctx.admin)
      {:ok, _} = DueItems.update_due_item(ctx.admin, item, %{"title" => item.title})
      assert length(events(item)) == 1
    end

    test "invalid input returns the changeset", ctx do
      item = due_item_fixture(ctx.admin)

      assert {:error, changeset} =
               DueItems.update_due_item(ctx.admin, item, %{"due_date" => "", "title" => ""})

      assert errors_on(changeset).title != []
      assert errors_on(changeset).due_date != []
    end
  end

  describe "assign_due_item/3" do
    test "reassigns, ends old assignments and audits who changed", ctx do
      item =
        due_item_fixture(ctx.admin, %{
          "primary_user_id" => ctx.user_a.user.id,
          "additional_user_ids" => [ctx.user_b.user.id]
        })

      assert {:ok, _} =
               DueItems.assign_due_item(ctx.admin, item, %{
                 "primary_user_id" => ctx.user_b.user.id,
                 "additional_user_ids" => [""]
               })

      item = reload(ctx.admin, item)
      assert DueItem.primary_user(item).id == ctx.user_b.user.id
      assert DueItem.additional_users(item) == []

      rows = Repo.all(from a in Assignment, where: a.due_item_id == ^item.id)
      assert length(rows) == 3
      assert Enum.count(rows, &is_nil(&1.ended_at)) == 1

      [_created, assigned] = events(item)
      assert assigned.action == "due_item.assigned"
      assert assigned.changes["primary"] == [ctx.user_a.user.id, ctx.user_b.user.id]
      assert assigned.changes["additional"] == [[ctx.user_b.user.id], []]
    end

    test "unassigning leaves nobody responsible", ctx do
      item = due_item_fixture(ctx.admin, %{"primary_user_id" => ctx.user_a.user.id})
      assert {:ok, _} = DueItems.assign_due_item(ctx.admin, item, %{"primary_user_id" => ""})
      assert DueItem.unassigned?(reload(ctx.admin, item))
    end

    test "no change writes nothing", ctx do
      item = due_item_fixture(ctx.admin, %{"primary_user_id" => ctx.user_a.user.id})

      assert {:ok, _} =
               DueItems.assign_due_item(ctx.admin, item, %{
                 "primary_user_id" => ctx.user_a.user.id
               })

      assert length(events(item)) == 1
    end

    test "assignees must be active members", ctx do
      item = due_item_fixture(ctx.admin)
      outsider = account_scope_fixture()

      assert {:error, changeset} =
               DueItems.assign_due_item(ctx.admin, item, %{"primary_user_id" => outsider.user.id})

      assert "choose an active member" in errors_on(changeset).primary_user_id
    end
  end

  describe "status overrides" do
    test "override and clear, with a required reason", ctx do
      item = due_item_fixture(ctx.admin, %{"due_date" => days_from_today(ctx.admin, -5)})
      assert DueItems.status(ctx.admin, item) == :overdue

      assert {:error, changeset} = DueItems.override_status(ctx.admin, item, "up_to_date", " ")
      assert "enter a reason" in errors_on(changeset).status_override_reason

      assert {:error, _} = DueItems.override_status(ctx.admin, item, "archived", "No")

      assert {:ok, _} =
               DueItems.override_status(ctx.admin, item, "up_to_date", "Paid at the counter")

      item = reload(ctx.admin, item)
      assert DueItems.status(ctx.admin, item) == :up_to_date

      assert {:ok, _} = DueItems.clear_status_override(ctx.admin, item)
      assert DueItems.status(ctx.admin, reload(ctx.admin, item)) == :overdue

      [_, overridden, cleared] = events(item)
      assert overridden.changes["status"] == ["overdue", "up_to_date"]
      assert overridden.metadata["reason"] == "Paid at the counter"
      assert cleared.action == "due_item.status_override_cleared"
    end
  end

  describe "archive and restore" do
    test "are audited and only change the right state", ctx do
      item = due_item_fixture(ctx.admin)
      assert {:ok, archived} = DueItems.archive_due_item(ctx.admin, item)
      assert archived.status == "archived"
      assert {:error, :not_active} = DueItems.archive_due_item(ctx.admin, archived)
      assert {:ok, restored} = DueItems.restore_due_item(ctx.admin, archived)
      assert restored.status == "active"
      assert {:error, :not_archived} = DueItems.restore_due_item(ctx.admin, restored)

      assert Enum.map(events(item), & &1.action) ==
               ["due_item.created", "due_item.archived", "due_item.restored"]
    end
  end

  describe "notes" do
    test "assignees add notes; the audit row never holds the text", ctx do
      item = due_item_fixture(ctx.user_a)

      assert {:error, changeset} = DueItems.add_note(ctx.user_a, item, %{"body" => "  "})
      assert "write a note" in errors_on(changeset).body

      assert {:ok, note} =
               DueItems.add_note(ctx.user_a, item, %{"body" => "Inspector visits Tuesday"})

      assert note.author_user.id == ctx.user_a.user.id
      assert [%{body: "Inspector visits Tuesday"}] = DueItems.list_notes(ctx.user_a, item)
      assert [_] = DueItems.list_notes(ctx.admin, item)

      for event <- events(item) do
        refute inspect(event.changes) =~ "Inspector"
        refute inspect(event.metadata) =~ "Inspector"
      end
    end
  end

  describe "history/2" do
    test "describes each change as a sentence", ctx do
      item = due_item_fixture(ctx.admin, %{"title" => "Fire NOC"})
      old_due = item.current_cycle.due_date
      new_due = Date.add(old_due, 5)

      {:ok, _} =
        DueItems.update_due_item(ctx.admin, item, %{"due_date" => Date.to_iso8601(new_due)})

      {:ok, _} =
        DueItems.assign_due_item(ctx.admin, item, %{"primary_user_id" => ctx.user_a.user.id})

      {:ok, _} = DueItems.override_status(ctx.admin, item, "overdue", "Missed the inspection")
      {:ok, _} = DueItems.add_note(ctx.admin, item, %{"body" => "Secret text"})
      {:ok, _} = DueItems.archive_due_item(ctx.admin, item)

      admin_name = ctx.admin.user.name
      user_name = ctx.user_a.user.name
      format = &Calendar.strftime(&1, "%d %b %Y")

      sentences = ctx.admin |> DueItems.history(item) |> Enum.map(& &1.sentence)

      assert sentences == [
               "#{admin_name} archived this DueItem",
               "#{admin_name} added a note",
               "#{admin_name} changed the status from Up to Date to Overdue",
               "#{admin_name} assigned #{user_name} as Primary Responsible",
               "#{admin_name} changed Due Date from #{format.(old_due)} to #{format.(new_due)}",
               "#{admin_name} created this DueItem"
             ]

      [_, _, override | _] = DueItems.history(ctx.admin, item)
      assert override.details == ["Reason: Missed the inspection"]
    end

    test "people outside the account are never named", ctx do
      item = due_item_fixture(ctx.admin, %{"primary_user_id" => ctx.user_a.user.id})

      # A former member's membership is gone.
      Repo.delete_all(
        from m in DueDesk.Tenancy.Membership, where: m.user_id == ^ctx.user_a.user.id
      )

      {:ok, _} =
        DueItems.assign_due_item(ctx.admin, reload(ctx.admin, item), %{"primary_user_id" => ""})

      [removed | _] = DueItems.history(ctx.admin, item)
      assert removed.sentence =~ "removed A former member as Primary Responsible"
    end
  end
end

defmodule DueDesk.Repo.Migrations.AddLifecycleToDueItemCycles do
  use Ecto.Migration

  def change do
    alter table(:due_item_cycles) do
      # The day the renewal or completion was done, as entered on the form.
      add :completed_on, :date
      add :completion_type, :string
      # "computed" when a renewal worked the dates out; "entered" when a
      # person typed them. Renewals count from the latest entered cycle so
      # month-end dates do not drift.
      add :dates_source, :string, null: false, default: "entered"
    end

    create constraint(:due_item_cycles, :completion_type_valid,
             check: "completion_type IS NULL OR completion_type IN ('renewed', 'completed')"
           )

    create constraint(:due_item_cycles, :dates_source_valid,
             check: "dates_source IN ('entered', 'computed')"
           )

    create index(:due_item_cycles, [:customer_account_id],
             name: :due_item_cycles_pending_review_index,
             where: "completion_type = 'renewed' AND reviewed_at IS NULL"
           )

    drop constraint(:due_items, :disposition_state_valid)

    create constraint(:due_items, :disposition_state_valid,
             check:
               "disposition_state IS NULL OR disposition_state IN ('awaiting_admin_disposition', 'awaiting_new_dates')"
           )
  end
end

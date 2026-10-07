defmodule DueDesk.Repo.Migrations.CreateAuditEvents do
  use Ecto.Migration

  def up do
    create table(:audit_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # No foreign keys: the audit trail must outlive the rows it describes.
      add :customer_account_id, :binary_id
      add :actor_type, :string, null: false
      add :actor_id, :binary_id
      add :action, :string, null: false
      add :subject_type, :string
      add :subject_id, :binary_id
      add :changes, :map, null: false, default: %{}
      add :metadata, :map, null: false, default: %{}

      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create index(:audit_events, [:customer_account_id, :inserted_at])
    create index(:audit_events, [:subject_type, :subject_id])

    # The audit log is append-only: refuse UPDATE and DELETE at the database level.
    execute """
    CREATE FUNCTION audit_events_append_only() RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'audit_events is append-only';
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER audit_events_no_update_delete
    BEFORE UPDATE OR DELETE ON audit_events
    FOR EACH ROW EXECUTE FUNCTION audit_events_append_only();
    """
  end

  def down do
    execute "DROP TRIGGER audit_events_no_update_delete ON audit_events"
    execute "DROP FUNCTION audit_events_append_only()"
    drop table(:audit_events)
  end
end

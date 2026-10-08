defmodule DueDesk.Repo.Migrations.AuditEventsClockTimestamp do
  use Ecto.Migration

  # now() is the start of the transaction, so events written in one
  # transaction shared a timestamp and a DueItem's history had no reliable
  # order. clock_timestamp() is the moment each row is written.
  def change do
    alter table(:audit_events) do
      modify :inserted_at, :utc_datetime_usec,
        default: fragment("clock_timestamp()"),
        from: {:utc_datetime_usec, default: fragment("now()")}
    end
  end
end

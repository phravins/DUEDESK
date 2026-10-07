defmodule DueDesk.Audit.AuditEvent do
  @moduledoc """
  An append-only record of something that happened. Rows are never
  updated or deleted (enforced by a database trigger).
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "audit_events" do
    field :customer_account_id, :binary_id
    field :actor_type, :string
    field :actor_id, :binary_id
    field :action, :string
    field :subject_type, :string
    field :subject_id, :binary_id
    field :changes, :map, default: %{}
    field :metadata, :map, default: %{}

    field :inserted_at, :utc_datetime_usec, read_after_writes: true
  end
end

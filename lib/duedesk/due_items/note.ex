defmodule DueDesk.DueItems.Note do
  @moduledoc """
  A note on a DueItem. Notes are append-only and are never copied into
  the audit log.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "due_item_notes" do
    field :body, :string

    belongs_to :customer_account, DueDesk.Tenancy.CustomerAccount
    belongs_to :due_item, DueDesk.DueItems.DueItem
    belongs_to :cycle, DueDesk.DueItems.Cycle
    belongs_to :author_user, DueDesk.Accounts.User

    field :inserted_at, :utc_datetime_usec, read_after_writes: true
  end

  @doc false
  def changeset(note, attrs) do
    note
    |> cast(attrs, [:body])
    |> update_change(:body, &String.trim/1)
    |> validate_required([:body], message: "write a note")
    |> validate_length(:body, max: 4000)
  end
end

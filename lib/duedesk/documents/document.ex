defmodule DueDesk.Documents.Document do
  @moduledoc """
  A stored file on one cycle of a DueItem (Product Definition §10).

  `role` says why it is there:

    * `current` — the document for the period the cycle covers, such as
      the licence itself;
    * `supporting` — anything else that belongs with it;
    * `completion` — proof that the cycle was completed or renewed.

  Documents are never overwritten: a renewal starts a new cycle with its
  own documents. Size and checksum are measured by the server.
  """
  use Ecto.Schema

  @roles ~w(current supporting completion)

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id
  schema "documents" do
    field :role, :string
    field :filename, :string
    field :storage_key, :string
    field :content_type, :string
    field :byte_size, :integer
    field :checksum_sha256, :string

    belongs_to :customer_account, DueDesk.Tenancy.CustomerAccount
    belongs_to :due_item, DueDesk.DueItems.DueItem
    belongs_to :cycle, DueDesk.DueItems.Cycle
    belongs_to :uploaded_by_user, DueDesk.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def roles, do: @roles
end

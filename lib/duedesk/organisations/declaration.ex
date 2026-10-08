defmodule DueDesk.Organisations.Declaration do
  @moduledoc """
  Evidence that a person declared they are authorised to manage an
  Organisation in DueDesk. A new row is written when an Organisation is
  created and whenever its type or identifier changes. Rows are never
  updated.

  The IP address and user agent are stored here only, never in audit rows
  or logs.
  """
  use Ecto.Schema

  @version "2026-10-v1"

  @text "I confirm that I am authorised to manage the compliance records of this " <>
          "Organisation, and that the details above are correct. DueDesk may suspend an " <>
          "Organisation that was added without authorisation."

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "organisation_declarations" do
    field :customer_account_id, :binary_id
    field :version, :string
    field :text_hash, :string
    field :accepted_at, :utc_datetime_usec
    field :ip, :string
    field :user_agent, :string

    belongs_to :organisation, DueDesk.Organisations.Organisation
    belongs_to :user, DueDesk.Accounts.User

    field :inserted_at, :utc_datetime, read_after_writes: true
  end

  @doc "The current declaration version."
  def version, do: @version

  @doc "The exact declaration text shown to the person."
  def text, do: @text

  @doc "SHA-256 of the declaration text, hex encoded."
  def text_hash, do: :crypto.hash(:sha256, @text) |> Base.encode16(case: :lower)

  @doc """
  Builds a declaration for `organisation`, accepted now by the scope's user.

  `meta` may carry `:ip` and `:user_agent` from the browser connection.
  """
  def build(scope, organisation, meta) do
    %__MODULE__{
      customer_account_id: organisation.customer_account_id,
      organisation_id: organisation.id,
      user_id: scope.user.id,
      version: @version,
      text_hash: text_hash(),
      accepted_at: DateTime.utc_now(),
      ip: meta[:ip],
      user_agent: meta[:user_agent] && String.slice(meta[:user_agent], 0, 512)
    }
  end
end

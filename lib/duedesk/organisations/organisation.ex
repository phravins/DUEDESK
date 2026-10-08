defmodule DueDesk.Organisations.Organisation do
  @moduledoc """
  A business whose obligations an account tracks. Organisations classify
  DueItems; they never grant or restrict access.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias DueDesk.Organisations.Identifier

  @statuses ~w(active archived)

  @duplicate_message "This Organisation is already registered in DueDesk."

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "organisations" do
    field :name, :string
    field :type, :string
    field :identifier_type, :string
    field :identifier, :string
    field :normalized_identifier, :string
    field :gstin, :string
    field :status, :string, default: "active"
    field :archived_at, :utc_datetime

    field :declaration_accepted, :boolean, virtual: true, default: false

    belongs_to :customer_account, DueDesk.Tenancy.CustomerAccount
    belongs_to :archived_by_user, DueDesk.Accounts.User
    belongs_to :created_by_user, DueDesk.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  @doc "The only message shown when an identifier is already registered."
  def duplicate_message, do: @duplicate_message

  @doc """
  Changeset for creating and editing an Organisation.

  The declaration must be accepted for a new Organisation and whenever the
  type or identifier changes.
  """
  def changeset(organisation, attrs) do
    organisation
    |> cast(attrs, [:name, :type, :identifier, :gstin, :declaration_accepted])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name], message: "enter the Organisation name")
    |> validate_length(:name, min: 2, max: 160)
    |> validate_required([:type], message: "choose the Organisation type")
    |> validate_inclusion(:type, Identifier.types())
    |> put_identifier()
    |> put_gstin()
    |> maybe_require_declaration()
    |> unique_constraint([:identifier_type, :normalized_identifier],
      name: :organisations_identifier_type_normalized_identifier_index,
      error_key: :identifier,
      message: @duplicate_message
    )
  end

  @doc "True when saving this changeset needs a new declaration."
  def declaration_required?(%Ecto.Changeset{data: data} = changeset) do
    is_nil(data.id) or changed?(changeset, :type) or changed?(changeset, :identifier_type) or
      changed?(changeset, :normalized_identifier)
  end

  defp put_identifier(changeset) do
    identifier_type = Identifier.identifier_type(get_field(changeset, :type))
    changeset = put_change(changeset, :identifier_type, identifier_type)

    case get_field(changeset, :identifier) do
      blank when blank in [nil, ""] ->
        add_error(changeset, :identifier, "enter the #{Identifier.label(identifier_type)}")

      _ when is_nil(identifier_type) ->
        changeset

      value ->
        normalized = Identifier.normalize(value)

        if Identifier.valid?(identifier_type, normalized) do
          changeset
          |> put_change(:normalized_identifier, normalized)
          |> put_change(:identifier, Identifier.format(identifier_type, normalized))
        else
          add_error(
            changeset,
            :identifier,
            "enter a valid #{Identifier.label(identifier_type)}, e.g. #{Identifier.example(identifier_type)}"
          )
        end
    end
  end

  defp put_gstin(changeset) do
    case get_change(changeset, :gstin) do
      nil ->
        changeset

      value ->
        normalized = Identifier.normalize(value)

        if Identifier.valid_gstin?(normalized) do
          put_change(changeset, :gstin, normalized)
        else
          add_error(changeset, :gstin, "enter a valid 15-character GSTIN, e.g. 27AAPFU0939F1ZV")
        end
    end
  end

  defp maybe_require_declaration(changeset) do
    if declaration_required?(changeset) do
      validate_acceptance(changeset, :declaration_accepted,
        message: "confirm the declaration to continue"
      )
    else
      changeset
    end
  end
end

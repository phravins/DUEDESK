defmodule DueDesk.Notifications.Delivery do
  @moduledoc """
  One message to one person on one channel: a reminder or an event
  notice. Rows are created `pending` together with their job and end
  `sent`, `failed` or `skipped` (no longer relevant when the job ran).

  `dedupe_key` is unique, so the same reminder is never queued twice.
  `error` holds a short code such as `timeout` or `http_500`, never a
  message body, a token or a full mobile number.
  """
  use Ecto.Schema

  @kinds ~w(reminder assignment renewal_review awaiting_disposition)
  @channels ~w(email whatsapp)
  @statuses ~w(pending sent failed skipped)

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "notification_deliveries" do
    field :kind, :string
    field :channel, :string
    field :target_date, :date
    field :offset_days, :integer
    field :escalated, :boolean, default: false
    field :status, :string, default: "pending"
    field :attempts, :integer, default: 0
    field :error, :string
    field :sent_at, :utc_datetime
    field :dedupe_key, :string

    belongs_to :customer_account, DueDesk.Tenancy.CustomerAccount
    belongs_to :user, DueDesk.Accounts.User
    belongs_to :due_item, DueDesk.DueItems.DueItem
    belongs_to :cycle, DueDesk.DueItems.Cycle
    belongs_to :reminder_rule, DueDesk.DueItems.ReminderRule

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds
  def channels, do: @channels
  def statuses, do: @statuses

  @doc "Human label for a channel."
  def channel_label("email"), do: "Email"
  def channel_label("whatsapp"), do: "WhatsApp"

  @doc "Human label for a status."
  def status_label("pending"), do: "Queued"
  def status_label("sent"), do: "Sent"
  def status_label("failed"), do: "Failed"
  def status_label("skipped"), do: "Skipped"

  @doc "Human label for a kind."
  def kind_label("reminder"), do: "Reminder"
  def kind_label("assignment"), do: "Assignment"
  def kind_label("renewal_review"), do: "Renewal review"
  def kind_label("awaiting_disposition"), do: "Awaiting decision"
end

defmodule DueDesk.Notifications.Email do
  @moduledoc """
  The text of notification emails and WhatsApp messages.

  Messages carry the DueItem's title, Organisation, dates and a link,
  never notes or document contents. Expects a delivery with its user,
  cycle (and the person who closed it) and DueItem (with Organisation,
  current cycle and active assignments) preloaded.
  """

  import Swoosh.Email

  alias DueDesk.DueItems.{Cycle, DueItem}
  alias DueDesk.Notifications.Delivery
  alias DueDeskWeb.Format

  @doc "The email for `delivery`."
  def build(%Delivery{user: user} = delivery) do
    new()
    |> to({user.name, user.email})
    |> from(Application.fetch_env!(:duedesk, :mail_from))
    |> subject(headline(delivery))
    |> text_body(body(delivery))
  end

  @doc """
  The WhatsApp request for a reminder: a template name and its values.
  `delivery_id` lets the receiver drop a request it has already handled.
  """
  def whatsapp_payload(%Delivery{user: user, due_item: item, cycle: cycle} = delivery) do
    effective = Cycle.effective_date(cycle)

    %{
      delivery_id: delivery.id,
      template: if(delivery.escalated, do: "duedesk_overdue", else: "duedesk_reminder"),
      to: user.mobile_number,
      name: user.name,
      title: item.title,
      organisation: item.organisation.name,
      date: Format.date(effective),
      days: Date.diff(effective, delivery.target_date),
      link: link(item)
    }
  end

  @doc "The subject line, e.g. \"Fire NOC is due in 7 days (15 Mar 2027)\"."
  def headline(%Delivery{kind: "reminder", due_item: item, cycle: cycle} = delivery) do
    effective = Cycle.effective_date(cycle)
    date = Format.date(effective)
    due? = not is_nil(cycle.due_date)

    case Date.diff(effective, delivery.target_date) do
      0 ->
        "#{item.title} #{if due?, do: "is due", else: "expires"} today (#{date})"

      1 ->
        "#{item.title} #{if due?, do: "is due", else: "expires"} tomorrow (#{date})"

      days when days > 1 ->
        "#{item.title} #{if due?, do: "is due", else: "expires"} in #{days} days (#{date})"

      _ ->
        "Overdue: #{item.title} #{if due?, do: "was due", else: "expired"} on #{date}"
    end
  end

  def headline(%Delivery{kind: "assignment", due_item: item, user: user}) do
    if primary?(item, user.id),
      do: "You are now responsible for #{item.title}",
      else: "You have been added to #{item.title}"
  end

  def headline(%Delivery{kind: "renewal_review", due_item: item}),
    do: "Renewal to review: #{item.title}"

  def headline(%Delivery{kind: "awaiting_disposition", due_item: item}),
    do: "Completed: #{item.title} needs your decision"

  defp body(%Delivery{user: user, due_item: item} = delivery) do
    """
    Hi #{user.name},

    #{intro(delivery)}

    DueItem: #{item.title}
    Organisation: #{item.organisation.name}
    #{dates(delivery)}

    Open it in DueDesk:
    #{link(item)}

    You can change which notifications you get in your DueDesk settings:
    #{DueDeskWeb.Endpoint.url()}/users/settings

    — DueDesk
    """
  end

  defp intro(%Delivery{kind: "reminder", escalated: true}),
    do: "This DueItem is overdue. Please renew or complete it, or make sure someone does."

  defp intro(%Delivery{kind: "reminder"}),
    do: "This is a reminder that the DueItem below is coming up."

  defp intro(%Delivery{kind: "assignment", due_item: item, user: user}) do
    if primary?(item, user.id),
      do: "You are now the Primary Responsible for this DueItem.",
      else: "You have been added as an Additional Assignee on this DueItem."
  end

  defp intro(%Delivery{kind: "renewal_review", cycle: cycle}),
    do: "#{name(cycle.completed_by_user)} renewed this DueItem. Please review the new dates."

  defp intro(%Delivery{kind: "awaiting_disposition", cycle: cycle}) do
    "#{name(cycle.completed_by_user)} marked this DueItem as completed. " <>
      "Archive it, or re-date and reactivate it."
  end

  # Reminders show the dates they were sent for; event notices show the
  # DueItem's dates now (after a renewal, the new ones).
  defp dates(%Delivery{kind: "reminder", cycle: cycle}), do: date_lines(cycle)

  defp dates(%Delivery{due_item: %DueItem{disposition_state: "awaiting_new_dates"}}),
    do: date_lines(nil)

  defp dates(%Delivery{due_item: %DueItem{current_cycle: cycle}}), do: date_lines(cycle)

  defp date_lines(nil), do: "Dates: to be set by an Administrator"

  defp date_lines(%Cycle{} = cycle) do
    [
      cycle.due_date && "Due Date: #{Format.date(cycle.due_date)}",
      cycle.expiry_date && "Expiry Date: #{Format.date(cycle.expiry_date)}"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp primary?(%DueItem{active_assignments: assignments}, user_id),
    do: Enum.any?(assignments, &(&1.role == "primary" and &1.user_id == user_id))

  defp name(nil), do: "Someone"
  defp name(user), do: user.name

  defp link(%DueItem{id: id}), do: "#{DueDeskWeb.Endpoint.url()}/due-items/#{id}"
end

defmodule DueDesk.Audit.Humanize do
  @moduledoc """
  Turns audit events into sentences for a DueItem's history, such as
  "Priya changed Due Date from 15 Mar 2027 to 20 Mar 2027".
  """

  import Ecto.Query, warn: false

  alias DueDesk.Repo
  alias DueDesk.Accounts.{Scope, User}
  alias DueDesk.Audit.AuditEvent
  alias DueDesk.DueItems.{Recurrence, ReminderRule, Status}
  alias DueDesk.Tenancy.Membership

  @type entry :: %{
          id: Ecto.UUID.t(),
          at: DateTime.t(),
          action: String.t(),
          actor: String.t(),
          sentence: String.t(),
          details: [String.t()]
        }

  @labels %{
    "title" => "Title",
    "description" => "Description",
    "reference_number" => "Reference Number",
    "related_party" => "Related Party",
    "organisation" => "Organisation",
    "category" => "Category",
    "recurrence" => "Recurrence",
    "start_date" => "Start Date",
    "due_date" => "Due Date",
    "expiry_date" => "Expiry Date",
    "reminders" => "Reminders"
  }

  @field_order ~w(title organisation category due_date expiry_date start_date reference_number
                  related_party description recurrence reminders)

  @doc """
  Describes `events`. Names of actors and assignees are loaded in one
  query, limited to members of the scope's account.
  """
  @spec describe([AuditEvent.t()], Scope.t()) :: [entry()]
  def describe(events, %Scope{} = scope) do
    names = load_names(events, scope)
    Enum.map(events, &entry(&1, names))
  end

  defp entry(%AuditEvent{} = event, names) do
    actor = actor_name(event, names)

    {sentence, details} =
      sentence(event.action, event.changes || %{}, event.metadata || %{}, names)

    %{
      id: event.id,
      at: event.inserted_at,
      action: event.action,
      actor: actor,
      sentence: "#{actor} #{sentence}",
      details: details
    }
  end

  defp sentence("due_item.created", _changes, _meta, _names), do: {"created this DueItem", []}
  defp sentence("due_item.archived", _changes, _meta, _names), do: {"archived this DueItem", []}

  defp sentence("due_item.restored", changes, _meta, names),
    do: {"restored this DueItem", reactivation_details(changes, names)}

  defp sentence("due_item.reactivated", changes, _meta, names),
    do: {"re-dated and reactivated this DueItem", reactivation_details(changes, names)}

  defp sentence("due_item.renewed", changes, meta, _names) do
    next =
      cond do
        meta["next_dates"] == "pending" ->
          "New dates are needed from an Administrator"

        match?([_, new] when is_binary(new), changes["due_date"]) ->
          "Next Due Date #{value("due_date", List.last(changes["due_date"]))}"

        match?([_, new] when is_binary(new), changes["expiry_date"]) ->
          "Next Expiry Date #{value("expiry_date", List.last(changes["expiry_date"]))}"

        true ->
          nil
      end

    {Enum.join(Enum.reject(["renewed this DueItem", next], &is_nil/1), ". "), []}
  end

  defp sentence("due_item.completed", _changes, _meta, _names),
    do: {"marked this DueItem as completed", []}

  defp sentence("due_item.renewal_reviewed", _changes, _meta, _names),
    do: {"reviewed the renewal", []}

  defp sentence("due_item.deleted", _changes, meta, _names),
    do: {"permanently deleted \u201c#{meta["title"]}\u201d", []}

  defp sentence("note.added", _changes, _meta, _names), do: {"added a note", []}

  defp sentence("due_item.updated", changes, _meta, _names) do
    phrases =
      for field <- @field_order, Map.has_key?(changes, field) do
        change_phrase(field, Map.fetch!(changes, field))
      end

    case phrases do
      [one] -> {one, []}
      [] -> {"updated this DueItem", []}
      many -> {"updated this DueItem", Enum.map(many, &capitalize/1)}
    end
  end

  defp sentence("due_item.assigned", changes, _meta, names) do
    case assignment_phrases(changes, names) do
      [] -> {"changed responsibility", []}
      phrases -> {join(phrases), []}
    end
  end

  defp sentence("due_item.status_overridden", changes, meta, _names) do
    [old, new] = Map.get(changes, "status", [nil, nil])
    reason = meta["reason"]

    {"changed the status from #{status_label(old)} to #{status_label(new)}",
     if(reason, do: ["Reason: #{reason}"], else: [])}
  end

  defp sentence("due_item.status_override_cleared", _changes, _meta, _names),
    do: {"removed the status override", []}

  defp sentence(action, _changes, _meta, _names), do: {"recorded #{action}", []}

  defp reactivation_details(changes, names) do
    dates =
      for field <- @field_order, Map.has_key?(changes, field) do
        change_phrase(field, Map.fetch!(changes, field))
      end

    Enum.map(dates ++ assignment_phrases(changes, names), &capitalize/1)
  end

  defp assignment_phrases(changes, names) do
    primary =
      case changes["primary"] do
        [_old, new] when is_binary(new) ->
          ["assigned #{name(names, new)} as Primary Responsible"]

        [old, nil] when is_binary(old) ->
          ["removed #{name(names, old)} as Primary Responsible"]

        _ ->
          []
      end

    additional =
      case changes["additional"] do
        [old, new] when is_list(old) and is_list(new) ->
          Enum.map(new -- old, &"added #{name(names, &1)} as Additional Assignee") ++
            Enum.map(old -- new, &"removed #{name(names, &1)} as Additional Assignee")

        _ ->
          []
      end

    primary ++ additional
  end

  defp change_phrase("description", _), do: "changed the Description"

  defp change_phrase("recurrence", [old, new]) do
    "changed Recurrence from #{recurrence(old)} to #{recurrence(new)}"
  end

  defp change_phrase("reminders", [_old, []]), do: "turned off all reminders"

  defp change_phrase("reminders", [_old, new]) do
    "changed Reminders to #{Enum.map_join(new, ", ", &String.downcase(ReminderRule.describe(&1)))}"
  end

  defp change_phrase(field, [old, new]) do
    label = Map.fetch!(@labels, field)

    cond do
      is_nil(old) -> "set #{label} to #{value(field, new)}"
      is_nil(new) -> "removed the #{label}"
      true -> "changed #{label} from #{value(field, old)} to #{value(field, new)}"
    end
  end

  defp value(field, iso) when field in ~w(start_date due_date expiry_date) do
    case Date.from_iso8601(iso) do
      {:ok, date} -> Calendar.strftime(date, "%d %b %Y")
      _ -> iso
    end
  end

  defp value(_field, value), do: to_string(value)

  defp recurrence([recurrence, unit, interval]),
    do: Recurrence.describe(recurrence, unit, interval) |> lower_first()

  defp recurrence(other) when is_binary(other), do: Recurrence.describe(other, nil, nil)
  defp recurrence(_), do: "does not repeat"

  defp status_label(nil), do: "the computed status"

  defp status_label(name) do
    case Status.parse(name) do
      nil -> name
      status -> Status.label(status)
    end
  end

  defp actor_name(%AuditEvent{actor_type: "user", actor_id: id}, names), do: name(names, id)
  defp actor_name(%AuditEvent{actor_type: "operator"}, _names), do: "DueDesk Support"
  defp actor_name(%AuditEvent{}, _names), do: "DueDesk"

  defp name(_names, nil), do: "Someone"
  defp name(names, id), do: Map.get(names, id, "A former member")

  # Only names of people in this account, so history never reveals others.
  defp load_names(events, scope) do
    ids =
      events
      |> Enum.flat_map(fn event ->
        [event.actor_id | assignment_ids(event.changes || %{})]
      end)
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    if ids == [] do
      %{}
    else
      account_id = Scope.account_id!(scope)

      from(u in User,
        join: m in Membership,
        on: m.user_id == u.id and m.customer_account_id == ^account_id,
        where: u.id in ^ids,
        select: {u.id, u.name}
      )
      |> Repo.all()
      |> Map.new()
    end
  end

  defp assignment_ids(changes) do
    primary = List.wrap(changes["primary"])

    additional =
      case changes["additional"] do
        [old, new] when is_list(old) and is_list(new) -> old ++ new
        _ -> []
      end

    primary ++ additional
  end

  defp join([one]), do: one
  defp join(phrases), do: Enum.join(Enum.drop(phrases, -1), ", ") <> " and " <> List.last(phrases)

  defp capitalize(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest
  defp lower_first(<<first::utf8, rest::binary>>), do: String.downcase(<<first::utf8>>) <> rest
end

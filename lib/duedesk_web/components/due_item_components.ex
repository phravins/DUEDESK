defmodule DueDeskWeb.DueItemComponents do
  @moduledoc """
  DueItem pieces shared by the list, the detail page, the dashboard and
  the Organisation pages: the status badges, who is responsible and a
  compact row.
  """
  use DueDeskWeb, :html

  alias DueDesk.DueItems.{DueItem, Status}

  @doc """
  The effective status of a DueItem loaded with its current cycle, for
  `today` and the account's due-soon window.
  """
  def item_status(%DueItem{} = item, today, due_soon_days) do
    Status.effective(item, item.current_cycle, today, due_soon_days)
  end

  @doc """
  The status badge, followed by an Unassigned badge when nobody is
  responsible for an active DueItem. A DueItem waiting for an
  Administrator shows that instead of its date status.
  """
  attr :item, DueItem, required: true
  attr :status, :atom, required: true
  attr :overridden, :boolean, default: false

  def due_item_status(assigns) do
    assigns = assign(assigns, :shown, disposition_status(assigns.item) || assigns.status)

    ~H"""
    <span class="inline-flex flex-wrap items-center gap-1.5">
      <.status_badge status={@shown} />
      <span
        :if={@overridden && @shown == @status && @item.current_cycle.status_override}
        class="text-[11px] font-medium text-zinc-400"
        title="Status set by an Administrator"
      >
        Set manually
      </span>
      <.status_badge
        :if={
          @item.status == "active" and is_nil(@item.disposition_state) and DueItem.unassigned?(@item)
        }
        status={:unassigned}
      />
    </span>
    """
  end

  @doc """
  `:awaiting` or `:needs_dates` for a DueItem waiting for an
  Administrator, else nil.
  """
  def disposition_status(%DueItem{status: "active", disposition_state: state}) do
    case state do
      "awaiting_admin_disposition" -> :awaiting
      "awaiting_new_dates" -> :needs_dates
      _ -> nil
    end
  end

  def disposition_status(%DueItem{}), do: nil

  @doc "An avatar with initials, coloured by name."
  attr :name, :string, required: true
  attr :size, :string, default: "sm", values: ~w(sm md)

  def avatar(assigns) do
    ~H"""
    <span
      class={[
        "inline-flex shrink-0 items-center justify-center rounded-full font-semibold text-white",
        if(@size == "sm", do: "size-6 text-[10px]", else: "size-8 text-xs"),
        avatar_colour(@name)
      ]}
      aria-hidden="true"
    >
      {initials(@name)}
    </span>
    """
  end

  @doc """
  The Primary Responsible, with a count of Additional Assignees, or
  "Unassigned".
  """
  attr :item, DueItem, required: true

  def responsibility(assigns) do
    assigns =
      assigns
      |> assign(:primary, DueItem.primary_user(assigns.item))
      |> assign(:additional, length(DueItem.additional_users(assigns.item)))

    ~H"""
    <span :if={@primary} class="inline-flex min-w-0 items-center gap-2">
      <.avatar name={@primary.name} />
      <span class="truncate text-zinc-700">{@primary.name}</span>
      <span
        :if={@additional > 0}
        class="shrink-0 rounded-full bg-[#efefed] px-1.5 py-px text-[11px] text-zinc-500"
        title={"#{@additional} Additional Assignee(s)"}
      >
        +{@additional}
      </span>
    </span>
    <span :if={!@primary} class="text-zinc-400">Unassigned</span>
    """
  end

  @doc """
  A compact DueItem row for dashboard and Organisation cards: title,
  Organisation and category, the date that drives status and the badge.
  """
  attr :id, :string, required: true
  attr :item, DueItem, required: true
  attr :status, :atom, required: true
  attr :show_organisation, :boolean, default: true

  def due_item_row(assigns) do
    ~H"""
    <li id={@id}>
      <.link
        navigate={~p"/due-items/#{@item}"}
        class="group -mx-2 flex items-center gap-3 rounded-md px-2 py-2.5 transition hover:bg-[#fafaf9]"
      >
        <span class="min-w-0 flex-1">
          <span class="block truncate text-sm font-medium text-ink group-hover:underline group-hover:underline-offset-2">
            {@item.title}
          </span>
          <span class="block truncate text-xs text-muted">
            {if @show_organisation, do: "#{@item.organisation.name} · "}{@item.category.name}
          </span>
        </span>
        <span class="hidden shrink-0 text-right text-xs tabular-nums text-zinc-500 sm:block">
          {date_label(@item)}
        </span>
        <.status_badge status={@status} class="shrink-0" />
      </.link>
    </li>
    """
  end

  @doc "\"Due 15 Mar 2027\" or \"Expires 15 Mar 2027\"."
  def date_label(%DueItem{current_cycle: cycle}) do
    cond do
      cycle.due_date -> "Due #{date(cycle.due_date)}"
      cycle.expiry_date -> "Expires #{date(cycle.expiry_date)}"
      true -> "—"
    end
  end

  @avatar_colours ~w(bg-rose-500 bg-violet-500 bg-sky-600 bg-emerald-600 bg-amber-500 bg-indigo-500)

  defp avatar_colour(name),
    do: Enum.at(@avatar_colours, :erlang.phash2(name, length(@avatar_colours)))

  defp initials(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end
end

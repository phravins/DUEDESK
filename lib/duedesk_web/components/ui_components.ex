defmodule DueDeskWeb.UIComponents do
  @moduledoc """
  DueDesk-specific UI building blocks: status badges, empty states,
  summary cards and page headers.
  """
  use Phoenix.Component

  import DueDeskWeb.CoreComponents, only: [icon: 1]

  @statuses %{
    overdue: %{
      label: "Overdue",
      icon: "hero-exclamation-circle-mini",
      class: "bg-error/10 text-error ring-error/30"
    },
    due_soon: %{
      label: "Due Soon",
      icon: "hero-clock-mini",
      class: "bg-warning/15 text-warning ring-warning/30"
    },
    up_to_date: %{
      label: "Up to Date",
      icon: "hero-check-circle-mini",
      class: "bg-success/10 text-success ring-success/30"
    },
    archived: %{
      label: "Archived",
      icon: "hero-archive-box-mini",
      class: "bg-base-200 text-base-content/70 ring-base-300"
    },
    unassigned: %{
      label: "Unassigned",
      icon: "hero-user-minus-mini",
      class: "bg-info/10 text-info ring-info/30"
    }
  }

  @doc """
  Renders a status badge. Status is always shown as text with an icon,
  never by colour alone (UX spec §77).

      <.status_badge status={:overdue} />
  """
  attr :status, :atom, required: true, values: Map.keys(@statuses)
  attr :class, :string, default: nil

  def status_badge(assigns) do
    assigns = assign(assigns, :s, Map.fetch!(@statuses, assigns.status))

    ~H"""
    <span class={[
      "inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset whitespace-nowrap",
      @s.class,
      @class
    ]}>
      <.icon name={@s.icon} class="size-3.5" />
      {@s.label}
    </span>
    """
  end

  @doc """
  An empty state with an icon, title, explanation and optional action.
  """
  attr :icon, :string, default: "hero-inbox"
  attr :title, :string, required: true
  attr :id, :string, default: nil
  slot :inner_block
  slot :action

  def empty_state(assigns) do
    ~H"""
    <div
      id={@id}
      class="text-center py-12 px-6 rounded-2xl border border-dashed border-base-300 bg-base-100"
    >
      <div class="mx-auto size-12 rounded-full bg-primary/10 text-primary flex items-center justify-center">
        <.icon name={@icon} class="size-6" />
      </div>
      <h3 class="mt-4 text-base font-semibold">{@title}</h3>
      <div :if={@inner_block != []} class="mt-2 text-sm text-base-content/70 max-w-md mx-auto">
        {render_slot(@inner_block)}
      </div>
      <div :if={@action != []} class="mt-6 flex flex-wrap justify-center gap-3">
        {render_slot(@action)}
      </div>
    </div>
    """
  end

  @doc """
  A dashboard summary card that links to a filtered list.
  """
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :status, :atom, required: true
  attr :navigate, :string, required: true

  def summary_card(assigns) do
    assigns = assign(assigns, :s, Map.fetch!(@statuses, assigns.status))

    ~H"""
    <.link
      id={@id}
      navigate={@navigate}
      class="group block rounded-2xl bg-base-100 border border-base-300 p-5 hover:border-primary/40 hover:shadow-sm transition"
    >
      <div class="flex items-center justify-between">
        <p class="text-sm font-medium text-base-content/70">{@label}</p>
        <span class={[
          "size-8 rounded-lg flex items-center justify-center ring-1 ring-inset",
          @s.class
        ]}>
          <.icon name={@s.icon} class="size-4" />
        </span>
      </div>
      <p class="mt-3 text-3xl font-semibold tabular-nums">{@count}</p>
      <p class="mt-1 text-xs text-base-content/60 group-hover:text-primary transition">
        View list →
      </p>
    </.link>
    """
  end

  @doc """
  The title row at the top of an app page.
  """
  attr :title, :string, required: true
  slot :subtitle
  slot :actions

  def page_header(assigns) do
    ~H"""
    <div class="flex flex-col sm:flex-row sm:items-end sm:justify-between gap-4 mb-6">
      <div>
        <h1 class="text-2xl font-semibold tracking-tight">{@title}</h1>
        <p :if={@subtitle != []} class="mt-1 text-sm text-base-content/70">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div :if={@actions != []} class="flex flex-wrap gap-2">{render_slot(@actions)}</div>
    </div>
    """
  end
end

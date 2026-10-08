defmodule DueDeskWeb.UIComponents do
  @moduledoc """
  DueDesk building blocks: page headers, cards, tabs, status badges, stat
  cards, meters, empty states, limit notices and the auth page heading.
  """
  use Phoenix.Component

  import DueDeskWeb.CoreComponents, only: [icon: 1]

  @statuses %{
    overdue: %{
      label: "Overdue",
      icon: "hero-exclamation-circle-mini",
      class: "bg-rose-50 text-rose-700 ring-rose-200/70",
      dot: "bg-rose-500"
    },
    due_soon: %{
      label: "Due Soon",
      icon: "hero-clock-mini",
      class: "bg-amber-50 text-amber-700 ring-amber-200/70",
      dot: "bg-amber-400"
    },
    up_to_date: %{
      label: "Up to Date",
      icon: "hero-check-circle-mini",
      class: "bg-emerald-50 text-emerald-700 ring-emerald-200/70",
      dot: "bg-emerald-500"
    },
    archived: %{
      label: "Archived",
      icon: "hero-archive-box-mini",
      class: "bg-zinc-100 text-zinc-600 ring-zinc-200",
      dot: "bg-zinc-400"
    },
    unassigned: %{
      label: "Unassigned",
      icon: "hero-user-minus-mini",
      class: "bg-sky-50 text-sky-700 ring-sky-200/70",
      dot: "bg-sky-500"
    }
  }

  @doc """
  Status is always shown as text with an icon, never by colour alone.

      <.status_badge status={:overdue} />
  """
  attr :status, :atom, required: true, values: Map.keys(@statuses)
  attr :class, :string, default: nil

  def status_badge(assigns) do
    assigns = assign(assigns, :s, Map.fetch!(@statuses, assigns.status))

    ~H"""
    <span class={[
      "inline-flex items-center gap-1 whitespace-nowrap rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset",
      @s.class,
      @class
    ]}>
      <.icon name={@s.icon} class="size-3.5" />
      {@s.label}
    </span>
    """
  end

  @doc """
  The title row at the top of an app page: a breadcrumb section, the page
  title and the page actions.
  """
  attr :title, :string, required: true
  attr :eyebrow, :string, default: nil
  attr :icon, :string, default: "hero-folder"
  slot :subtitle
  slot :actions

  def page_header(assigns) do
    ~H"""
    <div class="mb-8 border-b border-line pb-6">
      <div class="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
        <h1 class="flex min-w-0 items-center gap-2.5 text-[22px] leading-tight tracking-[-0.02em] text-ink sm:text-[26px]">
          <span :if={@eyebrow} class="flex shrink-0 items-center gap-2 text-zinc-400">
            <.icon name={@icon} class="size-5 sm:size-6" />
            <span class="truncate">{@eyebrow}</span>
            <span class="size-1 rounded-full bg-zinc-300" aria-hidden="true" />
          </span>
          <span class="truncate">{@title}</span>
        </h1>
        <div :if={@actions != []} class="flex flex-wrap items-center gap-2">
          {render_slot(@actions)}
        </div>
      </div>
      <p :if={@subtitle != []} class="mt-2 max-w-2xl text-sm text-muted">
        {render_slot(@subtitle)}
      </p>
    </div>
    """
  end

  @doc """
  A small bordered chip, for context such as today's date.
  """
  attr :icon, :string, default: nil
  slot :inner_block, required: true

  def pill(assigns) do
    ~H"""
    <span class="inline-flex h-9 items-center gap-2 rounded-md border border-line bg-white px-3 text-sm text-zinc-600">
      <.icon :if={@icon} name={@icon} class="size-4 text-zinc-400" />
      {render_slot(@inner_block)}
    </span>
    """
  end

  @doc """
  A bordered white card with an optional title row, action and footer.
  """
  attr :id, :string, default: nil
  attr :title, :string, default: nil
  attr :class, :any, default: nil
  attr :rest, :global
  slot :subtitle
  slot :action
  slot :footer
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <section id={@id} class={["rounded-lg border border-line bg-white", @class]} {@rest}>
      <div class="p-5">
        <div :if={@title} class="mb-5 flex items-start justify-between gap-4">
          <div>
            <h2 class="text-[15px] font-semibold text-ink">{@title}</h2>
            <p :if={@subtitle != []} class="mt-0.5 text-sm text-muted">
              {render_slot(@subtitle)}
            </p>
          </div>
          {render_slot(@action)}
        </div>
        {render_slot(@inner_block)}
      </div>
      <div :if={@footer != []} class="border-t border-line px-5 py-3 text-sm">
        {render_slot(@footer)}
      </div>
    </section>
    """
  end

  @doc """
  A grey circular icon link, used as a card's action button.
  """
  attr :navigate, :string, required: true
  attr :icon, :string, default: "hero-arrow-up-right"
  attr :label, :string, required: true

  def round_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      aria-label={@label}
      title={@label}
      class="flex size-8 shrink-0 items-center justify-center rounded-full bg-[#efefed] text-zinc-500 transition hover:bg-[#e4e4e1] hover:text-ink"
    >
      <.icon name={@icon} class="size-4" />
    </.link>
    """
  end

  @doc """
  A dashboard status card with a large count, linking to a filtered list.
  """
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :status, :atom, required: true
  attr :navigate, :string, required: true
  attr :hint, :string, required: true

  def stat_card(assigns) do
    assigns = assign(assigns, :s, Map.fetch!(@statuses, assigns.status))

    ~H"""
    <.link
      id={@id}
      navigate={@navigate}
      class="group flex flex-col rounded-lg border border-line bg-white transition duration-200 hover:border-zinc-300 hover:shadow-xs"
    >
      <div class="p-5">
        <div class="flex items-center justify-between gap-3">
          <p class="flex items-center gap-2 text-sm text-zinc-600">
            <span class={["size-2 rounded-full", @s.dot]} />
            {@label}
          </p>
          <span class="flex size-7 items-center justify-center rounded-full bg-[#efefed] text-zinc-500 transition group-hover:bg-navy group-hover:text-white">
            <.icon name="hero-arrow-up-right-mini" class="size-4" />
          </span>
        </div>
        <p class="mt-5 text-[40px] font-medium leading-none tracking-[-0.04em] text-ink tabular-nums">
          {@count}
        </p>
      </div>
      <div class="mt-auto flex items-center justify-between gap-2 border-t border-line px-5 py-3">
        <.status_badge status={@status} />
        <span class="truncate text-xs text-zinc-400">{@hint}</span>
      </div>
    </.link>
    """
  end

  @doc """
  A labelled usage bar.
  """
  attr :label, :string, required: true
  attr :used, :integer, required: true
  attr :limit, :any, required: true, doc: "an integer or :unlimited"
  attr :display, :string, default: nil, doc: "overrides the `used of limit` text"

  def meter(assigns) do
    percent =
      case assigns.limit do
        :unlimited -> 0
        0 -> 100
        limit -> min(100, round(assigns.used * 100 / limit))
      end

    assigns =
      assigns
      |> assign(:percent, percent)
      |> assign_new(:text, fn ->
        assigns.display ||
          "#{assigns.used} of #{if assigns.limit == :unlimited, do: "Unlimited", else: assigns.limit}"
      end)

    ~H"""
    <div>
      <div class="mb-2 flex items-baseline justify-between gap-3 text-sm">
        <span class="text-zinc-600">{@label}</span>
        <span class="font-medium text-ink tabular-nums">{@text}</span>
      </div>
      <div class="h-1.5 overflow-hidden rounded-full bg-[#efefed]">
        <div
          class={[
            "h-full rounded-full transition-all duration-700",
            cond do
              @percent >= 90 -> "bg-rose-500"
              @percent >= 75 -> "bg-amber-400"
              true -> "bg-navy"
            end
          ]}
          style={"width: #{max(@percent, 2)}%"}
        />
      </div>
    </div>
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
      class="rounded-lg border border-dashed border-zinc-300 bg-white px-6 py-14 text-center"
    >
      <div class="mx-auto flex size-11 items-center justify-center rounded-full bg-[#efefed] text-zinc-500">
        <.icon name={@icon} class="size-5" />
      </div>
      <h3 class="mt-4 text-base font-semibold text-ink">{@title}</h3>
      <div :if={@inner_block != []} class="mx-auto mt-1.5 max-w-md text-sm text-muted">
        {render_slot(@inner_block)}
      </div>
      <div :if={@action != []} class="mt-6 flex flex-wrap justify-center gap-2">
        {render_slot(@action)}
      </div>
    </div>
    """
  end

  @doc """
  The two-line heading at the top of an auth page: a statement in ink and a
  tagline in grey, with an optional explanation underneath.
  """
  attr :title, :string, required: true
  attr :tagline, :string, default: nil
  attr :eyebrow, :string, default: nil
  slot :inner_block

  def auth_heading(assigns) do
    ~H"""
    <div class="mb-8">
      <p :if={@eyebrow} class="mb-3 text-xs font-medium uppercase tracking-[0.12em] text-zinc-400">
        {@eyebrow}
      </p>
      <h1 class="text-2xl font-semibold leading-tight tracking-[-0.02em]">
        <span class="block text-ink">{@title}</span>
        <span :if={@tagline} class="block text-zinc-400">{@tagline}</span>
      </h1>
      <p :if={@inner_block != []} class="mt-3 text-sm leading-relaxed text-muted">
        {render_slot(@inner_block)}
      </p>
    </div>
    """
  end

  @doc """
  Underlined tabs that patch the current page.

      <.tabs id="organisation-tabs">
        <:tab patch={~p"/organisations"} active={@status == "active"} count={3}>Active</:tab>
      </.tabs>
  """
  attr :id, :string, required: true

  slot :tab, required: true do
    attr :patch, :string, required: true
    attr :active, :boolean
    attr :count, :integer
    attr :id, :string
  end

  def tabs(assigns) do
    ~H"""
    <nav id={@id} class="mb-5 flex gap-6 border-b border-line" aria-label="Tabs">
      <.link
        :for={tab <- @tab}
        id={tab[:id]}
        patch={tab.patch}
        aria-current={tab[:active] && "page"}
        class={[
          "-mb-px inline-flex items-center gap-2 border-b-2 pb-3 text-sm font-medium transition",
          if(tab[:active],
            do: "border-ink text-ink",
            else: "border-transparent text-zinc-500 hover:text-ink"
          )
        ]}
      >
        {render_slot(tab)}
        <span
          :if={tab[:count]}
          class={[
            "rounded-full px-1.5 py-px text-[11px] tabular-nums",
            if(tab[:active], do: "bg-navy text-white", else: "bg-[#efefed] text-zinc-500")
          ]}
        >
          {tab[:count]}
        </span>
      </.link>
    </nav>
    """
  end

  @doc """
  Shown when a plan limit stops an action. Super Admins get a link to the
  plans; everyone else is told to ask their Super Admin.
  """
  attr :id, :string, default: "limit-notice"
  attr :message, :string, required: true
  attr :plans_link, :boolean, default: false

  def limit_notice(assigns) do
    ~H"""
    <div
      id={@id}
      class="mb-5 flex flex-col gap-3 rounded-lg border border-amber-200 bg-amber-50/60 p-4 sm:flex-row sm:items-center"
    >
      <span class="flex size-8 shrink-0 items-center justify-center rounded-full bg-amber-100 text-amber-700">
        <.icon name="hero-sparkles-mini" class="size-4" />
      </span>
      <p class="min-w-0 flex-1 text-sm text-amber-900">{@message}</p>
      <.link
        :if={@plans_link}
        navigate="/account/plans"
        class="inline-flex h-8 shrink-0 items-center gap-1 rounded-md bg-navy px-3 text-[13px] font-medium text-white transition hover:bg-navy-hover"
      >
        View Plans <.icon name="hero-arrow-right-mini" class="size-4" />
      </.link>
    </div>
    """
  end

  @doc """
  The onboarding progress bar: Sign up, Verify email, Account and First
  Organisation. `current` is the step number being completed (3 or 4).
  """
  attr :current, :integer, required: true

  def onboarding_steps(assigns) do
    assigns =
      assign(assigns, :steps, ["Sign up", "Verify email", "Account", "First Organisation"])

    ~H"""
    <ol class="mb-10 flex items-center gap-2 text-xs font-medium" aria-label="Setup progress">
      <li
        :for={{label, number} <- Enum.with_index(@steps, 1)}
        class="flex min-w-0 flex-1 flex-col gap-2"
        aria-current={number == @current && "step"}
      >
        <span class={[
          "h-1 rounded-full",
          if(number > @current, do: "bg-[#ececea]", else: "bg-navy")
        ]} />
        <span class={["truncate", if(number > @current, do: "text-zinc-400", else: "text-ink")]}>
          {label}
        </span>
      </li>
    </ol>
    """
  end

  @doc """
  A label and value row inside a details card.
  """
  attr :label, :string, required: true
  attr :id, :string, default: nil
  slot :inner_block, required: true

  def detail(assigns) do
    ~H"""
    <div id={@id} class="grid gap-1 py-3 sm:grid-cols-3 sm:gap-4">
      <dt class="text-sm text-muted">{@label}</dt>
      <dd class="min-w-0 wrap-break-word text-sm text-ink sm:col-span-2">
        {render_slot(@inner_block)}
      </dd>
    </div>
    """
  end

  @doc """
  In development, points to the local mailbox where emails are delivered.
  """
  def dev_mailbox_notice(assigns) do
    ~H"""
    <p
      :if={Application.get_env(:duedesk, DueDesk.Mailer)[:adapter] == Swoosh.Adapters.Local}
      class="mb-6 flex items-center gap-2 rounded-md bg-brand-soft px-3 py-2 text-xs text-brand"
    >
      <.icon name="hero-beaker-mini" class="size-4" /> Development: emails arrive in
      <a href="/dev/mailbox" target="_blank" class="font-semibold underline underline-offset-2">
        the local mailbox
      </a>
    </p>
    """
  end
end

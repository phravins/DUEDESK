defmodule DueDeskWeb.DashboardLive do
  @moduledoc """
  The landing page after log in (UX spec §11–§14). Super Admins and
  Administrators see account-wide status; Users see only their own work.
  Every count and list goes through `DueDesk.DueItems`, so the visibility
  rule is the same as on the DueItems list.
  """
  use DueDeskWeb, :live_view

  import DueDeskWeb.DueItemComponents

  alias DueDesk.{Billing, DueItems, Permissions, Tenancy}
  alias DueDesk.Billing.Plans

  @timeline_days 30
  @dots_per_day 6

  @reminder_schedule [
    {"90 days before", "First heads-up"},
    {"30 days before", "Time to prepare"},
    {"7 days before", "Final reminder"},
    {"On the due date", "Action due today"},
    {"1 day after", "Escalated to Admins"}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:dashboard}>
      <.page_header
        eyebrow="Dashboard"
        icon="hero-squares-2x2"
        title={if @admin?, do: "Overview", else: "My work"}
      >
        <:subtitle>
          Hello, {first_name(@current_scope.user.name)}. {if @admin?,
            do: "Everything your account must renew, file or complete, in one place.",
            else: "The DueItems you are responsible for, and what needs attention next."}
        </:subtitle>
        <:actions>
          <.pill icon="hero-calendar-days">{Calendar.strftime(@today, "%a")}, {date(@today)}</.pill>
          <.button variant="secondary" navigate={~p"/due-items"}>View DueItems</.button>
          <.button navigate={~p"/due-items/new"}>
            <.icon name="hero-plus" class="size-4" /> Create DueItem
          </.button>
        </:actions>
      </.page_header>

      <div class={[
        "mb-4 grid gap-4 sm:grid-cols-2",
        if(@admin?, do: "xl:grid-cols-4", else: "xl:grid-cols-3")
      ]}>
        <.stat_card
          id="card-overdue"
          label={if @admin?, do: "Overdue", else: "My Overdue"}
          count={@counts.overdue}
          status={:overdue}
          hint="Past the due date"
          navigate={~p"/due-items?status=overdue"}
        />
        <.stat_card
          id="card-due-soon"
          label={if @admin?, do: "Due Soon", else: "My Due Soon"}
          count={@counts.due_soon}
          status={:due_soon}
          hint={"Within #{@current_scope.customer_account.due_soon_days} days"}
          navigate={~p"/due-items?status=due_soon"}
        />
        <.stat_card
          :if={@admin?}
          id="card-unassigned"
          label="Unassigned"
          count={@counts.unassigned}
          status={:unassigned}
          hint="No one responsible"
          navigate={~p"/due-items?assignment=unassigned"}
        />
        <.stat_card
          id="card-up-to-date"
          label={if @admin?, do: "Up to Date", else: "My Up to Date"}
          count={@counts.up_to_date}
          status={:up_to_date}
          hint="Nothing to do yet"
          navigate={~p"/due-items?status=up_to_date"}
        />
      </div>

      <div class="grid gap-4 lg:grid-cols-3">
        <div class="space-y-4 lg:col-span-2">
          <.card
            id="due-timeline"
            title={if @admin?, do: "Due in the next 30 days", else: "My next 30 days"}
          >
            <:subtitle>Each column is a day; each dot is a DueItem whose action is due.</:subtitle>
            <:action>
              <.round_link
                navigate={~p"/due-items?status=due_soon"}
                label="View DueItems due soon"
              />
            </:action>
            <div class="flex items-end gap-6">
              <div class="shrink-0">
                <p class="text-[40px] font-medium leading-none tracking-[-0.04em] tabular-nums">
                  {Enum.sum_by(@timeline, & &1.count)}
                </p>
                <p class="mt-2 text-xs text-zinc-500">DueItems</p>
              </div>
              <div class="min-w-0 flex-1 overflow-x-auto">
                <div class="flex min-w-105 items-end justify-between gap-1">
                  <div
                    :for={{day, index} <- Enum.with_index(@timeline)}
                    class="flex flex-col items-center gap-1"
                    title={"#{date(day.date)}: #{day.count}"}
                  >
                    <span
                      :for={level <- (@dots_per_day - 1)..0//-1}
                      class={[
                        "size-1.5 rounded-full sm:size-2",
                        cond do
                          level < day.count -> "bg-navy"
                          index == 0 -> "bg-brand/30"
                          true -> "bg-[#ececea]"
                        end
                      ]}
                    />
                  </div>
                </div>
                <div class="mt-3 flex min-w-105 justify-between text-[11px] text-zinc-400">
                  <span class="font-medium text-brand">Today</span>
                  <span>{date(Date.add(@today, 15))}</span>
                  <span>{date(Date.add(@today, @timeline_days - 1))}</span>
                </div>
              </div>
            </div>
          </.card>

          <.card
            :for={list <- @lists}
            :if={list.items != []}
            id={"list-#{list.key}"}
            title={list.title}
          >
            <:action>
              <.round_link navigate={list.navigate} label={"View all #{list.title}"} />
            </:action>
            <ul class="-my-1">
              <.due_item_row
                :for={item <- list.items}
                id={"#{list.key}-#{item.id}"}
                item={item}
                status={item_status(item, @today, @due_soon_days)}
              />
            </ul>
          </.card>

          <.card
            :if={!@admin? and @recent != []}
            id="recently-updated"
            title="Recently updated"
          >
            <ul class="-my-1">
              <.due_item_row
                :for={item <- @recent}
                id={"recent-#{item.id}"}
                item={item}
                status={item_status(item, @today, @due_soon_days)}
              />
            </ul>
          </.card>

          <.card :if={@completed != []} id="recently-completed" title="Recently completed">
            <:subtitle>Renewed or completed in the last 30 days.</:subtitle>
            <ul class="-my-1 divide-y divide-line">
              <li :for={cycle <- @completed} id={"completed-#{cycle.id}"}>
                <.link
                  navigate={~p"/due-items/#{cycle.due_item}"}
                  class="group flex items-center gap-3 py-2.5 text-sm"
                >
                  <span class={[
                    "flex size-6 shrink-0 items-center justify-center rounded-full",
                    if(cycle.completion_type == "renewed",
                      do: "bg-emerald-50 text-emerald-600",
                      else: "bg-violet-50 text-violet-600"
                    )
                  ]}>
                    <.icon
                      name={
                        if cycle.completion_type == "renewed",
                          do: "hero-arrow-path-mini",
                          else: "hero-check-mini"
                      }
                      class="size-3.5"
                    />
                  </span>
                  <span class="min-w-0 flex-1 truncate text-ink group-hover:underline group-hover:underline-offset-2">
                    {cycle.due_item.title}
                  </span>
                  <span class="hidden shrink-0 truncate text-xs text-muted sm:block">
                    {if cycle.completion_type == "renewed", do: "Renewed", else: "Completed"} by {closed_by(
                      cycle
                    )}
                  </span>
                  <span class="w-24 shrink-0 text-right text-xs tabular-nums text-zinc-500">
                    {date(cycle.completed_on)}
                  </span>
                </.link>
              </li>
            </ul>
          </.card>

          <.card
            :if={!@has_items?}
            id="welcome"
            title={if @admin?, do: "Welcome to DueDesk", else: "No DueItems assigned to you yet"}
          >
            <:subtitle>
              <%= if @admin? do %>
                Add the renewals, licences, registrations and contracts your business must not
                miss. DueDesk reminds the right people before they become overdue.
              <% else %>
                DueItems you are responsible for will appear here. You can also add one yourself.
              <% end %>
            </:subtitle>
            <ol :if={@admin?} class="divide-y divide-line rounded-md border border-line">
              <.setup_step
                number={1}
                title="Add an Organisation"
                navigate={~p"/organisations"}
                done={@usage.organisations > 0}
              />
              <.setup_step
                number={2}
                title="Create a DueItem"
                navigate={~p"/due-items/new"}
                done={@has_items?}
              />
              <.setup_step number={3} title="Invite your team" navigate={~p"/users"} />
            </ol>
            <.button :if={!@admin?} navigate={~p"/due-items/new"}>
              <.icon name="hero-plus" class="size-4" /> Create DueItem
            </.button>
            <:footer>
              <.link
                navigate={~p"/support"}
                class="inline-flex items-center gap-1.5 font-medium text-violet-600 hover:text-violet-700"
              >
                <.icon name="hero-lifebuoy-mini" class="size-4" /> Get help setting up
              </.link>
            </:footer>
          </.card>
        </div>

        <div class="space-y-4">
          <.card :if={@admin?} id="admin-queues" title="Waiting for you">
            <:subtitle>Decisions only an Administrator can make.</:subtitle>
            <ul class="-my-1 divide-y divide-line">
              <li id="card-awaiting">
                <.link
                  navigate={~p"/due-items?view=awaiting"}
                  class="group flex items-center gap-3 py-2.5 text-sm"
                >
                  <.icon name="hero-inbox-arrow-down" class="size-4 shrink-0 text-violet-500" />
                  <span class="min-w-0 flex-1 truncate text-ink group-hover:underline group-hover:underline-offset-2">
                    Awaiting action
                  </span>
                  <span class={[
                    "shrink-0 rounded-full px-2 py-px text-xs font-medium tabular-nums",
                    if(@awaiting_count > 0,
                      do: "bg-violet-50 text-violet-700",
                      else: "bg-[#efefed] text-zinc-500"
                    )
                  ]}>
                    {@awaiting_count}
                  </span>
                </.link>
              </li>
              <li id="card-reviews">
                <.link
                  navigate={~p"/due-items?view=reviews"}
                  class="group flex items-center gap-3 py-2.5 text-sm"
                >
                  <.icon name="hero-eye" class="size-4 shrink-0 text-sky-600" />
                  <span class="min-w-0 flex-1 truncate text-ink group-hover:underline group-hover:underline-offset-2">
                    Renewal reviews
                  </span>
                  <span class={[
                    "shrink-0 rounded-full px-2 py-px text-xs font-medium tabular-nums",
                    if(@reviews_count > 0,
                      do: "bg-sky-50 text-sky-700",
                      else: "bg-[#efefed] text-zinc-500"
                    )
                  ]}>
                    {@reviews_count}
                  </span>
                </.link>
              </li>
            </ul>
          </.card>

          <.card :if={@admin? and @by_organisation != []} id="by-organisation" title="By Organisation">
            <:subtitle>Active DueItems, and how many need attention.</:subtitle>
            <ul class="-my-1 divide-y divide-line">
              <li :for={row <- Enum.take(@by_organisation, 6)} id={"by-organisation-#{row.id}"}>
                <.link
                  navigate={~p"/due-items?organisation_id=#{row.id}"}
                  class="group flex items-center gap-3 py-2.5 text-sm"
                >
                  <span class="min-w-0 flex-1 truncate text-ink group-hover:underline group-hover:underline-offset-2">
                    {row.name}
                  </span>
                  <span
                    :if={row.overdue > 0}
                    class="shrink-0 text-xs font-medium tabular-nums text-rose-600"
                    title="Overdue"
                  >
                    {row.overdue} overdue
                  </span>
                  <span
                    :if={row.due_soon > 0}
                    class="shrink-0 text-xs font-medium tabular-nums text-amber-600"
                    title="Due soon"
                  >
                    {row.due_soon} soon
                  </span>
                  <span class="w-8 shrink-0 text-right tabular-nums text-zinc-500">{row.total}</span>
                </.link>
              </li>
            </ul>
          </.card>

          <.card :if={@admin? and @by_user != []} id="by-person" title="By person">
            <:subtitle>Active DueItems per Primary Responsible.</:subtitle>
            <ul class="-my-1 divide-y divide-line">
              <li :for={row <- Enum.take(@by_user, 6)} id={"by-person-#{row.id}"}>
                <.link
                  navigate={~p"/due-items?primary_user_id=#{row.id}"}
                  class="group flex items-center gap-3 py-2.5 text-sm"
                >
                  <.avatar name={row.name} />
                  <span class="min-w-0 flex-1 truncate text-ink group-hover:underline group-hover:underline-offset-2">
                    {row.name}
                  </span>
                  <span
                    :if={row.overdue > 0}
                    class="shrink-0 text-xs font-medium tabular-nums text-rose-600"
                  >
                    {row.overdue} overdue
                  </span>
                  <span class="w-8 shrink-0 text-right tabular-nums text-zinc-500">{row.total}</span>
                </.link>
              </li>
            </ul>
          </.card>

          <.card :if={@super_admin?} id="capacity" title="Capacity">
            <:subtitle>Usage against your plan limits.</:subtitle>
            <:action>
              <span class="rounded-full border border-line px-2.5 py-0.5 text-xs font-medium text-zinc-600">
                {@plan.name} plan
              </span>
            </:action>
            <div class="space-y-5">
              <.meter
                label="Organisations"
                used={@usage.organisations}
                limit={@plan.max_organisations}
              />
              <.meter label="DueItems" used={@usage.due_items} limit={@plan.max_due_items} />
              <.meter label="Admins & Users" used={@usage.members} limit={@plan.max_members} />
              <.meter
                label="Storage"
                used={@usage.storage_bytes}
                limit={@plan.storage_bytes}
                display={"#{Plans.format_bytes(@usage.storage_bytes)} of #{Plans.format_bytes(@plan.storage_bytes)}"}
              />
            </div>
          </.card>

          <.card id="reminder-schedule" title="Reminder schedule">
            <:subtitle>Default reminders for every new DueItem.</:subtitle>
            <div class="relative">
              <span class="absolute bottom-2 left-1.75 top-2 w-px bg-line" />
              <ol class="space-y-4 pl-6">
                <li :for={{when_label, note} <- @reminder_schedule} class="relative">
                  <span class="absolute -left-6 top-1 flex size-3.75 items-center justify-center rounded-full bg-white ring-1 ring-zinc-300">
                    <span class="size-1.5 rounded-full bg-navy" />
                  </span>
                  <p class="text-sm font-medium text-ink">{when_label}</p>
                  <p class="text-xs text-muted">{note}</p>
                </li>
              </ol>
            </div>
          </.card>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp closed_by(%{completed_by_user: %{name: name}}), do: name
  defp closed_by(_cycle), do: "a former member"

  attr :number, :integer, required: true
  attr :title, :string, required: true
  attr :navigate, :string, required: true
  attr :done, :boolean, default: false

  defp setup_step(assigns) do
    ~H"""
    <li>
      <.link
        navigate={@navigate}
        class="group flex items-center gap-3 px-4 py-3 transition hover:bg-[#fafaf9]"
      >
        <span
          :if={@done}
          class="flex size-6 shrink-0 items-center justify-center rounded-full bg-emerald-500 text-white"
          aria-label="Done"
        >
          <.icon name="hero-check-mini" class="size-4" />
        </span>
        <span
          :if={!@done}
          class="flex size-6 shrink-0 items-center justify-center rounded-full bg-[#efefed] text-xs font-semibold text-zinc-600"
        >
          {@number}
        </span>
        <span class={[
          "min-w-0 flex-1 text-sm font-medium",
          if(@done, do: "text-zinc-400 line-through decoration-zinc-300", else: "text-ink")
        ]}>
          {@title}
        </span>
        <.icon
          name="hero-arrow-right-mini"
          class="size-4 text-zinc-400 transition group-hover:translate-x-0.5 group-hover:text-ink"
        />
      </.link>
    </li>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    today = Tenancy.today(scope)
    admin? = Permissions.admin?(scope)

    counts = DueItems.count_by_status(scope)
    usage = if admin?, do: Billing.usage(scope), else: %{organisations: 0, due_items: 0}

    has_items? =
      if admin?,
        do: usage.due_items > 0,
        else: counts.overdue + counts.due_soon + counts.up_to_date > 0

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:today, today)
     |> assign(:due_soon_days, scope.customer_account.due_soon_days)
     |> assign(:admin?, admin?)
     |> assign(:super_admin?, Permissions.super_admin?(scope))
     |> assign(:plan, Billing.plan(scope))
     |> assign(:usage, usage)
     |> assign(:counts, counts)
     |> assign(:has_items?, has_items?)
     |> assign(:lists, attention_lists(scope, counts, admin?))
     |> assign(:recent, if(admin?, do: [], else: DueItems.list_recently_updated(scope, 5)))
     |> assign(:completed, DueItems.list_recently_completed(scope, 5))
     |> assign(:awaiting_count, DueItems.count_awaiting(scope))
     |> assign(:reviews_count, DueItems.count_renewal_reviews(scope))
     |> assign(:by_organisation, DueItems.counts_by_organisation(scope))
     |> assign(:by_user, DueItems.counts_by_user(scope))
     |> assign(:timeline, DueItems.due_timeline(scope, @timeline_days))
     |> assign(:timeline_days, @timeline_days)
     |> assign(:dots_per_day, @dots_per_day)
     |> assign(:reminder_schedule, @reminder_schedule)}
  end

  @list_size 5

  # The top few Overdue, Due Soon and (for Administrators) Unassigned
  # DueItems. Lists with nothing in them are not queried.
  defp attention_lists(scope, counts, admin?) do
    [
      {:overdue, "Overdue", %{"status" => "overdue"}, counts.overdue > 0},
      {:due_soon, "Due Soon", %{"status" => "due_soon"}, counts.due_soon > 0},
      {:unassigned, "Unassigned", %{"assignment" => "unassigned"},
       admin? and counts.unassigned > 0}
    ]
    |> Enum.map(fn {key, title, params, wanted?} ->
      %{
        key: key,
        title: title,
        navigate: ~p"/due-items?#{params}",
        items:
          if(wanted?, do: DueItems.list_due_items(scope, params, limit: @list_size), else: [])
      }
    end)
  end

  defp first_name(name), do: name |> String.split() |> List.first()
end

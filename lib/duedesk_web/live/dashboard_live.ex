defmodule DueDeskWeb.DashboardLive do
  @moduledoc """
  The landing page after log in (UX spec §11–§14). Super Admins and
  Administrators see account-wide status; Users see only their own work.

  Counts are wired to real DueItems in Phase 2.
  """
  use DueDeskWeb, :live_view

  alias DueDesk.Permissions
  alias DueDesk.Billing.Plans

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:dashboard}>
      <.page_header title={"Hello, #{first_name(@current_scope.user.name)}"}>
        <:subtitle>Here is what needs attention today, {date(@today)}.</:subtitle>
        <:actions>
          <.link navigate={~p"/due-items/new"} class="btn btn-primary">
            <.icon name="hero-plus" class="size-4" /> Create DueItem
          </.link>
        </:actions>
      </.page_header>

      <div class="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
        <.summary_card
          id="card-overdue"
          label={if @admin?, do: "Overdue", else: "My Overdue"}
          count={@counts.overdue}
          status={:overdue}
          navigate={~p"/due-items?status=overdue"}
        />
        <.summary_card
          id="card-due-soon"
          label={if @admin?, do: "Due Soon", else: "My Due Soon"}
          count={@counts.due_soon}
          status={:due_soon}
          navigate={~p"/due-items?status=due_soon"}
        />
        <.summary_card
          :if={@admin?}
          id="card-unassigned"
          label="Unassigned"
          count={@counts.unassigned}
          status={:unassigned}
          navigate={~p"/due-items?assignment=unassigned"}
        />
        <.summary_card
          id="card-up-to-date"
          label={if @admin?, do: "Up to Date", else: "My Up to Date"}
          count={@counts.up_to_date}
          status={:up_to_date}
          navigate={~p"/due-items?status=up_to_date"}
        />
      </div>

      <div class="grid gap-6 lg:grid-cols-3">
        <div class="lg:col-span-2">
          <.empty_state
            id="welcome"
            icon="hero-sparkles"
            title={if @admin?, do: "Welcome to DueDesk", else: "No DueItems assigned to you yet"}
          >
            <%= if @admin? do %>
              Add the renewals, licences, registrations and contracts your business must not miss.
              DueDesk will remind the right people before they become overdue.
            <% else %>
              DueItems you are responsible for will appear here. You can also add one yourself.
            <% end %>
            <:action>
              <.link navigate={~p"/due-items/new"} class="btn btn-primary">
                <.icon name="hero-plus" class="size-4" /> Create DueItem
              </.link>
            </:action>
          </.empty_state>
        </div>

        <aside
          :if={@super_admin?}
          id="capacity"
          class="rounded-2xl bg-base-100 border border-base-300 p-5 h-fit"
        >
          <div class="flex items-center justify-between mb-4">
            <h2 class="font-semibold">Capacity</h2>
            <span class="text-xs font-medium rounded-full bg-primary/10 text-primary px-2 py-0.5">
              {@plan.name} plan
            </span>
          </div>
          <dl class="space-y-3 text-sm">
            <.capacity_row label="Organisations" used={0} limit={@plan.max_organisations} />
            <.capacity_row label="DueItems" used={0} limit={@plan.max_due_items} />
            <.capacity_row label="Admins & Users" used={0} limit={@plan.max_members} />
            <div class="flex justify-between">
              <dt class="text-base-content/70">Storage</dt>
              <dd class="tabular-nums">
                {Plans.format_bytes(@current_scope.customer_account.storage_used_bytes)} of {Plans.format_bytes(
                  @plan.storage_bytes
                )}
              </dd>
            </div>
          </dl>
        </aside>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :used, :integer, required: true
  attr :limit, :any, required: true

  defp capacity_row(assigns) do
    ~H"""
    <div class="flex justify-between">
      <dt class="text-base-content/70">{@label}</dt>
      <dd class="tabular-nums">
        {@used} of {if @limit == :unlimited, do: "Unlimited", else: @limit}
      </dd>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:today, DueDesk.Tenancy.today(scope))
     |> assign(:admin?, Permissions.admin?(scope))
     |> assign(:super_admin?, Permissions.super_admin?(scope))
     |> assign(:plan, Plans.get(scope.customer_account.plan_code))
     |> assign(:counts, %{overdue: 0, due_soon: 0, unassigned: 0, up_to_date: 0})}
  end

  defp first_name(name), do: name |> String.split() |> List.first()
end

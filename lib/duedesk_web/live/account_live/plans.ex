defmodule DueDeskWeb.AccountLive.Plans do
  @moduledoc """
  The plans and the account's usage against its current plan. Read-only
  until online upgrades arrive with billing.
  """
  use DueDeskWeb, :live_view

  on_mount {DueDeskWeb.UserAuth, :require_admin}

  alias DueDesk.Billing
  alias DueDesk.Billing.Plans

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:account}>
      <.page_header eyebrow="Account" icon="hero-sparkles" title="Plans">
        <:subtitle>
          Every plan includes the full product: reminders, documents, renewals and history.
          Plans differ only in capacity.
        </:subtitle>
      </.page_header>

      <.card id="plan-usage" title="Your usage" class="mb-6">
        <:subtitle>You are on the {@plan.name} plan.</:subtitle>
        <div class="grid gap-x-10 gap-y-5 sm:grid-cols-2">
          <.meter label="Organisations" used={@usage.organisations} limit={@plan.max_organisations} />
          <.meter label="DueItems" used={@usage.due_items} limit={@plan.max_due_items} />
          <.meter
            label="Admins & Users"
            used={@usage.members + @usage.invitations}
            limit={@plan.max_members}
          />
          <.meter
            label="Storage"
            used={@usage.storage_bytes}
            limit={@plan.storage_bytes}
            display={"#{Plans.format_bytes(@usage.storage_bytes)} of #{Plans.format_bytes(@plan.storage_bytes)}"}
          />
        </div>
      </.card>

      <div id="plans" class="grid gap-4 md:grid-cols-3">
        <section
          :for={plan <- @plans}
          id={"plan-#{plan.code}"}
          class={[
            "relative flex flex-col rounded-lg border bg-white p-5 transition",
            if(plan == @plan,
              do: "border-navy ring-1 ring-navy",
              else: "border-line hover:border-zinc-300"
            )
          ]}
        >
          <div class="flex items-center justify-between gap-2">
            <h2 class="text-[15px] font-semibold text-ink">{plan.name}</h2>
            <span
              :if={plan == @plan}
              id="current-plan"
              class="rounded-full bg-navy px-2.5 py-0.5 text-xs font-medium text-white"
            >
              Current plan
            </span>
          </div>
          <p class="mt-4 flex items-baseline gap-1">
            <span class="text-[32px] font-medium leading-none tracking-[-0.03em] text-ink tabular-nums">
              {inr(plan.monthly_inr)}
            </span>
            <span class="text-sm text-muted">/ month</span>
          </p>
          <p class="mt-1 text-xs text-muted">
            {if plan.annual_inr == 0,
              do: "Free forever",
              else: "or #{inr(plan.annual_inr)} / year"}
          </p>
          <ul class="mt-5 space-y-2.5 border-t border-line pt-5 text-sm text-zinc-700">
            <li :for={line <- limits(plan)} class="flex items-center gap-2">
              <.icon name="hero-check-mini" class="size-4 shrink-0 text-brand" /> {line}
            </li>
          </ul>
        </section>
      </div>

      <p class="mt-6 text-sm text-muted">
        Online upgrades are coming soon. To change your plan now, <.link
          navigate={~p"/support"}
          class="font-medium text-ink underline underline-offset-2 hover:text-brand"
        >
          contact support
        </.link>.
      </p>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     socket
     |> assign(:page_title, "Plans")
     |> assign(:plan, Billing.plan(scope))
     |> assign(:plans, Plans.all())
     |> assign(:usage, Billing.usage(scope))}
  end

  defp limits(plan) do
    [
      count(plan.max_organisations, "Organisation", "Organisations"),
      count(plan.max_due_items, "DueItem", "DueItems"),
      count(plan.max_members, "Admin or User", "Admins & Users"),
      count(plan.max_super_admins, "Super Admin", "Super Admins"),
      "#{Plans.format_bytes(plan.storage_bytes)} document storage"
    ]
  end

  defp count(:unlimited, _one, many), do: "Unlimited #{many}"
  defp count(1, one, _many), do: "1 #{one}"
  defp count(n, _one, many), do: "#{n} #{many}"
end

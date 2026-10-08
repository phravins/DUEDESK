defmodule DueDeskAdmin.AccountsLive do
  @moduledoc """
  Operator console: list of Customer Accounts. Read-only in Phase 0.
  """
  use DueDeskWeb, :live_view

  alias DueDesk.Admin
  alias DueDesk.Billing.Plans

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-white">
      <header class="sticky top-0 z-30 border-b border-line bg-white/90 backdrop-blur">
        <div class="mx-auto flex h-16 max-w-6xl items-center justify-between gap-4 px-4 sm:px-6">
          <div class="flex items-center gap-3">
            <Layouts.logo class="h-7" />
            <span class="rounded-full border border-line px-2.5 py-0.5 text-xs font-medium text-zinc-600">
              Operator
            </span>
          </div>
          <div class="flex items-center gap-3 text-sm">
            <span class="hidden text-muted sm:inline">{@current_operator.name}</span>
            <.button href={~p"/admin/log-out"} method="delete" variant="secondary" size="sm">
              <.icon name="hero-arrow-right-start-on-rectangle-mini" class="size-4" /> Log out
            </.button>
          </div>
        </div>
      </header>

      <main class="mx-auto max-w-6xl px-4 py-10 sm:px-6">
        <.page_header eyebrow="Operator" icon="hero-shield-check" title="Customer Accounts">
          <:subtitle>{length(@accounts)} shown</:subtitle>
          <:actions>
            <form
              id="account-search"
              phx-change="search"
              phx-submit="search"
              class="w-full sm:w-80"
            >
              <.input
                type="search"
                name="search"
                value={@search}
                icon="hero-magnifying-glass"
                placeholder="Search by account name"
                phx-debounce="300"
                messages={false}
              />
            </form>
          </:actions>
        </.page_header>

        <div class="overflow-hidden rounded-lg border border-line bg-white">
          <div class="overflow-x-auto">
            <table id="accounts" class="w-full text-left text-[13px]">
              <thead>
                <tr class="border-b border-line bg-[#fafaf9] text-[11px] font-semibold uppercase tracking-[0.06em] text-zinc-500">
                  <th class="px-5 py-2.5 font-semibold">Account</th>
                  <th class="px-5 py-2.5 font-semibold">Plan</th>
                  <th class="px-5 py-2.5 font-semibold">Status</th>
                  <th class="px-5 py-2.5 font-semibold">Members</th>
                  <th class="px-5 py-2.5 font-semibold">Organisations</th>
                  <th class="px-5 py-2.5 font-semibold">Storage</th>
                  <th class="px-5 py-2.5 font-semibold">Created</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-line">
                <tr
                  :for={%{account: a, member_count: n, organisation_count: orgs} <- @accounts}
                  id={"account-#{a.id}"}
                  class="transition hover:bg-[#fafaf9]"
                >
                  <td class="px-5 py-3 font-medium text-ink">{a.name}</td>
                  <td class="px-5 py-3">
                    <span class="rounded-full border border-line px-2 py-0.5 text-xs font-medium text-zinc-700">
                      {Plans.get(a.plan_code).name}
                    </span>
                  </td>
                  <td class="px-5 py-3 text-zinc-600">{String.capitalize(a.status)}</td>
                  <td class="px-5 py-3 tabular-nums text-zinc-600">{n}</td>
                  <td
                    id={"account-#{a.id}-organisations"}
                    class="px-5 py-3 tabular-nums text-zinc-600"
                  >
                    {orgs}
                  </td>
                  <td class="px-5 py-3 tabular-nums text-zinc-600">
                    {Plans.format_bytes(a.storage_used_bytes)}
                  </td>
                  <td class="px-5 py-3 text-zinc-500">{date(a.inserted_at)}</td>
                </tr>
                <tr :if={@accounts == []}>
                  <td colspan="7" class="px-6 py-14 text-center text-zinc-500">
                    No accounts found.
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </main>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Accounts")
     |> assign(:search, "")
     |> assign(:accounts, Admin.list_customer_accounts())}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    {:noreply,
     socket
     |> assign(:search, search)
     |> assign(:accounts, Admin.list_customer_accounts(search: search))}
  end
end

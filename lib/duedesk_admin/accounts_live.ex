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
    <div class="min-h-screen bg-base-200">
      <header class="bg-neutral text-neutral-content">
        <div class="mx-auto max-w-6xl px-4 sm:px-6 h-14 flex items-center justify-between">
          <p class="font-semibold">DueDesk Operator Console</p>
          <div class="flex items-center gap-4 text-sm">
            <span class="opacity-80">{@current_operator.name}</span>
            <.link href={~p"/admin/log-out"} method="delete" class="underline">Log out</.link>
          </div>
        </div>
      </header>
      <main class="mx-auto max-w-6xl px-4 sm:px-6 py-8">
        <.page_header title="Customer Accounts">
          <:subtitle>{length(@accounts)} shown</:subtitle>
        </.page_header>

        <form id="account-search" phx-change="search" phx-submit="search" class="mb-4 max-w-sm">
          <input
            type="search"
            name="search"
            value={@search}
            placeholder="Search by account name"
            phx-debounce="300"
            class="input w-full"
          />
        </form>

        <div class="overflow-x-auto rounded-2xl bg-base-100 border border-base-300">
          <table class="table" id="accounts">
            <thead>
              <tr>
                <th>Account</th>
                <th>Plan</th>
                <th>Status</th>
                <th>Members</th>
                <th>Storage</th>
                <th>Created</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={%{account: a, member_count: n} <- @accounts} id={"account-#{a.id}"}>
                <td class="font-medium">{a.name}</td>
                <td>{Plans.get(a.plan_code).name}</td>
                <td>{String.capitalize(a.status)}</td>
                <td>{n}</td>
                <td>{Plans.format_bytes(a.storage_used_bytes)}</td>
                <td>{date(a.inserted_at)}</td>
              </tr>
              <tr :if={@accounts == []}>
                <td colspan="6" class="text-center text-base-content/60 py-8">
                  No accounts found.
                </td>
              </tr>
            </tbody>
          </table>
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

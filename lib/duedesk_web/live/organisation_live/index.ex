defmodule DueDeskWeb.OrganisationLive.Index do
  @moduledoc """
  The account's Organisations (UX spec §25), with Active and Archived tabs.
  Administrators and Super Admins only.
  """
  use DueDeskWeb, :live_view

  on_mount {DueDeskWeb.UserAuth, :require_admin}

  alias DueDesk.{Billing, Organisations, Permissions}
  alias DueDesk.Organisations.Identifier

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:organisations}>
      <.page_header eyebrow="Account" icon="hero-building-office-2" title="Organisations">
        <:subtitle>
          The businesses whose renewals and obligations you track. Archived Organisations keep
          their history and do not count toward your plan.
        </:subtitle>
        <:actions>
          <.button :if={!@limit_message} id="add-organisation" navigate={~p"/organisations/new"}>
            <.icon name="hero-plus" class="size-4" /> Add Organisation
          </.button>
        </:actions>
      </.page_header>

      <.limit_notice :if={@limit_message} message={@limit_message} plans_link={@plans_link?} />

      <.tabs id="organisation-tabs">
        <:tab
          id="tab-active"
          patch={~p"/organisations"}
          active={@status == "active"}
          count={@counts.active}
        >
          Active
        </:tab>
        <:tab
          id="tab-archived"
          patch={~p"/organisations?status=archived"}
          active={@status == "archived"}
          count={@counts.archived}
        >
          Archived
        </:tab>
      </.tabs>

      <.empty_state
        :if={@empty?}
        id="organisations-empty"
        icon="hero-building-office-2"
        title={if @status == "active", do: "No Organisations yet", else: "No archived Organisations"}
      >
        <%= if @status == "active" do %>
          Add the businesses you manage. Each DueItem belongs to one Organisation.
        <% else %>
          Organisations you archive appear here and can be restored later.
        <% end %>
        <:action :if={@status == "active" and !@limit_message}>
          <.button navigate={~p"/organisations/new"}>
            <.icon name="hero-plus" class="size-4" /> Add Organisation
          </.button>
        </:action>
      </.empty_state>

      <div :if={!@empty?} class="overflow-x-auto rounded-lg border border-line bg-white">
        <table class="w-full min-w-[720px] text-left text-sm">
          <thead class="border-b border-line bg-[#fafaf9] text-xs font-medium text-zinc-500">
            <tr>
              <th class="px-4 py-3 font-medium">Name</th>
              <th class="px-4 py-3 font-medium">Type</th>
              <th class="px-4 py-3 font-medium">Identifier</th>
              <th class="px-4 py-3 font-medium">GSTIN</th>
              <th class="px-4 py-3 text-right font-medium">Active DueItems</th>
            </tr>
          </thead>
          <tbody id="organisations" phx-update="stream" class="divide-y divide-line">
            <tr
              :for={{dom_id, organisation} <- @streams.organisations}
              id={dom_id}
              class="group cursor-pointer transition hover:bg-[#fafaf9]"
              phx-click={JS.navigate(~p"/organisations/#{organisation}")}
            >
              <td class="px-4 py-3.5">
                <.link
                  navigate={~p"/organisations/#{organisation}"}
                  class="font-medium text-ink group-hover:underline group-hover:underline-offset-2"
                >
                  {organisation.name}
                </.link>
              </td>
              <td class="px-4 py-3.5 text-zinc-600">{Identifier.type_label(organisation.type)}</td>
              <td class="px-4 py-3.5">
                <span class="text-xs text-zinc-400">
                  {Identifier.short_label(organisation.identifier_type)}
                </span>
                <span class="ml-1 font-mono text-[13px] text-zinc-700">
                  {organisation.identifier}
                </span>
              </td>
              <td class="px-4 py-3.5 font-mono text-[13px] text-zinc-600">
                {organisation.gstin || "—"}
              </td>
              <td class="px-4 py-3.5 text-right tabular-nums text-zinc-600">0</td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {limit_message, plans_link?} =
      case Billing.check(scope, :organisation) do
        :ok ->
          {nil, false}

        {:error, {:limit_reached, info}} ->
          {Billing.limit_message(scope, info), Permissions.can_manage_billing?(scope)}
      end

    {:ok,
     socket
     |> assign(:page_title, "Organisations")
     |> assign(:limit_message, limit_message)
     |> assign(:plans_link?, plans_link?)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    scope = socket.assigns.current_scope
    status = if params["status"] == "archived", do: "archived", else: "active"
    organisations = Organisations.list_organisations(scope, status: status)

    {:noreply,
     socket
     |> assign(:status, status)
     |> assign(:counts, Organisations.count_by_status(scope))
     |> assign(:empty?, organisations == [])
     |> stream(:organisations, organisations, reset: true)}
  end
end

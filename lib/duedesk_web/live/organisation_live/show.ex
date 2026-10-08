defmodule DueDeskWeb.OrganisationLive.Show do
  @moduledoc """
  An Organisation's details, its latest declaration and (from Phase 2) its
  DueItems. Archive and restore live here.
  """
  use DueDeskWeb, :live_view

  on_mount {DueDeskWeb.UserAuth, :require_admin}

  alias DueDesk.{Billing, Organisations, Permissions}
  alias DueDesk.Organisations.Identifier

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:organisations}>
      <.page_header eyebrow="Organisations" icon="hero-building-office-2" title={@organisation.name}>
        <:actions>
          <%= if @organisation.status == "active" do %>
            <.button
              id="archive-organisation"
              variant="outline"
              phx-click="archive"
              data-confirm="Archive this Organisation? Its DueItems and documents are kept, and it stops counting toward your plan."
            >
              <.icon name="hero-archive-box" class="size-4" /> Archive
            </.button>
            <.button id="edit-organisation" navigate={~p"/organisations/#{@organisation}/edit"}>
              <.icon name="hero-pencil-square" class="size-4" /> Edit
            </.button>
          <% else %>
            <.button
              id="restore-organisation"
              phx-click="restore"
              data-confirm="Restore this Organisation? It will count toward your plan again."
            >
              <.icon name="hero-arrow-uturn-left" class="size-4" /> Restore
            </.button>
          <% end %>
        </:actions>
      </.page_header>

      <.limit_notice :if={@limit_message} message={@limit_message} plans_link={@plans_link?} />

      <div class="grid gap-4 lg:grid-cols-3">
        <div class="space-y-4 lg:col-span-2">
          <.card id="organisation-details" title="Details">
            <:action>
              <%= if @organisation.status == "archived" do %>
                <.status_badge status={:archived} />
              <% else %>
                <span class="inline-flex items-center gap-1.5 rounded-full bg-emerald-50 px-2 py-0.5 text-xs font-medium text-emerald-700 ring-1 ring-inset ring-emerald-200/70">
                  <.icon name="hero-check-circle-mini" class="size-3.5" /> Active
                </span>
              <% end %>
            </:action>
            <dl class="-my-3 divide-y divide-line">
              <.detail label="Type">{Identifier.type_label(@organisation.type)}</.detail>
              <.detail
                id="organisation-identifier"
                label={Identifier.label(@organisation.identifier_type)}
              >
                <span class="font-mono text-[13px]">{@organisation.identifier}</span>
              </.detail>
              <.detail label="GSTIN">
                <span class="font-mono text-[13px]">{@organisation.gstin || "—"}</span>
              </.detail>
              <.detail label="Added">
                {datetime(@organisation.inserted_at, @tz)}{if @organisation.created_by_user,
                  do: " by #{@organisation.created_by_user.name}"}
              </.detail>
              <.detail :if={@organisation.archived_at} label="Archived">
                {datetime(@organisation.archived_at, @tz)}
              </.detail>
            </dl>
          </.card>

          <.empty_state
            id="organisation-due-items"
            icon="hero-clipboard-document-list"
            title="No DueItems yet"
          >
            Renewals, licences and filings for {@organisation.name} will be listed here.
          </.empty_state>
        </div>

        <.card id="organisation-declaration" title="Declaration">
          <:subtitle>Confirms the person who added it may manage it.</:subtitle>
          <%= if @declaration do %>
            <dl class="space-y-3 text-sm">
              <div>
                <dt class="text-xs text-muted">Accepted by</dt>
                <dd class="text-ink">{(@declaration.user && @declaration.user.name) || "—"}</dd>
              </div>
              <div>
                <dt class="text-xs text-muted">On</dt>
                <dd class="text-ink">{datetime(@declaration.accepted_at, @tz)}</dd>
              </div>
              <div>
                <dt class="text-xs text-muted">Version</dt>
                <dd class="font-mono text-[13px] text-ink">{@declaration.version}</dd>
              </div>
            </dl>
          <% else %>
            <p class="text-sm text-muted">No declaration recorded.</p>
          <% end %>
        </.card>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    organisation = Organisations.get_organisation!(scope, id)

    {:ok,
     socket
     |> assign(:page_title, organisation.name)
     |> assign(:tz, scope.customer_account.timezone)
     |> assign(:limit_message, nil)
     |> assign(:plans_link?, false)
     |> assign_organisation(organisation)}
  end

  @impl true
  def handle_event("archive", _params, socket) do
    %{current_scope: scope, organisation: organisation} = socket.assigns

    case Organisations.archive_organisation(scope, organisation) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Organisation archived.")
         |> assign_organisation(Organisations.get_organisation!(scope, organisation.id))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "This Organisation could not be archived.")}
    end
  end

  def handle_event("restore", _params, socket) do
    %{current_scope: scope, organisation: organisation} = socket.assigns

    case Organisations.restore_organisation(scope, organisation) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Organisation restored.")
         |> assign(:limit_message, nil)
         |> assign_organisation(Organisations.get_organisation!(scope, organisation.id))}

      {:error, {:limit_reached, info}} ->
        {:noreply,
         socket
         |> assign(:limit_message, Billing.limit_message(scope, info))
         |> assign(:plans_link?, Permissions.can_manage_billing?(scope))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "This Organisation could not be restored.")}
    end
  end

  defp assign_organisation(socket, organisation) do
    socket
    |> assign(:organisation, organisation)
    |> assign(
      :declaration,
      Organisations.latest_declaration(socket.assigns.current_scope, organisation)
    )
  end
end

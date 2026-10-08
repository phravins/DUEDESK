defmodule DueDeskWeb.OrganisationLive.Form do
  @moduledoc """
  Add or edit an Organisation (UX spec §26). Changing the type or the
  identifier needs the declaration again.
  """
  use DueDeskWeb, :live_view

  on_mount {DueDeskWeb.UserAuth, :require_admin}

  import DueDeskWeb.OrganisationComponents

  alias DueDesk.{Billing, Organisations, Permissions}
  alias DueDesk.Organisations.Organisation

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:organisations}>
      <.page_header eyebrow="Organisations" icon="hero-building-office-2" title={@page_title} />

      <div class="max-w-2xl">
        <.limit_notice :if={@limit_message} message={@limit_message} plans_link={@plans_link?} />

        <.card :if={!@limit_message} id="organisation-card">
          <.organisation_form form={@form} id="organisation-form" declaration={@declaration?}>
            <:actions>
              <div class="flex flex-wrap items-center gap-2">
                <.button id="save-organisation" phx-disable-with="Saving...">
                  {if @live_action == :new, do: "Add Organisation", else: "Save changes"}
                </.button>
                <.button variant="ghost" navigate={@return_to}>Cancel</.button>
              </div>
            </:actions>
          </.organisation_form>
        </.card>

        <.button :if={@limit_message} variant="secondary" navigate={~p"/organisations"}>
          <.icon name="hero-arrow-left-mini" class="size-4" /> Back to Organisations
        </.button>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:declaration_meta, declaration_meta(socket))
     |> assign(:limit_message, nil)
     |> assign(:plans_link?, false)
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    scope = socket.assigns.current_scope

    socket =
      socket
      |> assign(:page_title, "Add Organisation")
      |> assign(:organisation, %Organisation{})
      |> assign(:return_to, ~p"/organisations")
      |> assign_form(Organisations.change_organisation(%Organisation{}))

    case Billing.check(scope, :organisation) do
      :ok -> socket
      {:error, {:limit_reached, info}} -> assign_limit(socket, info)
    end
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    organisation = Organisations.get_organisation!(socket.assigns.current_scope, id)

    socket
    |> assign(:page_title, "Edit #{organisation.name}")
    |> assign(:organisation, organisation)
    |> assign(:return_to, ~p"/organisations/#{organisation}")
    |> assign_form(Organisations.change_organisation(organisation))
  end

  @impl true
  def handle_event("validate", %{"organisation" => params}, socket) do
    changeset = Organisations.change_organisation(socket.assigns.organisation, params)
    {:noreply, assign_form(socket, %{changeset | action: :validate})}
  end

  def handle_event("save", %{"organisation" => params}, socket) do
    save(socket, socket.assigns.live_action, params)
  end

  defp save(socket, :new, params) do
    %{current_scope: scope, declaration_meta: meta} = socket.assigns

    scope
    |> Organisations.create_organisation(params, meta)
    |> handle_result(socket, "Organisation added.")
  end

  defp save(socket, :edit, params) do
    %{current_scope: scope, declaration_meta: meta, organisation: organisation} = socket.assigns

    scope
    |> Organisations.update_organisation(organisation, params, meta)
    |> handle_result(socket, "Organisation updated.")
  end

  defp handle_result({:ok, organisation}, socket, message) do
    {:noreply,
     socket
     |> put_flash(:info, message)
     |> push_navigate(to: ~p"/organisations/#{organisation}")}
  end

  defp handle_result({:error, %Ecto.Changeset{} = changeset}, socket, _message) do
    {:noreply, assign_form(socket, changeset)}
  end

  defp handle_result({:error, {:limit_reached, info}}, socket, _message) do
    {:noreply, assign_limit(socket, info)}
  end

  defp handle_result({:error, :unauthorized}, socket, _message) do
    {:noreply,
     socket
     |> put_flash(:error, "This page is not available to your account access.")
     |> push_navigate(to: ~p"/dashboard")}
  end

  defp assign_form(socket, changeset) do
    socket
    |> assign(:form, to_form(changeset))
    |> assign(:declaration?, Organisation.declaration_required?(changeset))
  end

  defp assign_limit(socket, info) do
    scope = socket.assigns.current_scope

    socket
    |> assign(:limit_message, Billing.limit_message(scope, info))
    |> assign(:plans_link?, Permissions.can_manage_billing?(scope))
  end
end

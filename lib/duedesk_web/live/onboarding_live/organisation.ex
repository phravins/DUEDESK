defmodule DueDeskWeb.OnboardingLive.Organisation do
  @moduledoc """
  Onboarding step 4 (UX spec §9): add the first Organisation. It can be
  skipped; accounts that already have an Organisation, and members who
  cannot add one, go straight to the dashboard.
  """
  use DueDeskWeb, :live_view

  import DueDeskWeb.OrganisationComponents

  alias DueDesk.{Organisations, Permissions}
  alias DueDesk.Organisations.Organisation

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash} current_scope={@current_scope} wide>
      <.onboarding_steps current={4} />

      <.auth_heading title="Add your first Organisation" tagline="The business you track.">
        DueItems belong to an Organisation, such as your proprietorship, firm, LLP or company.
        You can add more later.
      </.auth_heading>

      <.organisation_form form={@form} id="onboarding_organisation_form">
        <:actions>
          <.button size="lg" class="w-full" phx-disable-with="Adding...">
            Add Organisation
          </.button>
          <p class="mt-4 text-center text-sm">
            <.link
              id="skip-organisation"
              navigate={~p"/dashboard"}
              class="font-medium text-zinc-500 transition hover:text-ink"
            >
              I'll do this later
            </.link>
          </p>
        </:actions>
      </.organisation_form>
    </Layouts.auth>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    counts =
      if Permissions.can_manage_organisations?(scope), do: Organisations.count_by_status(scope)

    if counts && counts.active + counts.archived == 0 do
      {:ok,
       socket
       |> assign(:page_title, "Add your first Organisation")
       |> assign(:declaration_meta, declaration_meta(socket))
       |> assign_form(Organisations.change_organisation(%Organisation{}))}
    else
      {:ok, push_navigate(socket, to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_event("validate", %{"organisation" => params}, socket) do
    changeset = Organisations.change_organisation(%Organisation{}, params)
    {:noreply, assign_form(socket, %{changeset | action: :validate})}
  end

  def handle_event("save", %{"organisation" => params}, socket) do
    %{current_scope: scope, declaration_meta: meta} = socket.assigns

    case Organisations.create_organisation(scope, params, meta) do
      {:ok, _organisation} ->
        {:noreply,
         socket
         |> put_flash(:info, "Organisation added. Next, create your first DueItem.")
         |> push_navigate(to: ~p"/dashboard")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "This Organisation could not be added.")
         |> push_navigate(to: ~p"/dashboard")}
    end
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))
end

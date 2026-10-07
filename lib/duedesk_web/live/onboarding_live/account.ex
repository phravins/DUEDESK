defmodule DueDeskWeb.OnboardingLive.Account do
  @moduledoc """
  Onboarding step 3 (UX spec §8): set up the Customer Account. The person
  completing this becomes its Super Admin.
  """
  use DueDeskWeb, :live_view

  alias DueDesk.Tenancy

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash} current_scope={@current_scope} wide>
      <ol
        class="flex items-center gap-2 text-xs font-medium text-base-content/60 mb-6"
        aria-label="Setup progress"
      >
        <li class="flex items-center gap-1 text-success">
          <.icon name="hero-check-circle-mini" class="size-4" /> Sign up
        </li>
        <li aria-hidden="true">›</li>
        <li class="flex items-center gap-1 text-success">
          <.icon name="hero-check-circle-mini" class="size-4" /> Verify email
        </li>
        <li aria-hidden="true">›</li>
        <li class="text-primary" aria-current="step">Account setup</li>
        <li aria-hidden="true">›</li>
        <li>First Organisation</li>
      </ol>

      <h1 class="text-2xl font-semibold tracking-tight">Set up your DueDesk account</h1>
      <p class="mt-1 mb-6 text-sm text-base-content/70">
        Your account holds your Organisations, DueItems, documents and team.
        You will be its Super Admin.
      </p>

      <.form for={@form} id="account_setup_form" phx-change="validate" phx-submit="save">
        <.input
          field={@form[:name]}
          type="text"
          label="Account name"
          placeholder="e.g. Sharma Group"
          required
          phx-mounted={JS.focus()}
        />
        <.input
          field={@form[:notification_mobile]}
          type="tel"
          label="Mobile number for reminders"
          required
        />
        <div class="rounded-xl bg-base-200 p-4 mb-6 text-sm">
          <.input
            field={@form[:whatsapp_consent]}
            type="checkbox"
            label="Send me DueDesk reminders on WhatsApp"
          />
          <p class="text-xs text-base-content/60 -mt-1">
            Optional. Reminders always go by email; you can change this later in Account settings.
          </p>
        </div>
        <.button phx-disable-with="Setting up..." class="btn btn-primary w-full">
          Continue
        </.button>
      </.form>
    </Layouts.auth>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    changeset =
      Tenancy.change_account_setup(%{"notification_mobile" => user.mobile_number})

    {:ok,
     assign(socket, page_title: "Set up your account", form: to_form(changeset, as: "account"))}
  end

  @impl true
  def handle_event("validate", %{"account" => params}, socket) do
    changeset = Tenancy.change_account_setup(params)
    {:noreply, assign(socket, form: to_form(changeset, as: "account", action: :validate))}
  end

  def handle_event("save", %{"account" => params}, socket) do
    case Tenancy.create_customer_account(socket.assigns.current_scope, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Your DueDesk account is ready.")
         |> redirect(to: ~p"/dashboard")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "account"))}
    end
  end
end

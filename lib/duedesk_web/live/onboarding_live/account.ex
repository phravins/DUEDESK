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
      <ol class="mb-10 flex items-center gap-2 text-xs font-medium" aria-label="Setup progress">
        <.step state={:done}>Sign up</.step>
        <.step state={:done}>Verify email</.step>
        <.step state={:current}>Account</.step>
        <.step state={:next}>First Organisation</.step>
      </ol>

      <.auth_heading title="Set up your DueDesk account" tagline="You'll be its Super Admin.">
        Your account holds your Organisations, DueItems, documents and team.
      </.auth_heading>

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
        <div class="mb-6 rounded-md border border-line p-3.5 *:mb-0">
          <.input
            field={@form[:whatsapp_consent]}
            type="checkbox"
            label="Send me DueDesk reminders on WhatsApp"
          />
          <p class="mt-1 pl-6.5 text-xs text-muted">
            Optional. Reminders always go by email; you can change this later in Account settings.
          </p>
        </div>
        <.button size="lg" class="w-full" phx-disable-with="Setting up...">
          Continue
        </.button>
      </.form>
    </Layouts.auth>
    """
  end

  attr :state, :atom, required: true, values: [:done, :current, :next]
  slot :inner_block, required: true

  defp step(assigns) do
    ~H"""
    <li class="flex min-w-0 flex-1 flex-col gap-2" aria-current={@state == :current && "step"}>
      <span class={[
        "h-1 rounded-full",
        if(@state == :next, do: "bg-[#ececea]", else: "bg-navy")
      ]} />
      <span class={["truncate", if(@state == :next, do: "text-zinc-400", else: "text-ink")]}>
        {render_slot(@inner_block)}
      </span>
    </li>
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

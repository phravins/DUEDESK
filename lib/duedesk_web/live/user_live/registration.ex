defmodule DueDeskWeb.UserLive.Registration do
  use DueDeskWeb, :live_view

  alias DueDesk.Accounts
  alias DueDesk.Accounts.User

  @impl true
  def render(%{registered_email: email} = assigns) when is_binary(email) do
    ~H"""
    <Layouts.auth flash={@flash} current_scope={@current_scope}>
      <div id="check-email">
        <.auth_heading title="Check your email." tagline="One more step.">
          We have sent a confirmation link to <span class="font-medium text-ink">{@registered_email}</span>.
          Open it to verify your email address, then log in to set up your account.
        </.auth_heading>

        <.button navigate={~p"/users/log-in"} size="lg" class="w-full">
          Go to log in
        </.button>

        <p class="mt-8 text-xs leading-relaxed text-zinc-400">
          No email after a few minutes? Check your spam folder, or log in and we will send a
          new link.
        </p>
      </div>
    </Layouts.auth>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash} current_scope={@current_scope}>
      <:header_action>
        Already have an account?
        <.link navigate={~p"/users/log-in"} class="font-medium text-brand hover:underline">
          Log in
        </.link>
      </:header_action>

      <.auth_heading title="Never miss a renewal." tagline="Create your DueDesk account." />

      <.form for={@form} id="registration_form" phx-submit="save" phx-change="validate">
        <.input
          field={@form[:name]}
          type="text"
          label="Full name"
          placeholder="Asha Sharma"
          autocomplete="name"
          required
          phx-mounted={JS.focus()}
        />
        <.input
          field={@form[:email]}
          type="email"
          label="Work email"
          placeholder="name@company.in"
          autocomplete="username"
          spellcheck="false"
          required
        />
        <.input
          field={@form[:mobile_number]}
          type="tel"
          label="Mobile number"
          placeholder="98765 43210"
          autocomplete="tel"
          required
        />
        <.input
          field={@form[:password]}
          type="password"
          label="Password"
          placeholder="At least 10 characters"
          autocomplete="new-password"
          required
        />

        <.button size="lg" class="mt-2 w-full" phx-disable-with="Creating account...">
          Create account
        </.button>
      </.form>

      <.legal_consent action="By creating an account" />
    </Layouts.auth>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: DueDeskWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_registration(%User{}, %{}, validate_unique: false)

    {:ok,
     socket
     |> assign(page_title: "Create account", registered_email: nil)
     |> assign_form(changeset), temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_user_confirmation_instructions(
            user,
            &url(~p"/users/confirm/#{&1}")
          )

        {:noreply, assign(socket, page_title: "Check your email", registered_email: user.email)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset =
      Accounts.change_user_registration(%User{}, user_params,
        validate_unique: false,
        hash_password: false
      )

    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, form: to_form(changeset, as: "user"))
  end
end

defmodule DueDeskWeb.UserLive.Registration do
  use DueDeskWeb, :live_view

  alias DueDesk.Accounts
  alias DueDesk.Accounts.User

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash} current_scope={@current_scope}>
      <div class="mb-6">
        <h1 class="text-2xl font-semibold tracking-tight">Create your DueDesk account</h1>
        <p class="mt-1 text-sm text-base-content/70">
          Already registered?
          <.link navigate={~p"/users/log-in"} class="font-medium text-primary hover:underline">
            Log in
          </.link>
        </p>
      </div>

      <.form for={@form} id="registration_form" phx-submit="save" phx-change="validate">
        <.input
          field={@form[:name]}
          type="text"
          label="Your name"
          autocomplete="name"
          required
          phx-mounted={JS.focus()}
        />
        <.input
          field={@form[:email]}
          type="email"
          label="Email"
          autocomplete="username"
          spellcheck="false"
          required
        />
        <.input
          field={@form[:mobile_number]}
          type="tel"
          label="Mobile number"
          autocomplete="tel"
          placeholder="98765 43210"
          required
        />
        <.input
          field={@form[:password]}
          type="password"
          label="Password"
          autocomplete="new-password"
          required
        />
        <p class="-mt-1 mb-4 text-xs text-base-content/60">At least 10 characters.</p>

        <.button phx-disable-with="Creating account..." class="btn btn-primary w-full">
          Create account
        </.button>
      </.form>
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

    {:ok, socket |> assign(:page_title, "Create account") |> assign_form(changeset),
     temporary_assigns: [form: nil]}
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

        {:noreply,
         socket
         |> put_flash(
           :info,
           "Account created. We have sent a confirmation link to #{user.email} — open it to continue."
         )
         |> push_navigate(to: ~p"/users/log-in")}

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
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end

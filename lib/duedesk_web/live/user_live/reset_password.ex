defmodule DueDeskWeb.UserLive.ResetPassword do
  use DueDeskWeb, :live_view

  alias DueDesk.Accounts
  alias DueDeskWeb.UserAuth

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash} current_scope={@current_scope}>
      <div class="mb-6">
        <h1 class="text-2xl font-semibold tracking-tight">Choose a new password</h1>
        <p class="mt-1 text-sm text-base-content/70">
          For {@user.email}. You will be logged out of every device.
        </p>
      </div>

      <.form
        for={@form}
        id="new_password_form"
        phx-submit="reset_password"
        phx-change="validate"
      >
        <.input
          field={@form[:password]}
          type="password"
          label="New password"
          autocomplete="new-password"
          required
          phx-mounted={JS.focus()}
        />
        <.input
          field={@form[:password_confirmation]}
          type="password"
          label="Confirm new password"
          autocomplete="new-password"
          required
        />
        <.button phx-disable-with="Saving..." class="btn btn-primary w-full">
          Save new password
        </.button>
      </.form>
    </Layouts.auth>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if user = Accounts.get_user_by_reset_password_token(token) do
      form = to_form(Accounts.change_user_password(user, %{}, hash_password: false), as: "user")

      {:ok, assign(socket, page_title: "Reset password", user: user, form: form),
       temporary_assigns: [form: nil]}
    else
      {:ok,
       socket
       |> put_flash(
         :error,
         "This reset link is invalid or has expired. Please request a new one."
       )
       |> push_navigate(to: ~p"/users/reset-password")}
    end
  end

  @impl true
  def handle_event("reset_password", %{"user" => user_params}, socket) do
    case Accounts.reset_user_password(socket.assigns.user, user_params) do
      {:ok, {_user, expired_tokens}} ->
        UserAuth.disconnect_sessions(expired_tokens)

        {:noreply,
         socket
         |> put_flash(:info, "Password reset. Log in with your new password.")
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "user"))}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset =
      Accounts.change_user_password(socket.assigns.user, user_params, hash_password: false)

    {:noreply, assign(socket, form: to_form(changeset, as: "user", action: :validate))}
  end
end

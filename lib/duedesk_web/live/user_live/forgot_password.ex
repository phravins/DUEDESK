defmodule DueDeskWeb.UserLive.ForgotPassword do
  use DueDeskWeb, :live_view

  alias DueDesk.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash} current_scope={@current_scope}>
      <div class="mb-6">
        <h1 class="text-2xl font-semibold tracking-tight">Reset your password</h1>
        <p class="mt-1 text-sm text-base-content/70">
          Enter your email and we'll send you a link to choose a new password.
        </p>
      </div>

      <.form for={@form} id="reset_password_form" phx-submit="send_email">
        <.input
          field={@form[:email]}
          type="email"
          label="Email"
          autocomplete="username"
          required
          phx-mounted={JS.focus()}
        />
        <.button phx-disable-with="Sending..." class="btn btn-primary w-full">
          Send reset link
        </.button>
      </.form>

      <p class="mt-6 text-center text-sm">
        <.link navigate={~p"/users/log-in"} class="text-primary hover:underline">
          Back to log in
        </.link>
      </p>
    </Layouts.auth>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Forgot password", form: to_form(%{}, as: "user"))}
  end

  @impl true
  def handle_event("send_email", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(
        user,
        &url(~p"/users/reset-password/#{&1}")
      )
    end

    info =
      "If that email is registered, you will receive password reset instructions shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/users/log-in")}
  end
end

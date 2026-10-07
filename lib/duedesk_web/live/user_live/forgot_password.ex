defmodule DueDeskWeb.UserLive.ForgotPassword do
  use DueDeskWeb, :live_view

  alias DueDesk.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash} current_scope={@current_scope}>
      <:header_action>
        Remembered it?
        <.link navigate={~p"/users/log-in"} class="font-medium text-brand hover:underline">
          Log in
        </.link>
      </:header_action>

      <.auth_heading title="Forgot your password?" tagline="We'll email you a link.">
        Enter the email you use for DueDesk and we will send you a link to choose a new one.
      </.auth_heading>

      <.form for={@form} id="reset_password_form" phx-submit="send_email">
        <.input
          field={@form[:email]}
          type="email"
          label="Email"
          placeholder="name@company.in"
          autocomplete="username"
          required
          phx-mounted={JS.focus()}
        />
        <.button size="lg" class="mt-2 w-full" phx-disable-with="Sending...">
          Send reset link
        </.button>
      </.form>

      <.button navigate={~p"/users/log-in"} variant="outline" size="lg" class="mt-3 w-full">
        Back to log in
      </.button>
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

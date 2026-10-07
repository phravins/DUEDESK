defmodule DueDeskWeb.UserLive.Login do
  use DueDeskWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash} current_scope={@current_scope}>
      <div class="mb-6">
        <h1 class="text-2xl font-semibold tracking-tight">
          {if @current_scope, do: "Confirm it's you", else: "Log in to DueDesk"}
        </h1>
        <p class="mt-1 text-sm text-base-content/70">
          <%= if @current_scope do %>
            Enter your password again to continue with this sensitive action.
          <% else %>
            New to DueDesk?
            <.link navigate={~p"/users/register"} class="font-medium text-primary hover:underline">
              Create an account
            </.link>
          <% end %>
        </p>
      </div>

      <div :if={local_mail_adapter?()} class="alert alert-info mb-4 text-sm">
        <.icon name="hero-information-circle" class="size-5 shrink-0" />
        <p>
          Development mode: emails appear in <.link href="/dev/mailbox" class="underline">the local mailbox</.link>.
        </p>
      </div>

      <.form
        :let={f}
        for={@form}
        id="login_form"
        action={~p"/users/log-in"}
        phx-submit="submit"
        phx-trigger-action={@trigger_submit}
      >
        <.input
          readonly={!!@current_scope}
          field={f[:email]}
          type="email"
          label="Email"
          autocomplete="username"
          spellcheck="false"
          required
          phx-mounted={!@current_scope && JS.focus()}
        />
        <.input
          field={@form[:password]}
          type="password"
          label="Password"
          autocomplete="current-password"
          required
          phx-mounted={@current_scope && JS.focus()}
        />
        <div class="flex items-center justify-between mb-4 text-sm">
          <label :if={!@current_scope} class="flex items-center gap-2">
            <input
              type="checkbox"
              name={@form[:remember_me].name}
              value="true"
              class="checkbox checkbox-sm"
            /> Keep me logged in
          </label>
          <.link
            navigate={~p"/users/reset-password"}
            class="text-primary hover:underline ml-auto"
          >
            Forgot password?
          </.link>
        </div>
        <.button class="btn btn-primary w-full" phx-disable-with="Logging in...">
          Log in
        </.button>
      </.form>
    </Layouts.auth>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, page_title: "Log in", form: form, trigger_submit: false)}
  end

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end

  defp local_mail_adapter? do
    Application.get_env(:duedesk, DueDesk.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end

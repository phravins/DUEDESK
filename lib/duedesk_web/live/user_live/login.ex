defmodule DueDeskWeb.UserLive.Login do
  use DueDeskWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash} current_scope={@current_scope}>
      <:header_action :if={!@current_scope}>
        New to DueDesk?
        <.link navigate={~p"/users/register"} class="font-medium text-brand hover:underline">
          Sign up
        </.link>
      </:header_action>

      <%= if @current_scope do %>
        <.auth_heading title="Confirm it's you." tagline="Enter your password again.">
          This keeps sensitive changes to your account safe.
        </.auth_heading>
      <% else %>
        <.auth_heading title="Know what is due." tagline="Log in to DueDesk." />
      <% end %>

      <.dev_mailbox_notice />

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
          placeholder="name@company.in"
          autocomplete="username"
          spellcheck="false"
          required
          phx-mounted={!@current_scope && JS.focus()}
        />
        <div class="mb-6">
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            placeholder="Enter password"
            autocomplete="current-password"
            required
            phx-mounted={@current_scope && JS.focus()}
          />
          <div class="-mt-2.5 flex items-center justify-between gap-3 text-[13px]">
            <label
              :if={!@current_scope}
              class="inline-flex cursor-pointer items-center gap-2 text-zinc-600"
            >
              <input
                type="checkbox"
                name={@form[:remember_me].name}
                value="true"
                class="size-3.5 rounded border-zinc-300 accent-navy"
              /> Keep me logged in
            </label>
            <.link
              navigate={~p"/users/reset-password"}
              class="ml-auto font-medium text-brand hover:underline"
            >
              Forgot password?
            </.link>
          </div>
        </div>
        <.button size="lg" class="w-full" phx-disable-with="Logging in...">
          Continue
        </.button>
      </.form>

      <.button
        :if={!@current_scope}
        navigate={~p"/users/register"}
        variant="outline"
        size="lg"
        class="mt-3 w-full"
      >
        Create an account
      </.button>

      <p :if={!@current_scope} class="mt-8 text-xs leading-relaxed text-zinc-400">
        By continuing, you agree to the DueDesk terms of service and privacy policy.
      </p>
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
end

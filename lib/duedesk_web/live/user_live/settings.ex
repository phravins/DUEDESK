defmodule DueDeskWeb.UserLive.Settings do
  use DueDeskWeb, :live_view

  on_mount {DueDeskWeb.UserAuth, :require_sudo_mode}

  alias DueDesk.{Accounts, Notifications, Tenancy}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:profile}>
      <.page_header eyebrow="Settings" icon="hero-cog-6-tooth" title="My profile">
        <:subtitle>Your name, mobile number, email and password.</:subtitle>
      </.page_header>

      <div class="grid gap-4 lg:grid-cols-3">
        <.card id="profile" title="Profile">
          <:subtitle>How your team sees you.</:subtitle>
          <.form for={@profile_form} id="profile_form" phx-submit="update_profile">
            <.input
              field={@profile_form[:name]}
              type="text"
              label="Name"
              required
            />
            <.input
              field={@profile_form[:mobile_number]}
              type="tel"
              label="Mobile number"
              required
            />
            <.button class="mt-2" phx-disable-with="Saving...">Save profile</.button>
          </.form>
        </.card>

        <.card id="email" title="Email">
          <:subtitle>We will send a confirmation link to the new address.</:subtitle>
          <.form
            for={@email_form}
            id="email_form"
            phx-submit="update_email"
            phx-change="validate_email"
          >
            <.input
              field={@email_form[:email]}
              type="email"
              label="Email"
              autocomplete="username"
              spellcheck="false"
              required
            />
            <.button class="mt-2" phx-disable-with="Changing...">Change email</.button>
          </.form>
        </.card>

        <.card id="password" title="Password">
          <:subtitle>You will stay logged in on this device only.</:subtitle>
          <.form
            for={@password_form}
            id="password_form"
            action={~p"/users/update-password"}
            method="post"
            phx-change="validate_password"
            phx-submit="update_password"
            phx-trigger-action={@trigger_submit}
          >
            <input
              name={@password_form[:email].name}
              type="hidden"
              id="hidden_user_email"
              spellcheck="false"
              value={@current_email}
            />
            <.input
              field={@password_form[:password]}
              type="password"
              label="New password"
              autocomplete="new-password"
              spellcheck="false"
              required
            />
            <.input
              field={@password_form[:password_confirmation]}
              type="password"
              label="Confirm new password"
              autocomplete="new-password"
              spellcheck="false"
            />
            <.button class="mt-2" phx-disable-with="Saving...">Save password</.button>
          </.form>
        </.card>

        <.card :if={@notification_form} id="notifications" title="Notifications">
          <:subtitle>How DueDesk reminds you about your DueItems.</:subtitle>
          <.form
            for={@notification_form}
            id="notification-form"
            phx-change="validate_notifications"
            phx-submit="save_notifications"
          >
            <.input
              field={@notification_form[:notify_email]}
              type="checkbox"
              label="Email reminders"
            />
            <.input
              field={@notification_form[:notify_whatsapp]}
              type="checkbox"
              label="WhatsApp reminders"
            />
            <.input
              field={@notification_form[:whatsapp_consent]}
              type="checkbox"
              label={"I agree to receive DueDesk reminders on WhatsApp at #{mobile(@current_scope.user.mobile_number)}"}
            />
            <p
              :if={not @whatsapp_available?}
              id="whatsapp-unavailable"
              class="mb-3 flex items-center gap-1.5 text-xs text-muted"
            >
              <.icon name="hero-information-circle" class="size-4" /> WhatsApp delivery unavailable
            </p>
            <p
              :if={@whatsapp_available? and @whatsapp_enabled?}
              id="whatsapp-enabled"
              class="mb-3 flex items-center gap-1.5 text-xs text-emerald-700"
            >
              <.icon name="hero-check-circle" class="size-4" /> WhatsApp reminder enabled
            </p>
            <.button class="mt-2" phx-disable-with="Saving...">Save notifications</.button>
          </.form>
        </.card>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email changed.")

        {:error, _} ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    socket =
      socket
      |> assign(:page_title, "My profile")
      |> assign(:current_email, user.email)
      |> assign(:profile_form, to_form(Accounts.change_user_profile(user)))
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)
      |> assign(:whatsapp_available?, Notifications.whatsapp_available?())
      |> assign_notifications(socket.assigns.current_scope)

    {:ok, socket}
  end

  defp assign_notifications(socket, %{membership: %Tenancy.Membership{} = membership} = scope) do
    socket
    |> assign(
      :notification_form,
      to_form(Tenancy.change_notification_preferences(scope), as: :notifications)
    )
    |> assign(
      :whatsapp_enabled?,
      membership.notify_whatsapp and not is_nil(membership.whatsapp_consent_at)
    )
  end

  defp assign_notifications(socket, _scope),
    do: socket |> assign(:notification_form, nil) |> assign(:whatsapp_enabled?, false)

  @impl true
  def handle_event("update_profile", %{"user" => user_params}, socket) do
    scope = socket.assigns.current_scope

    case Accounts.update_user_profile(scope, user_params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:current_scope, %{
           scope
           | user: %{user | authenticated_at: scope.user.authenticated_at}
         })
         |> assign(:profile_form, to_form(Accounts.change_user_profile(user)))
         |> put_flash(:info, "Profile saved.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :profile_form, to_form(changeset, action: :update))}
    end
  end

  def handle_event("validate_notifications", %{"notifications" => params}, socket) do
    form =
      socket.assigns.current_scope
      |> Tenancy.change_notification_preferences(params)
      |> to_form(as: :notifications, action: :validate)

    {:noreply, assign(socket, :notification_form, form)}
  end

  def handle_event("save_notifications", %{"notifications" => params}, socket) do
    scope = socket.assigns.current_scope

    case Tenancy.update_notification_preferences(scope, params) do
      {:ok, membership} ->
        scope = %{scope | membership: membership}

        {:noreply,
         socket
         |> assign(:current_scope, scope)
         |> assign_notifications(scope)
         |> put_flash(:info, "Notification settings saved.")}

      {:error, changeset} ->
        {:noreply,
         assign(
           socket,
           :notification_form,
           to_form(changeset, as: :notifications, action: :update)
         )}
    end
  end

  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end
end

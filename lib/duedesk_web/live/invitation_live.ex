defmodule DueDeskWeb.InvitationLive do
  @moduledoc """
  The page an invitation link opens (UX spec §27.3). Someone new signs up
  here with the invited email; someone with a DueDesk login logs in and
  accepts. A link that is unknown, expired, revoked or used says so
  without revealing anything about the account.
  """
  use DueDeskWeb, :live_view

  alias DueDesk.{Accounts, Tenancy}
  alias DueDesk.Tenancy.{Invitation, Membership}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash} current_scope={@current_scope}>
      <%= case @state do %>
        <% :invalid -> %>
          <div id="invitation-invalid">
            <.auth_heading title="This link doesn't work." tagline="Ask for a new invitation.">
              The invitation link is incomplete or no longer exists. Ask the person who invited you
              to send it again.
            </.auth_heading>
            <.button navigate={~p"/"} variant="outline" size="lg" class="w-full">
              Go to DueDesk
            </.button>
          </div>
        <% {:closed, reason} -> %>
          <div id={"invitation-#{reason}"}>
            <.auth_heading title={closed_title(reason)} tagline={@invitation.customer_account.name}>
              {closed_text(reason)}
            </.auth_heading>
            <.button navigate={~p"/"} variant="outline" size="lg" class="w-full">
              Go to DueDesk
            </.button>
          </div>
        <% :wrong_email -> %>
          <div id="invitation-wrong-email">
            <.auth_heading title="This invitation is for someone else." tagline={@invitation.email}>
              You are logged in as <span class="font-medium text-ink">{@current_scope.user.email}</span>. Log out, then
              open the link again to accept it with the invited email.
            </.auth_heading>
            <.button
              href={~p"/users/log-out"}
              method="delete"
              variant="outline"
              size="lg"
              class="w-full"
            >
              Log out
            </.button>
          </div>
        <% :already_member -> %>
          <div id="invitation-already-member">
            <.auth_heading
              title="You already have a DueDesk account."
              tagline="One account per login."
            >
              Your login already works in another DueDesk account, so it can't join {@invitation.customer_account.name} as well. Ask the person who invited you to use a
              different email.
            </.auth_heading>
            <.button navigate={~p"/dashboard"} variant="outline" size="lg" class="w-full">
              Go to your dashboard
            </.button>
          </div>
        <% :accept -> %>
          <div id="invitation-accept">
            <.invited_heading invitation={@invitation} />
            <.button
              id="accept-invitation"
              size="lg"
              class="w-full"
              phx-click="accept"
              phx-disable-with
            >
              Accept and continue
            </.button>
          </div>
        <% :log_in -> %>
          <div id="invitation-log-in">
            <.invited_heading invitation={@invitation} />
            <p class="mb-5 text-[13px] text-zinc-600">
              <span class="font-medium text-ink">{@invitation.email}</span>
              already has a DueDesk login. Log in to accept.
            </p>
            <.button
              id="log-in-to-accept"
              href={~p"/invitations/#{@token}/log-in"}
              size="lg"
              class="w-full"
            >
              Log in to accept
            </.button>
          </div>
        <% :register -> %>
          <div id="invitation-register">
            <.invited_heading invitation={@invitation} />
            <.form
              for={@form}
              id="invitation-form"
              phx-change="validate"
              phx-submit="register"
            >
              <.input
                field={@form[:email]}
                type="email"
                label="Email"
                value={@invitation.email}
                readonly
                hint="The address this invitation was sent to"
              />
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
              <.button size="lg" class="mt-2 w-full" phx-disable-with>
                Join {@invitation.customer_account.name}
              </.button>
            </.form>
            <.legal_consent action="By joining" />
          </div>
      <% end %>
    </Layouts.auth>
    """
  end

  attr :invitation, :map, required: true

  defp invited_heading(assigns) do
    ~H"""
    <.auth_heading
      title={"Join #{@invitation.customer_account.name}."}
      tagline={"As #{article(@invitation.role)} #{Membership.role_label(@invitation.role)}."}
    >
      <%= if @invitation.invited_by do %>
        {@invitation.invited_by.name} invited you to track renewals and filings together on
        DueDesk.
      <% else %>
        You have been invited to track renewals and filings together on DueDesk.
      <% end %>
    </.auth_heading>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    invitation = Tenancy.get_invitation_by_token(token)

    {:ok,
     socket
     |> assign(page_title: "Invitation", token: token, invitation: invitation)
     |> assign_state()}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset = Tenancy.change_invitation_registration(socket.assigns.invitation, params)
    {:noreply, assign(socket, form: to_form(Map.put(changeset, :action, :validate), as: "user"))}
  end

  def handle_event("register", %{"user" => params}, %{assigns: %{state: :register}} = socket) do
    case Tenancy.register_and_accept_invitation(socket.assigns.token, params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Welcome to #{socket.assigns.invitation.customer_account.name}. Log in to get started."
         )
         |> put_flash(:email, socket.assigns.invitation.email)
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "user"))}

      {:error, reason} ->
        {:noreply, failed(socket, reason)}
    end
  end

  def handle_event("accept", _params, %{assigns: %{state: :accept}} = socket) do
    case Tenancy.accept_invitation(socket.assigns.current_scope, socket.assigns.token) do
      {:ok, _membership} ->
        {:noreply,
         socket
         |> put_flash(:info, "Welcome to #{socket.assigns.invitation.customer_account.name}.")
         |> push_navigate(to: ~p"/dashboard")}

      {:error, reason} ->
        {:noreply, failed(socket, reason)}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp failed(socket, {:limit_reached, _info}) do
    put_flash(
      socket,
      :error,
      "#{socket.assigns.invitation.customer_account.name} has no free seats right now. Ask the person who invited you to free one or upgrade their plan."
    )
  end

  defp failed(socket, reason) when reason in [:wrong_email, :already_member],
    do: assign(socket, :state, reason)

  defp failed(socket, :invalid), do: assign(socket, :state, :invalid)
  defp failed(socket, reason), do: assign(socket, :state, {:closed, reason})

  defp assign_state(%{assigns: %{invitation: nil}} = socket), do: assign(socket, :state, :invalid)

  defp assign_state(socket) do
    %{invitation: invitation, current_scope: scope} = socket.assigns
    user = scope && scope.user

    state =
      case Tenancy.invitation_status(invitation) do
        {:error, reason} ->
          {:closed, reason}

        :ok ->
          cond do
            user && String.downcase(user.email) != String.downcase(invitation.email) ->
              :wrong_email

            user && Tenancy.get_current_membership(user) ->
              :already_member

            user ->
              :accept

            Accounts.get_user_by_email(invitation.email) ->
              :log_in

            true ->
              :register
          end
      end

    socket
    |> assign(:state, state)
    |> assign(
      :form,
      if(state == :register,
        do: to_form(Tenancy.change_invitation_registration(invitation), as: "user")
      )
    )
  end

  defp closed_title(:expired), do: "This invitation has expired."
  defp closed_title(:revoked), do: "This invitation was withdrawn."
  defp closed_title(:accepted), do: "This invitation has been used."
  defp closed_title(:account_unavailable), do: "This account is not available."

  defp closed_text(:expired),
    do:
      "Invitations work for #{Invitation.validity_days()} days. Ask the person who invited you to send it again."

  defp closed_text(:revoked),
    do: "The invitation was revoked. Ask the person who invited you if you still need access."

  defp closed_text(:accepted),
    do: "Someone has already accepted it. If that was you, log in to DueDesk to continue."

  defp closed_text(:account_unavailable),
    do: "The account you were invited to can't accept new people right now."

  defp article("admin"), do: "an"
  defp article(_), do: "a"
end

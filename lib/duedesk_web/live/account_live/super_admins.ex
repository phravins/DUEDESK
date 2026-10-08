defmodule DueDeskWeb.AccountLive.SuperAdmins do
  @moduledoc """
  Who owns the account (UX spec §27.5). On plans with several Super Admins
  an active Administrator can be appointed, up to the plan limit, and a
  Super Admin removed (never the last). On single Super Admin plans the
  role is handed over instead. Super Admins only, and only within 10
  minutes of entering their password.
  """
  use DueDeskWeb, :live_view

  alias DueDesk.{Accounts, Billing, Permissions, Tenancy}
  alias DueDesk.Tenancy.Membership
  alias DueDeskWeb.UserAuth

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:users}>
      <.page_header eyebrow="Users" icon="hero-shield-check" title="Super Admins">
        <:subtitle>
          Super Admins manage the plan, billing and every person in the account. They are not
          counted toward your User seats.
        </:subtitle>
        <:actions>
          <.button variant="outline" navigate={~p"/users"}>
            <.icon name="hero-arrow-left-mini" class="size-4" /> Users
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 lg:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]">
        <div class="overflow-x-auto rounded-lg border border-line bg-white">
          <table class="w-full min-w-[520px] text-left text-[13px]">
            <thead class="border-b border-line bg-[#fafaf9] text-[11px] font-semibold uppercase tracking-[0.06em] text-zinc-500">
              <tr>
                <th class="px-4 py-2.5 font-semibold">Name</th>
                <th class="px-4 py-2.5 text-right font-semibold">Actions</th>
              </tr>
            </thead>
            <tbody id="super-admins" phx-update="stream" class="divide-y divide-line">
              <tr :for={{dom_id, m} <- @streams.super_admins} id={dom_id}>
                <td class="px-4 py-3">
                  <p class="font-medium text-ink">
                    {m.user.name}
                    <span :if={m.user_id == @current_scope.user.id} class="text-zinc-400">(you)</span>
                  </p>
                  <p class="text-[12px] text-zinc-500">{m.user.email}</p>
                </td>
                <td class="px-4 py-3 text-right">
                  <.button
                    :if={@multiple? and @super_admin_count > 1}
                    id={"remove-super-admin-#{m.id}"}
                    variant="ghost"
                    size="sm"
                    class="text-rose-600 hover:text-rose-700"
                    phx-click="remove"
                    phx-value-id={m.id}
                    data-confirm={"Make #{m.user.name} an Administrator? They will take a User seat."}
                  >
                    Make Administrator
                  </.button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <%= if @multiple? do %>
          <.card id="appoint" title="Appoint a Super Admin">
            <.meter
              label="Super Admins"
              used={@super_admin_count}
              limit={@super_admin_limit}
            />
            <div class="mt-4">
              <p :if={@admin_options == []} id="appoint-none" class="text-[13px] text-zinc-500">
                Only active Administrators can be appointed. Make someone an Administrator from
                the Users page first.
              </p>
              <p
                :if={@admin_options != [] and @super_admin_limit_reached?}
                id="appoint-limit"
                class="text-[13px] text-zinc-500"
              >
                Your plan allows {@super_admin_limit} Super Admins, and all are in place.
              </p>
              <.form
                :if={@admin_options != [] and not @super_admin_limit_reached?}
                for={@appoint_form}
                id="appoint-form"
                phx-submit="appoint"
              >
                <.input
                  field={@appoint_form[:membership_id]}
                  type="select"
                  label="Administrator"
                  prompt="Choose an Administrator"
                  options={@admin_options}
                />
                <.button id="appoint-super-admin" class="w-full" phx-disable-with>
                  Appoint Super Admin
                </.button>
              </.form>
            </div>
          </.card>
        <% else %>
          <.card id="transfer" title="Transfer ownership">
            <p class="mb-4 text-[13px] text-zinc-600">
              Your plan has one Super Admin. Hand the role to someone else and you become an
              Administrator.
            </p>
            <p :if={@member_options == []} id="transfer-none" class="text-[13px] text-zinc-500">
              Invite someone first; ownership can only go to an active member.
            </p>
            <.form
              :if={@member_options != []}
              for={@transfer_form}
              id="transfer-form"
              phx-submit="transfer"
            >
              <.input
                field={@transfer_form[:membership_id]}
                type="select"
                label="New Super Admin"
                prompt="Choose a person"
                options={@member_options}
              />
              <.button
                id="transfer-ownership"
                variant="danger"
                class="w-full"
                data-confirm="Transfer ownership? You will become an Administrator straight away."
                phx-disable-with
              >
                Transfer ownership
              </.button>
            </.form>
          </.card>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    cond do
      not Permissions.can_manage_super_admins?(scope) ->
        {:ok,
         socket
         |> put_flash(:error, "This page is not available to your account access.")
         |> push_navigate(to: ~p"/dashboard")}

      not Accounts.sudo_mode?(scope.user, -10) ->
        {:ok, reauthenticate(socket)}

      true ->
        {:ok,
         socket
         |> assign(:page_title, "Super Admins")
         |> assign(:multiple?, Billing.multiple_super_admins?(scope))
         |> load()}
    end
  end

  @impl true
  def handle_event("appoint", %{"appoint" => %{"membership_id" => id}}, socket) when id != "" do
    run(socket, id, &Tenancy.appoint_super_admin/2, fn m ->
      "#{m.user.name} is now a Super Admin."
    end)
  end

  def handle_event("remove", %{"id" => id}, socket) do
    run(socket, id, &Tenancy.remove_super_admin/2, fn m ->
      "#{m.user.name} is now an Administrator."
    end)
  end

  def handle_event("transfer", %{"transfer" => %{"membership_id" => id}}, socket)
      when id != "" do
    scope = socket.assigns.current_scope
    membership = Tenancy.get_membership!(scope, id)

    case Tenancy.transfer_ownership(scope, membership) do
      {:ok, _} ->
        disconnect(membership.user_id)

        {:noreply,
         socket
         |> put_flash(:info, "#{membership.user.name} is now the Super Admin.")
         |> push_navigate(to: ~p"/users")}

      {:error, reason} ->
        {:noreply, failed(socket, reason)}
    end
  end

  def handle_event(_event, _params, socket) do
    {:noreply, put_flash(socket, :error, "Choose a person first.")}
  end

  defp run(socket, id, fun, message) do
    scope = socket.assigns.current_scope
    membership = Tenancy.get_membership!(scope, id)

    case fun.(scope, membership) do
      {:ok, _} when membership.user_id == scope.user.id ->
        {:noreply,
         socket |> put_flash(:info, message.(membership)) |> push_navigate(to: ~p"/users")}

      {:ok, _} ->
        disconnect(membership.user_id)
        {:noreply, socket |> put_flash(:info, message.(membership)) |> load()}

      {:error, reason} ->
        {:noreply, failed(socket, reason)}
    end
  end

  defp failed(socket, :reauthenticate), do: reauthenticate(socket)

  defp failed(socket, reason) do
    socket
    |> put_flash(:error, error_message(socket.assigns.current_scope, reason))
    |> load()
  end

  defp reauthenticate(socket) do
    socket
    |> put_flash(:error, "Enter your password again to manage Super Admins.")
    |> redirect(to: ~p"/users/confirm-access?#{[to: ~p"/account/super-admins"]}")
  end

  defp load(socket) do
    scope = socket.assigns.current_scope
    memberships = Tenancy.list_memberships(scope)
    super_admins = Tenancy.list_super_admins(scope)
    limit = Billing.plan(scope).max_super_admins

    options = fn roles ->
      for m <- memberships,
          m.status == "active" and m.role in roles,
          do: {"#{m.user.name} (#{Membership.role_label(m.role)})", m.id}
    end

    socket
    |> assign(:super_admin_count, length(super_admins))
    |> assign(:super_admin_limit, limit)
    |> assign(:super_admin_limit_reached?, Billing.check(scope, :super_admin) != :ok)
    |> assign(:admin_options, options.(["admin"]))
    |> assign(:member_options, options.(["admin", "user"]))
    |> assign(:appoint_form, to_form(%{"membership_id" => ""}, as: :appoint))
    |> assign(:transfer_form, to_form(%{"membership_id" => ""}, as: :transfer))
    |> stream(:super_admins, super_admins, reset: true)
  end

  defp disconnect(user_id),
    do: user_id |> Accounts.list_session_tokens() |> UserAuth.disconnect_sessions()

  defp error_message(scope, {:limit_reached, info}), do: Billing.limit_message(scope, info)
  defp error_message(_scope, :last_super_admin), do: "The account needs at least one Super Admin."
  defp error_message(_scope, :not_admin), do: "Only active Administrators can be appointed."

  defp error_message(_scope, reason) when reason in [:not_active, :not_super_admin, :not_member],
    do: "Someone else changed this person just now. The list has been refreshed."

  defp error_message(_scope, _reason), do: "You don't have permission to do that."
end

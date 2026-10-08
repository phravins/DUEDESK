defmodule DueDeskWeb.UserLive.Index do
  @moduledoc """
  The account's people (UX spec §27): members with their role, status and
  assigned DueItems, pending invitations, the seat meter and the invite
  form. Administrators manage Users; Super Admins also manage
  Administrators and change roles. Administrators and Super Admins only.
  """
  use DueDeskWeb, :live_view

  on_mount {DueDeskWeb.UserAuth, :require_admin}

  alias DueDesk.{Accounts, Billing, Permissions, Tenancy}
  alias DueDesk.Tenancy.{Invitation, Membership}
  alias DueDeskWeb.UserAuth

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:users}>
      <.page_header eyebrow="Account" icon="hero-users" title="Users">
        <:subtitle>
          The people who work in {@current_scope.customer_account.name}. Super Admins are not
          counted toward your seats.
        </:subtitle>
        <:actions>
          <.button
            :if={Permissions.can_manage_super_admins?(@current_scope)}
            id="super-admins-link"
            variant="outline"
            navigate={~p"/account/super-admins"}
          >
            <.icon name="hero-shield-check" class="size-4" /> Super Admins
          </.button>
        </:actions>
      </.page_header>

      <.limit_notice :if={@limit_message} message={@limit_message} plans_link={@plans_link?} />

      <div class="mb-6 grid gap-4 lg:grid-cols-[minmax(0,1fr)_minmax(0,2fr)]">
        <.card id="seats" title="Seats">
          <.meter
            label="Administrators and Users"
            used={@seats.used}
            limit={@seats.limit}
            display={"#{@seats.used} of #{@seats.limit} User seats used"}
          />
          <p class="mt-3 text-[12.5px] text-zinc-500">
            Active members and pending invitations take a seat. Deactivating someone or
            revoking an invitation frees one.
          </p>
        </.card>

        <.card id="invite" title="Invite someone">
          <%= if @limit_message do %>
            <p id="invite-blocked" class="text-[13px] text-zinc-500">
              Every seat is in use. Free a seat or upgrade the plan to invite more people.
            </p>
          <% else %>
            <.form
              for={@invite_form}
              id="invite-form"
              phx-change="validate_invite"
              phx-submit="invite"
              class="grid gap-x-3 sm:grid-cols-[minmax(0,1fr)_180px_auto] sm:items-start"
            >
              <.input
                field={@invite_form[:email]}
                type="email"
                label="Email"
                placeholder="name@company.in"
                autocomplete="off"
                spellcheck="false"
              />
              <.input
                field={@invite_form[:role]}
                type="select"
                label="Role"
                options={@role_options}
              />
              <div class="sm:pt-[22px]">
                <.button id="send-invite" class="w-full" phx-disable-with>
                  <.icon name="hero-paper-airplane" class="size-4" /> Send invite
                </.button>
              </div>
            </.form>
            <p class="text-[12.5px] text-zinc-500">
              They get an email with a link that works for {Invitation.validity_days()} days.
            </p>
          <% end %>
        </.card>
      </div>

      <div class="overflow-x-auto rounded-lg border border-line bg-white">
        <table class="w-full min-w-[760px] text-left text-[13px]">
          <thead class="border-b border-line bg-[#fafaf9] text-[11px] font-semibold uppercase tracking-[0.06em] text-zinc-500">
            <tr>
              <th class="w-14 px-4 py-2.5 font-semibold">S No</th>
              <th class="px-4 py-2.5 font-semibold">Name</th>
              <th class="px-4 py-2.5 font-semibold">Role</th>
              <th class="px-4 py-2.5 font-semibold">Status</th>
              <th class="px-4 py-2.5 text-right font-semibold">Assigned DueItems</th>
              <th class="px-4 py-2.5 text-right font-semibold">Actions</th>
            </tr>
          </thead>
          <tbody id="members" phx-update="stream" class="divide-y divide-line">
            <tr :for={{dom_id, row} <- @streams.members} id={dom_id} class="hover:bg-[#fafaf9]">
              <td class="px-4 py-3 tabular-nums text-zinc-500">{row.position}</td>
              <td class="px-4 py-3">
                <p class="font-medium text-ink">
                  {row.membership.user.name}
                  <span :if={row.membership.user_id == @current_scope.user.id} class="text-zinc-400">
                    (you)
                  </span>
                </p>
                <p class="text-[12px] text-zinc-500">{row.membership.user.email}</p>
              </td>
              <td class="px-4 py-3 text-zinc-700">{Membership.role_label(row.membership.role)}</td>
              <td class="px-4 py-3">
                <.member_status status={row.membership.status} />
              </td>
              <td
                id={"member-assigned-#{row.membership.id}"}
                class="px-4 py-3 text-right tabular-nums text-zinc-600"
              >
                {Map.get(@assigned, row.membership.user_id, 0)}
              </td>
              <td class="px-4 py-3">
                <div class="flex justify-end gap-1.5">
                  <.button
                    :if={
                      row.membership.status == "active" and
                        Permissions.can_change_role?(@current_scope, row.membership)
                    }
                    id={"change-role-#{row.membership.id}"}
                    variant="ghost"
                    size="sm"
                    phx-click="change_role"
                    phx-value-id={row.membership.id}
                    data-confirm={"Make #{row.membership.user.name} #{other_role_label(row.membership.role)}? They will be told by email."}
                  >
                    Make {other_role_label(row.membership.role)}
                  </.button>
                  <.button
                    :if={
                      row.membership.status == "active" and
                        Permissions.can_manage_member?(@current_scope, row.membership)
                    }
                    id={"deactivate-#{row.membership.id}"}
                    variant="ghost"
                    size="sm"
                    class="text-rose-600 hover:text-rose-700"
                    phx-click="open_deactivate"
                    phx-value-id={row.membership.id}
                  >
                    Deactivate
                  </.button>
                  <.button
                    :if={
                      row.membership.status == "deactivated" and
                        Permissions.can_manage_member?(@current_scope, row.membership)
                    }
                    id={"reactivate-#{row.membership.id}"}
                    variant="outline"
                    size="sm"
                    phx-click="reactivate"
                    phx-value-id={row.membership.id}
                    phx-disable-with
                  >
                    Reactivate
                  </.button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <section id="invitations-section" class="mt-8">
        <div class="mb-3 flex items-baseline justify-between gap-3">
          <h2 class="text-[14px] font-semibold text-ink">Pending invitations</h2>
          <span class="text-[12.5px] text-zinc-500">
            {@invitation_count} {if @invitation_count == 1, do: "invitation", else: "invitations"}
          </span>
        </div>
        <div class="overflow-x-auto rounded-lg border border-line bg-white">
          <table class="w-full min-w-[760px] text-left text-[13px]">
            <thead class="border-b border-line bg-[#fafaf9] text-[11px] font-semibold uppercase tracking-[0.06em] text-zinc-500">
              <tr>
                <th class="px-4 py-2.5 font-semibold">Email</th>
                <th class="px-4 py-2.5 font-semibold">Role</th>
                <th class="px-4 py-2.5 font-semibold">Invited by</th>
                <th class="px-4 py-2.5 font-semibold">Expires</th>
                <th class="px-4 py-2.5 text-right font-semibold">Actions</th>
              </tr>
            </thead>
            <tbody id="invitations" phx-update="stream" class="divide-y divide-line">
              <tr id="invitations-empty" class="hidden only:table-row">
                <td colspan="5" class="px-4 py-6 text-center text-[13px] text-zinc-500">
                  No pending invitations.
                </td>
              </tr>
              <tr
                :for={{dom_id, invitation} <- @streams.invitations}
                id={dom_id}
                class="hover:bg-[#fafaf9]"
              >
                <td class="px-4 py-3 font-medium text-ink">{invitation.email}</td>
                <td class="px-4 py-3 text-zinc-700">{Membership.role_label(invitation.role)}</td>
                <td class="px-4 py-3 text-zinc-600">
                  {(invitation.invited_by && invitation.invited_by.name) || "—"}
                </td>
                <td class="px-4 py-3">
                  <%= if Invitation.state(invitation) == :expired do %>
                    <span class="inline-flex items-center gap-1.5 text-[12.5px] font-medium text-amber-700">
                      <span class="size-1.5 rounded-full bg-amber-400" /> Expired
                    </span>
                  <% else %>
                    <span class="text-zinc-600">
                      {DueDeskWeb.Format.date(
                        DateTime.shift_zone!(
                          invitation.expires_at,
                          @current_scope.customer_account.timezone
                        )
                      )}
                    </span>
                  <% end %>
                </td>
                <td class="px-4 py-3">
                  <div
                    :if={Permissions.can_invite_role?(@current_scope, invitation.role)}
                    class="flex justify-end gap-1.5"
                  >
                    <.button
                      id={"resend-#{invitation.id}"}
                      variant="ghost"
                      size="sm"
                      phx-click="resend"
                      phx-value-id={invitation.id}
                      phx-disable-with
                    >
                      Resend
                    </.button>
                    <.button
                      id={"revoke-#{invitation.id}"}
                      variant="ghost"
                      size="sm"
                      class="text-rose-600 hover:text-rose-700"
                      phx-click="revoke"
                      phx-value-id={invitation.id}
                      data-confirm={"Revoke the invitation to #{invitation.email}? The link will stop working."}
                    >
                      Revoke
                    </.button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <div
        :if={@deactivating}
        id="deactivate-modal"
        class="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-ink/40 px-4 pt-24 pb-10"
        phx-window-keydown="close_deactivate"
        phx-key="escape"
        role="dialog"
        aria-modal="true"
        aria-labelledby="deactivate-title"
      >
        <div
          class="w-full max-w-[460px] rounded-lg border border-line bg-white shadow-lg"
          phx-click-away="close_deactivate"
        >
          <div class="border-b border-line px-5 py-4">
            <h2 id="deactivate-title" class="text-[15px] font-semibold text-ink">
              Deactivate {@deactivating.membership.user.name}?
            </h2>
            <p class="mt-1 text-[13px] text-zinc-600">
              They lose access straight away and stop getting reminders. Their history stays.
            </p>
          </div>

          <div class="px-5 py-4">
            <p id="deactivate-count" class="mb-4 text-[13px] text-ink">
              <%= if @deactivating.count == 1 do %>
                {first_name(@deactivating.membership.user.name)} has <span class="font-semibold">1 assigned DueItem</span>.
              <% else %>
                {first_name(@deactivating.membership.user.name)} has <span class="font-semibold">{@deactivating.count} assigned DueItems</span>.
              <% end %>
            </p>

            <%= if @deactivating.count > 0 do %>
              <.form
                for={@deactivate_form}
                id="deactivate-form"
                phx-change="validate_deactivate"
                phx-submit="deactivate"
              >
                <.input
                  field={@deactivate_form[:reassign_to]}
                  type="select"
                  label="Reassign Now to"
                  prompt="Choose a person"
                  options={@deactivating.candidates}
                />
                <div class="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
                  <.button
                    type="button"
                    id="deactivate-unassigned"
                    variant="outline"
                    phx-click="deactivate"
                    phx-value-mode="unassigned"
                    phx-disable-with
                  >
                    Leave Unassigned
                  </.button>
                  <.button id="deactivate-reassign" variant="danger" phx-disable-with>
                    Reassign and deactivate
                  </.button>
                </div>
              </.form>
            <% else %>
              <div class="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
                <.button type="button" variant="outline" phx-click="close_deactivate">
                  Cancel
                </.button>
                <.button
                  type="button"
                  id="deactivate-confirm"
                  variant="danger"
                  phx-click="deactivate"
                  phx-value-mode="unassigned"
                  phx-disable-with
                >
                  Deactivate
                </.button>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :status, :string, required: true

  defp member_status(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1.5 text-[12.5px] font-medium",
      if(@status == "active", do: "text-emerald-700", else: "text-zinc-500")
    ]}>
      <span class={[
        "size-1.5 rounded-full",
        if(@status == "active", do: "bg-emerald-500", else: "bg-zinc-400")
      ]} />
      {if @status == "active", do: "Active", else: "Deactivated"}
    </span>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    role_options =
      for role <- ["user", "admin"],
          Permissions.can_invite_role?(scope, role),
          do: {Membership.role_label(role), role}

    {:ok,
     socket
     |> assign(:page_title, "Users")
     |> assign(:role_options, role_options)
     |> assign(:deactivating, nil)
     |> assign(:deactivate_form, nil)
     |> assign_invite_form(Tenancy.change_invitation())
     |> load()}
  end

  @impl true
  def handle_event("validate_invite", %{"invitation" => params}, socket) do
    changeset = Tenancy.change_invitation(params)
    {:noreply, assign_invite_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("invite", %{"invitation" => params}, socket) do
    scope = socket.assigns.current_scope

    case Tenancy.invite_member(scope, params, &url(~p"/invitations/#{&1}")) do
      {:ok, invitation} ->
        {:noreply,
         socket
         |> put_flash(:info, "Invitation sent to #{invitation.email}.")
         |> assign_invite_form(Tenancy.change_invitation())
         |> load()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_invite_form(socket, changeset)}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, error_message(scope, reason)) |> load()}
    end
  end

  def handle_event("resend", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    invitation = Tenancy.get_invitation!(scope, id)

    case Tenancy.resend_invitation(scope, invitation, &url(~p"/invitations/#{&1}")) do
      {:ok, invitation} ->
        {:noreply,
         socket |> put_flash(:info, "Invitation sent again to #{invitation.email}.") |> load()}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, error_message(scope, reason)) |> load()}
    end
  end

  def handle_event("revoke", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    invitation = Tenancy.get_invitation!(scope, id)

    case Tenancy.revoke_invitation(scope, invitation) do
      {:ok, invitation} ->
        {:noreply,
         socket
         |> put_flash(:info, "Invitation to #{invitation.email} revoked.")
         |> stream_delete(:invitations, invitation)
         |> load()}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, error_message(scope, reason)) |> load()}
    end
  end

  def handle_event("change_role", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    membership = Tenancy.get_membership!(scope, id)
    role = if membership.role == "admin", do: "user", else: "admin"

    case Tenancy.change_member_role(scope, membership, role) do
      {:ok, updated} ->
        disconnect(updated.user_id)

        {:noreply,
         socket
         |> put_flash(
           :info,
           "#{membership.user.name} is now #{article(role)} #{Membership.role_label(role)}."
         )
         |> load()}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, error_message(scope, reason)) |> load()}
    end
  end

  def handle_event("open_deactivate", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    membership = Tenancy.get_membership!(scope, id)

    if Permissions.can_manage_member?(scope, membership) and membership.status == "active" do
      candidates =
        for m <- Tenancy.list_memberships(scope),
            m.status == "active" and m.id != membership.id,
            do: {"#{m.user.name} (#{Membership.role_label(m.role)})", m.user_id}

      {:noreply,
       socket
       |> assign(:deactivating, %{
         membership: membership,
         count: Map.get(socket.assigns.assigned, membership.user_id, 0),
         candidates: candidates
       })
       |> assign(:deactivate_form, to_form(%{"reassign_to" => ""}, as: :deactivate))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_deactivate", _params, socket) do
    {:noreply, assign(socket, deactivating: nil, deactivate_form: nil)}
  end

  def handle_event("validate_deactivate", %{"deactivate" => params}, socket) do
    {:noreply, assign(socket, :deactivate_form, to_form(params, as: :deactivate))}
  end

  def handle_event("deactivate", params, %{assigns: %{deactivating: %{}}} = socket) do
    scope = socket.assigns.current_scope
    %{membership: membership} = socket.assigns.deactivating

    reassign_to =
      case params do
        %{"mode" => "unassigned"} -> nil
        %{"deactivate" => %{"reassign_to" => id}} when id != "" -> id
        _ -> :missing
      end

    if reassign_to == :missing do
      form =
        to_form(%{"reassign_to" => ""},
          as: :deactivate,
          errors: [reassign_to: {"choose who takes over, or leave the DueItems unassigned", []}],
          action: :validate
        )

      {:noreply, assign(socket, :deactivate_form, form)}
    else
      case Tenancy.deactivate_member(scope, membership, reassign_to) do
        {:ok, %{due_items: count}} ->
          disconnect(membership.user_id)

          {:noreply,
           socket
           |> put_flash(:info, deactivated_message(membership, reassign_to, count))
           |> assign(deactivating: nil, deactivate_form: nil)
           |> load()}

        {:error, reason} ->
          {:noreply,
           socket
           |> put_flash(:error, error_message(scope, reason))
           |> assign(deactivating: nil, deactivate_form: nil)
           |> load()}
      end
    end
  end

  def handle_event("deactivate", _params, socket), do: {:noreply, socket}

  def handle_event("reactivate", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    membership = Tenancy.get_membership!(scope, id)

    case Tenancy.reactivate_member(scope, membership) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{membership.user.name} can use DueDesk again.")
         |> load()}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, error_message(scope, reason)) |> load()}
    end
  end

  defp load(socket) do
    scope = socket.assigns.current_scope
    members = Tenancy.list_memberships(scope)
    invitations = Tenancy.list_open_invitations(scope)

    {limit_message, plans_link?} =
      case Billing.check(scope, :member) do
        :ok ->
          {nil, false}

        {:error, {:limit_reached, info}} ->
          {Billing.limit_message(scope, info), Permissions.can_manage_billing?(scope)}
      end

    rows =
      members
      |> Enum.sort_by(&{&1.status != "active", role_rank(&1.role), String.downcase(&1.user.name)})
      |> Enum.with_index(1)
      |> Enum.map(fn {m, i} -> %{id: m.id, position: i, membership: m} end)

    socket
    |> assign(:seats, Billing.seats(scope))
    |> assign(:assigned, Tenancy.assigned_counts(scope))
    |> assign(:limit_message, limit_message)
    |> assign(:plans_link?, plans_link?)
    |> assign(:invitation_count, length(invitations))
    |> stream(:members, rows, reset: true)
    |> stream(:invitations, invitations, reset: true)
  end

  defp assign_invite_form(socket, changeset), do: assign(socket, :invite_form, to_form(changeset))

  defp disconnect(user_id),
    do: user_id |> Accounts.list_session_tokens() |> UserAuth.disconnect_sessions()

  defp role_rank("super_admin"), do: 0
  defp role_rank("admin"), do: 1
  defp role_rank(_), do: 2

  defp other_role_label("admin"), do: "User"
  defp other_role_label(_), do: "Administrator"

  defp article("admin"), do: "an"
  defp article(_), do: "a"

  defp first_name(name), do: name |> String.split(" ", trim: true) |> List.first()

  defp deactivated_message(membership, nil, 0),
    do: "#{membership.user.name} has been deactivated."

  defp deactivated_message(membership, nil, count),
    do:
      "#{membership.user.name} has been deactivated. #{count} #{items(count)} left without them; any without a Primary Responsible are in Unassigned."

  defp deactivated_message(membership, _reassign_to, count),
    do: "#{membership.user.name} has been deactivated and #{count} #{items(count)} reassigned."

  defp items(1), do: "DueItem"
  defp items(_), do: "DueItems"

  defp error_message(scope, {:limit_reached, info}), do: Billing.limit_message(scope, info)
  defp error_message(_scope, :invalid_target), do: "Choose an active person to take over."
  defp error_message(_scope, :closed), do: "That invitation is no longer open."

  defp error_message(_scope, reason) when reason in [:not_active, :not_deactivated, :unchanged],
    do: "Someone else changed this person just now. The list has been refreshed."

  defp error_message(_scope, _reason), do: "You don't have permission to do that."
end

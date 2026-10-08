defmodule DueDeskWeb.DueItemLive.Show do
  @moduledoc """
  A DueItem's detail page (UX spec §35): dates, status, who is
  responsible, recurrence and reminders, notes and readable history.

  Administrators and Super Admins edit, assign, override the status and
  archive or restore here. Anyone who can see the DueItem can add notes.
  A DueItem the viewer may not see gets the same message whether it
  exists or not.
  """
  use DueDeskWeb, :live_view

  import DueDeskWeb.DueItemComponents

  alias DueDesk.{Billing, DueItems, Permissions, Tenancy}
  alias DueDesk.DueItems.{Cycle, DueItem, Recurrence, ReminderRule, Status}

  @not_available "This DueItem is not available to your account access."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:due_items}>
      <.page_header eyebrow="DueItems" icon="hero-clipboard-document-list" title={@item.title}>
        <:subtitle>
          <span class="inline-flex flex-wrap items-center gap-x-2 gap-y-1">
            <span id="due-item-status">
              <.due_item_status item={@item} status={@status} overridden />
            </span>
            <span class="text-zinc-300" aria-hidden="true">·</span>
            <span>{@item.organisation.name}</span>
            <span class="text-zinc-300" aria-hidden="true">·</span>
            <span>{@item.category.name}</span>
          </span>
        </:subtitle>
        <:actions :if={@control?}>
          <%= if @item.status == "active" do %>
            <.button
              id="archive-due-item"
              variant="outline"
              phx-click="archive"
              data-confirm="Archive this DueItem? It is hidden from Users, stops sending reminders and no longer counts toward your plan. Its history is kept."
            >
              <.icon name="hero-archive-box" class="size-4" /> Archive
            </.button>
            <.button id="edit-due-item" navigate={~p"/due-items/#{@item}/edit"}>
              <.icon name="hero-pencil-square" class="size-4" /> Edit
            </.button>
          <% else %>
            <.button
              id="restore-due-item"
              phx-click="restore"
              data-confirm="Restore this DueItem? Check its dates and who is responsible afterwards. It will count toward your plan again."
            >
              <.icon name="hero-arrow-uturn-left" class="size-4" /> Restore
            </.button>
          <% end %>
        </:actions>
      </.page_header>

      <.limit_notice :if={@limit_message} message={@limit_message} plans_link={@plans_link?} />

      <div
        :if={@item.status == "archived"}
        id="archived-banner"
        class="mb-4 flex items-start gap-2.5 rounded-lg border border-line bg-[#f6f6f4] px-4 py-3 text-sm text-zinc-600"
      >
        <.icon name="hero-archive-box" class="mt-px size-5 shrink-0 text-zinc-400" />
        <span>
          Archived{if @item.archived_at, do: " on #{datetime(@item.archived_at, @tz)}"}. It is
          hidden from Users and sends no reminders.
        </span>
      </div>

      <div class="grid gap-4 lg:grid-cols-3">
        <div class="space-y-4 lg:col-span-2">
          <.card id="due-item-dates" title="Dates">
            <:action :if={@control? and @item.status == "active" and @panel != :override}>
              <button
                type="button"
                id="open-override"
                phx-click="open_panel"
                phx-value-panel="override"
                class="text-xs font-medium text-zinc-500 transition hover:text-ink"
              >
                Override status
              </button>
            </:action>
            <div class="grid gap-4 sm:grid-cols-3">
              <div class="rounded-md bg-[#f6f6f4] px-3.5 py-3">
                <p class="text-xs text-muted">Action Due</p>
                <p id="due-item-due-date" class="mt-0.5 text-base font-semibold text-ink">
                  {date(@cycle.due_date)}
                </p>
                <p :if={@days_note} class="mt-0.5 text-xs text-zinc-500">{@days_note}</p>
              </div>
              <div class="rounded-md bg-[#f6f6f4] px-3.5 py-3">
                <p class="text-xs text-muted">Expires</p>
                <p id="due-item-expiry-date" class="mt-0.5 text-base font-semibold text-ink">
                  {date(@cycle.expiry_date)}
                </p>
              </div>
              <div class="rounded-md bg-[#f6f6f4] px-3.5 py-3">
                <p class="text-xs text-muted">Start</p>
                <p class="mt-0.5 text-base font-semibold text-ink">{date(@cycle.start_date)}</p>
              </div>
            </div>

            <div
              :if={@cycle.status_override}
              id="status-override"
              class="mt-4 flex flex-wrap items-start justify-between gap-3 rounded-md border border-amber-200/70 bg-amber-50/60 px-3.5 py-3 text-sm"
            >
              <div class="min-w-0">
                <p class="font-medium text-zinc-800">
                  Status set to {Status.label(String.to_existing_atom(@cycle.status_override))} by an Administrator
                </p>
                <p class="mt-0.5 text-zinc-600">{@cycle.status_override_reason}</p>
                <p class="mt-1 text-xs text-zinc-500">
                  Applies until the next cycle. The dates would give {Status.label(@computed_status)}.
                </p>
              </div>
              <button
                :if={@control?}
                type="button"
                id="clear-override"
                phx-click="clear_override"
                class="shrink-0 text-xs font-medium text-zinc-600 underline-offset-2 hover:text-ink hover:underline"
              >
                Remove override
              </button>
            </div>

            <.form
              :if={@panel == :override}
              for={@override_form}
              id="override-form"
              phx-submit="override"
              class="mt-4 rounded-md border border-line p-4 pb-1"
            >
              <p class="mb-3 text-sm font-medium text-ink">Override status</p>
              <div class="grid gap-x-4 sm:grid-cols-3">
                <.input
                  field={@override_form[:status]}
                  type="select"
                  label="Status"
                  options={override_options()}
                />
                <div class="sm:col-span-2">
                  <.input
                    field={@override_form[:reason]}
                    label="Reason"
                    placeholder="e.g. Filed on the portal, acknowledgement awaited"
                    maxlength="500"
                  />
                </div>
              </div>
              <div class="mb-3 flex gap-2">
                <.button id="save-override" size="sm" phx-disable-with="Saving…">
                  Set status
                </.button>
                <.button type="button" size="sm" variant="ghost" phx-click="close_panel">
                  Cancel
                </.button>
              </div>
            </.form>
          </.card>

          <.card :if={has_details?(@item)} id="due-item-details" title="Details">
            <dl class="-my-3 divide-y divide-line">
              <.detail :if={@item.reference_number} label="Reference Number">
                <span class="font-mono text-[13px]">{@item.reference_number}</span>
              </.detail>
              <.detail :if={@item.related_party} label="Related Party">
                {@item.related_party}
              </.detail>
              <.detail :if={@item.description} label="Description">
                <span class="whitespace-pre-line">{@item.description}</span>
              </.detail>
            </dl>
          </.card>

          <.card id="due-item-notes" title="Notes">
            <:subtitle>Visible to everyone who can see this DueItem.</:subtitle>
            <ul id="notes" phx-update="stream" class="space-y-4">
              <li id="notes-empty" class="hidden text-sm text-muted only:block">
                No notes yet.
              </li>
              <li :for={{dom_id, note} <- @streams.notes} id={dom_id} class="flex gap-3">
                <.avatar name={author_name(note)} size="md" />
                <div class="min-w-0 flex-1">
                  <p class="text-xs text-muted">
                    <span class="font-medium text-zinc-700">{author_name(note)}</span>
                    · {datetime(note.inserted_at, @tz)}
                  </p>
                  <p class="mt-1 whitespace-pre-line text-sm text-ink">{note.body}</p>
                </div>
              </li>
            </ul>
            <.form
              :if={@item.status == "active"}
              for={@note_form}
              id="note-form"
              phx-submit="add_note"
              phx-change="validate_note"
              class="mt-5 border-t border-line pt-4"
            >
              <.input
                field={@note_form[:body]}
                type="textarea"
                placeholder="Add a note: what was done, who was contacted, what is pending."
                aria-label="Note"
                maxlength="4000"
                class="block min-h-20 w-full rounded-md border border-transparent bg-field px-3 py-2.5 text-sm text-ink placeholder:text-zinc-400 transition hover:bg-[#ededeb] focus:border-zinc-300 focus:bg-white focus:outline-none focus:ring-3 focus:ring-zinc-900/5"
              />
              <.button id="save-note" size="sm" phx-disable-with="Adding…">Add note</.button>
            </.form>
          </.card>

          <.card id="due-item-history" title="History">
            <ol id="history" phx-update="stream" class="relative space-y-4">
              <li id="history-empty" class="hidden text-sm text-muted only:block">
                No history yet.
              </li>
              <li :for={{dom_id, entry} <- @streams.history} id={dom_id} class="flex gap-3">
                <span class="mt-1.5 size-2 shrink-0 rounded-full bg-zinc-300" aria-hidden="true" />
                <div class="min-w-0 flex-1">
                  <p class="text-sm text-ink">{entry.sentence}</p>
                  <ul :if={entry.details != []} class="mt-1 space-y-0.5">
                    <li :for={detail <- entry.details} class="text-xs text-zinc-600">{detail}</li>
                  </ul>
                  <p class="mt-0.5 text-xs text-muted">{datetime(entry.at, @tz)}</p>
                </div>
              </li>
            </ol>
          </.card>
        </div>

        <div class="space-y-4">
          <.card id="due-item-responsibility" title="Responsibility">
            <:action :if={@control? and @item.status == "active" and @panel != :assign}>
              <button
                type="button"
                id="open-assign"
                phx-click="open_panel"
                phx-value-panel="assign"
                class="text-xs font-medium text-zinc-500 transition hover:text-ink"
              >
                {if @primary, do: "Edit", else: "Assign"}
              </button>
            </:action>

            <%= if @panel == :assign do %>
              <.form
                for={@assign_form}
                id="assign-form"
                phx-change="validate_assign"
                phx-submit="assign"
              >
                <.input
                  field={@assign_form[:primary_user_id]}
                  type="select"
                  label="Primary Responsible"
                  prompt="Unassigned"
                  options={@member_options}
                />
                <fieldset :if={@assign_primary_id} class="mb-4">
                  <legend class="mb-2 text-[13px] font-medium text-zinc-600">
                    Additional Assignees
                  </legend>
                  <input type="hidden" name="assignment[additional_user_ids][]" value="" />
                  <div class="space-y-2">
                    <label
                      :for={{name, id} <- @member_options}
                      :if={id != @assign_primary_id}
                      class="flex cursor-pointer items-center gap-2.5 text-sm text-zinc-700"
                    >
                      <input
                        type="checkbox"
                        id={"assign-additional-#{id}"}
                        name="assignment[additional_user_ids][]"
                        value={id}
                        checked={id in @assign_additional_ids}
                        class="size-4 rounded border-zinc-300 accent-navy"
                      />
                      {name}
                    </label>
                  </div>
                  <p
                    :for={
                      msg <- Enum.map(@assign_form[:additional_user_ids].errors, &translate_error/1)
                    }
                    class="mt-1.5 text-xs text-rose-600"
                  >
                    {msg}
                  </p>
                </fieldset>
                <div class="flex gap-2">
                  <.button id="save-assignment" size="sm" phx-disable-with="Saving…">Save</.button>
                  <.button type="button" size="sm" variant="ghost" phx-click="close_panel">
                    Cancel
                  </.button>
                </div>
              </.form>
            <% else %>
              <%= if @primary do %>
                <div id="primary-responsible" class="flex items-center gap-3">
                  <.avatar name={@primary.name} size="md" />
                  <div class="min-w-0">
                    <p class="truncate text-sm font-medium text-ink">{@primary.name}</p>
                    <p class="text-xs text-muted">Primary Responsible</p>
                  </div>
                </div>
                <div :if={@additional != []} id="additional-assignees" class="mt-4">
                  <p class="mb-2 text-xs text-muted">Additional Assignees</p>
                  <ul class="space-y-2">
                    <li :for={user <- @additional} class="flex items-center gap-2 text-sm">
                      <.avatar name={user.name} />
                      <span class="truncate text-zinc-700">{user.name}</span>
                    </li>
                  </ul>
                </div>
              <% else %>
                <div id="unassigned-notice" class="text-sm">
                  <.status_badge status={:unassigned} />
                  <p class="mt-2 text-zinc-600">
                    Nobody is responsible for this DueItem, so reminders go only to
                    Administrators once it is overdue.
                  </p>
                  <.button
                    :if={@control? and @item.status == "active"}
                    id="assign-responsibility"
                    size="sm"
                    class="mt-3"
                    phx-click="open_panel"
                    phx-value-panel="assign"
                  >
                    <.icon name="hero-user-plus" class="size-4" /> Assign Responsibility
                  </.button>
                </div>
              <% end %>
            <% end %>
          </.card>

          <.card id="due-item-schedule" title="Recurrence & reminders">
            <dl class="space-y-3 text-sm">
              <div>
                <dt class="text-xs text-muted">Repeats</dt>
                <dd id="due-item-recurrence" class="text-ink">{Recurrence.describe(@item)}</dd>
              </div>
              <div>
                <dt class="text-xs text-muted">Reminders</dt>
                <dd id="due-item-reminders">
                  <%= if @reminders == [] do %>
                    <span class="text-zinc-500">No reminders</span>
                  <% else %>
                    <ul class="mt-1 flex flex-wrap gap-1.5">
                      <li
                        :for={offset <- @reminders}
                        class="rounded-full bg-[#efefed] px-2 py-0.5 text-xs text-zinc-600"
                      >
                        {ReminderRule.describe(offset)}
                      </li>
                    </ul>
                  <% end %>
                </dd>
              </div>
            </dl>
          </.card>

          <div class="rounded-lg border border-dashed border-zinc-300 px-4 py-3 text-sm text-zinc-500">
            <p class="flex items-center gap-2">
              <.icon name="hero-paper-clip" class="size-4 text-zinc-400" /> Documents
            </p>
            <p class="mt-1 text-xs">Uploading documents arrives in an upcoming release.</p>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    case DueItems.get_due_item(scope, id) do
      {:ok, item} ->
        {:ok,
         socket
         |> assign(:control?, Permissions.can_manage_due_items?(scope))
         |> assign(:tz, scope.customer_account.timezone)
         |> assign(:today, Tenancy.today(scope))
         |> assign(:panel, nil)
         |> assign(:limit_message, nil)
         |> assign(:plans_link?, false)
         |> assign(:note_form, to_form(DueItems.change_note()))
         |> assign_item(item)
         |> stream(:notes, DueItems.list_notes(scope, item))}

      {:error, :not_found} ->
        {:ok, not_available(socket)}
    end
  end

  @impl true
  def handle_event("open_panel", %{"panel" => "assign"}, socket) do
    if socket.assigns.control? do
      %{current_scope: scope, item: item} = socket.assigns

      {:noreply,
       socket
       |> assign(:panel, :assign)
       |> assign(:member_options, member_options(scope))
       |> assign_assignment(DueItems.change_assignment(scope, item))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("open_panel", %{"panel" => "override"}, socket) do
    if socket.assigns.control? do
      {:noreply,
       socket
       |> assign(:panel, :override)
       |> assign(
         :override_form,
         to_form(%{"status" => "up_to_date", "reason" => ""}, as: :override)
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_panel", _params, socket) do
    {:noreply, assign(socket, :panel, nil)}
  end

  def handle_event("validate_assign", %{"assignment" => params}, socket) do
    %{current_scope: scope, item: item} = socket.assigns
    {:noreply, assign_assignment(socket, DueItems.change_assignment(scope, item, params))}
  end

  def handle_event("assign", %{"assignment" => params}, socket) do
    %{current_scope: scope, item: item} = socket.assigns

    case DueItems.assign_due_item(scope, item, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:panel, nil)
         |> put_flash(:info, "Responsibility updated.")
         |> reload()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_assignment(socket, changeset)}

      {:error, _} ->
        {:noreply, not_available(socket)}
    end
  end

  def handle_event("override", %{"override" => %{"status" => status, "reason" => reason}}, socket) do
    %{current_scope: scope, item: item} = socket.assigns

    case DueItems.override_status(scope, item, status, reason) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:panel, nil)
         |> put_flash(:info, "Status overridden until the next cycle.")
         |> reload()}

      {:error, %Ecto.Changeset{} = changeset} ->
        errors =
          for {field, error} <- changeset.errors,
              form_field = override_field(field),
              do: {form_field, error}

        {:noreply,
         assign(
           socket,
           :override_form,
           to_form(%{"status" => status, "reason" => reason},
             as: :override,
             errors: errors,
             action: :validate
           )
         )}

      {:error, _} ->
        {:noreply, not_available(socket)}
    end
  end

  def handle_event("clear_override", _params, socket) do
    %{current_scope: scope, item: item} = socket.assigns

    case DueItems.clear_status_override(scope, item) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Status override removed.") |> reload()}

      {:error, _} ->
        {:noreply, not_available(socket)}
    end
  end

  def handle_event("archive", _params, socket) do
    %{current_scope: scope, item: item} = socket.assigns

    case DueItems.archive_due_item(scope, item) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "DueItem archived.") |> reload()}

      {:error, :not_active} ->
        {:noreply, reload(socket)}

      {:error, _} ->
        {:noreply, not_available(socket)}
    end
  end

  def handle_event("restore", _params, socket) do
    %{current_scope: scope, item: item} = socket.assigns

    case DueItems.restore_due_item(scope, item) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:limit_message, nil)
         |> put_flash(:info, "DueItem restored. Check its dates and who is responsible.")
         |> reload()}

      {:error, {:limit_reached, info}} ->
        {:noreply,
         socket
         |> assign(:limit_message, Billing.limit_message(scope, info))
         |> assign(:plans_link?, Permissions.can_manage_billing?(scope))}

      {:error, :not_archived} ->
        {:noreply, reload(socket)}

      {:error, _} ->
        {:noreply, not_available(socket)}
    end
  end

  def handle_event("validate_note", %{"note" => params}, socket) do
    {:noreply, assign(socket, :note_form, to_form(DueItems.change_note(params)))}
  end

  def handle_event("add_note", %{"note" => params}, socket) do
    %{current_scope: scope, item: item} = socket.assigns

    case DueItems.add_note(scope, item, params) do
      {:ok, note} ->
        {:noreply,
         socket
         |> assign(:note_form, to_form(DueItems.change_note()))
         |> stream_insert(:notes, note)
         |> stream(:history, DueItems.history(scope, item), reset: true)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :note_form, to_form(changeset, action: :validate))}

      {:error, :unauthorized} ->
        {:noreply, not_available(socket)}
    end
  end

  # Reloads the DueItem after a change. If the viewer can no longer see
  # it, they leave with the usual message.
  defp reload(socket) do
    %{current_scope: scope, item: item} = socket.assigns

    case DueItems.get_due_item(scope, item.id) do
      {:ok, item} -> assign_item(socket, item)
      {:error, :not_found} -> not_available(socket)
    end
  end

  defp assign_item(socket, %DueItem{} = item) do
    %{current_scope: scope, today: today} = socket.assigns
    days = scope.customer_account.due_soon_days
    cycle = item.current_cycle
    status = Status.effective(item, cycle, today, days)

    socket
    |> assign(:page_title, item.title)
    |> assign(:item, item)
    |> assign(:cycle, cycle)
    |> assign(:status, status)
    |> assign(
      :computed_status,
      Status.effective(item, %{cycle | status_override: nil}, today, days)
    )
    |> assign(:days_note, days_note(item, cycle, today))
    |> assign(:primary, DueItem.primary_user(item))
    |> assign(:additional, DueItem.additional_users(item))
    |> assign(:reminders, for(%{active: true, offset_days: d} <- item.reminder_rules, do: d))
    |> stream(:history, DueItems.history(scope, item), reset: true)
  end

  defp assign_assignment(socket, changeset) do
    primary = Ecto.Changeset.get_field(changeset, :primary_user_id)

    socket
    |> assign(:assign_form, to_form(changeset, as: :assignment))
    |> assign(:assign_primary_id, primary)
    |> assign(
      :assign_additional_ids,
      List.wrap(Ecto.Changeset.get_field(changeset, :additional_user_ids))
    )
  end

  defp not_available(socket) do
    socket
    |> put_flash(:error, @not_available)
    |> push_navigate(to: ~p"/due-items")
  end

  defp member_options(scope) do
    scope
    |> DueItems.assignable_members()
    |> Enum.map(&{&1.user.name, &1.user.id})
  end

  defp override_options do
    for name <- Cycle.overrides(), do: {Status.label(String.to_existing_atom(name)), name}
  end

  defp override_field(:status_override), do: :status
  defp override_field(:status_override_reason), do: :reason
  defp override_field(_), do: nil

  defp has_details?(item),
    do: Enum.any?([item.reference_number, item.related_party, item.description])

  defp author_name(%{author_user: %{name: name}}), do: name
  defp author_name(_), do: "A former member"

  defp days_note(%DueItem{status: "active"}, %Cycle{} = cycle, today) do
    case cycle.due_date do
      nil ->
        nil

      date ->
        case Date.diff(date, today) do
          0 -> "Today"
          1 -> "Tomorrow"
          -1 -> "Yesterday"
          n when n > 0 -> "In #{n} days"
          n -> "#{-n} days ago"
        end
    end
  end

  defp days_note(_item, _cycle, _today), do: nil
end

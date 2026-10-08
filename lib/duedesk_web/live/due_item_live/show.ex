defmodule DueDeskWeb.DueItemLive.Show do
  @moduledoc """
  A DueItem's detail page (UX spec §35): dates, status, who is
  responsible, recurrence and reminders, documents, notes and readable
  history.

  Anyone who can see an active DueItem can renew or complete it, upload
  documents and add notes. Administrators and Super Admins edit, assign, override the
  status, archive, decide what happens to completed DueItems, restore
  archived ones and review Users' renewals here; a Super Admin can
  permanently delete an archived DueItem.
  A DueItem the viewer may not see gets the same message whether it
  exists or not.
  """
  use DueDeskWeb, :live_view

  import DueDeskWeb.DueItemComponents
  import DueDeskWeb.DocumentComponents

  alias DueDesk.{Billing, Documents, DueItems, Permissions, Tenancy}
  alias DueDesk.Documents.Document
  alias DueDesk.DueItems.{Cycle, DueItem, Recurrence, ReminderRule, Status}

  @not_available "This DueItem is not available to your account access."
  @stale "This DueItem has already been updated. Refresh to see the latest."

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
        <:actions :if={@can_act? or @control?}>
          <.button
            :if={@can_act? and @recurring?}
            id="renew-due-item"
            navigate={~p"/due-items/#{@item}/renew"}
          >
            <.icon name="hero-arrow-path" class="size-4" /> Renew
          </.button>
          <.button
            :if={@can_act? and not @recurring?}
            id="complete-due-item"
            navigate={~p"/due-items/#{@item}/complete"}
          >
            <.icon name="hero-check" class="size-4" /> Mark as completed
          </.button>
          <%= cond do %>
            <% not @control? or @awaiting -> %>
            <% @item.status == "active" -> %>
              <.button
                id="archive-due-item"
                variant="outline"
                phx-click="archive"
                data-confirm="Archive this DueItem? It is hidden from Users, stops sending reminders and no longer counts toward your plan. Its history is kept."
              >
                <.icon name="hero-archive-box" class="size-4" /> Archive
              </.button>
              <.button
                id="edit-due-item"
                variant={if(@can_act?, do: "outline", else: "primary")}
                navigate={~p"/due-items/#{@item}/edit"}
              >
                <.icon name="hero-pencil-square" class="size-4" /> Edit
              </.button>
            <% true -> %>
              <.button
                :if={@delete? and @panel != :delete}
                id="delete-due-item"
                variant="outline"
                phx-click="open_panel"
                phx-value-panel="delete"
              >
                <.icon name="hero-trash" class="size-4" /> Delete permanently
              </.button>
              <.button id="restore-due-item" navigate={~p"/due-items/#{@item}/reactivate"}>
                <.icon name="hero-arrow-uturn-left" class="size-4" /> Restore
              </.button>
          <% end %>
        </:actions>
      </.page_header>

      <div
        :if={@control? and @awaiting}
        id="awaiting-banner"
        class="mb-4 flex flex-col gap-3 rounded-lg border border-violet-200/70 bg-violet-50/60 px-4 py-3 text-sm sm:flex-row sm:items-center"
      >
        <.icon name="hero-inbox-arrow-down" class="hidden size-5 shrink-0 text-violet-500 sm:block" />
        <div class="min-w-0 flex-1 text-violet-900">
          <p>{awaiting_message(@awaiting, List.first(@cycles))}</p>
          <.document_list
            :if={cycle_documents(@documents_by_cycle, List.first(@cycles)) != []}
            id="awaiting-documents"
            documents={cycle_documents(@documents_by_cycle, List.first(@cycles))}
            tz={@tz}
            dom_prefix="awaiting-"
            compact
          />
        </div>
        <div class="flex shrink-0 flex-wrap gap-2">
          <.button
            id="archive-awaiting"
            size="sm"
            variant="outline"
            phx-click="archive"
            data-confirm="Archive this DueItem? It no longer counts toward your plan. Its history is kept."
          >
            <.icon name="hero-archive-box" class="size-4" /> Archive
          </.button>
          <.button
            id="reactivate-due-item"
            size="sm"
            navigate={~p"/due-items/#{@item}/reactivate"}
          >
            {if @awaiting == :needs_dates, do: "Set new dates", else: "Re-date and reactivate"}
          </.button>
        </div>
      </div>

      <div
        :if={@control? and @pending_review}
        id="renewal-review"
        class="mb-4 flex flex-col gap-3 rounded-lg border border-sky-200/70 bg-sky-50/60 px-4 py-3 text-sm sm:flex-row sm:items-center"
      >
        <.icon name="hero-eye" class="hidden size-5 shrink-0 text-sky-600 sm:block" />
        <p class="min-w-0 flex-1 text-sky-900">
          Renewed by {completed_by(@pending_review)} on {date(@pending_review.completed_on)}.
          Check the new dates, then mark the renewal as reviewed.
        </p>
        <.button
          id="dismiss-review"
          size="sm"
          variant="outline"
          phx-click="dismiss_review"
          phx-value-id={@pending_review.id}
        >
          <.icon name="hero-check" class="size-4" /> Mark as reviewed
        </.button>
      </div>

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

      <.form
        :if={@panel == :delete}
        for={@delete_form}
        id="delete-form"
        phx-submit="delete"
        class="mb-4 rounded-lg border border-rose-200 bg-rose-50/40 p-4 pb-1"
      >
        <p class="text-sm font-medium text-rose-900">Permanently delete this DueItem?</p>
        <p class="mt-1 mb-3 text-sm text-rose-800">
          Its cycles, documents, notes, responsibility and reminders are deleted and cannot be
          recovered. The documents' storage is freed. Type
          <span class="font-semibold">{@item.title}</span>
          to confirm.
        </p>
        <div class="max-w-md">
          <.input field={@delete_form[:title]} aria-label="DueItem title" autocomplete="off" />
        </div>
        <div class="mb-3 flex gap-2">
          <.button id="confirm-delete" size="sm" variant="danger" phx-disable-with="Deleting…">
            Delete permanently
          </.button>
          <.button type="button" size="sm" variant="ghost" phx-click="close_panel">
            Cancel
          </.button>
        </div>
      </.form>

      <div class="grid gap-4 lg:grid-cols-3">
        <div class="space-y-4 lg:col-span-2">
          <.card id="due-item-dates" title="Dates">
            <:action :if={@control? and @live? and @panel != :override}>
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

          <.card id="due-item-documents" title="Documents">
            <:subtitle>
              {if @open_cycle?, do: "For the current cycle.", else: "No cycle is open."}
            </:subtitle>
            <:action :if={@can_upload? and @panel != :upload}>
              <.button
                id="upload-documents"
                size="sm"
                variant="outline"
                phx-click="open_panel"
                phx-value-panel="upload"
              >
                <.icon name="hero-arrow-up-tray" class="size-4" /> Upload
              </.button>
            </:action>

            <%= if @panel == :upload do %>
              <%= if @storage.left == 0 do %>
                <div
                  id="storage-full"
                  class="mb-5 rounded-md border border-amber-200/70 bg-amber-50/60 px-3.5 py-3 text-sm text-amber-900"
                >
                  <p>{storage_full_message(@current_scope, @storage)}</p>
                  <div class="mt-2 flex gap-3">
                    <.link
                      :if={Permissions.can_manage_billing?(@current_scope)}
                      navigate={~p"/account/plans"}
                      class="text-xs font-medium text-amber-900 underline underline-offset-2"
                    >
                      View Plans
                    </.link>
                    <button
                      type="button"
                      phx-click="close_panel"
                      class="text-xs font-medium text-amber-900/80 hover:text-amber-900"
                    >
                      Close
                    </button>
                  </div>
                </div>
              <% else %>
                <.form
                  for={@upload_form}
                  id="upload-form"
                  phx-change="validate_upload"
                  phx-submit="upload"
                  class="mb-5 rounded-md border border-line p-4"
                >
                  <fieldset class="mb-4">
                    <legend class="mb-2 text-[13px] font-medium text-zinc-600">Add as</legend>
                    <div class="grid gap-2 sm:grid-cols-2">
                      <label
                        :for={
                          {value, label, hint} <- [
                            {"current", "Current document",
                             "The licence, certificate or filing for this cycle."},
                            {"supporting", "Supporting document",
                             "Receipts, letters and anything else that belongs with it."}
                          ]
                        }
                        class="flex cursor-pointer items-start gap-2.5 rounded-md border border-line px-3 py-2.5 transition hover:bg-zinc-50 has-checked:border-navy/40 has-checked:bg-sky-50/40"
                      >
                        <input
                          type="radio"
                          id={"upload-role-#{value}"}
                          name="upload[role]"
                          value={value}
                          checked={@upload_form[:role].value == value}
                          class="mt-0.5 size-4 accent-navy"
                        />
                        <span>
                          <span class="block text-sm font-medium text-ink">{label}</span>
                          <span class="block text-xs text-muted">{hint}</span>
                        </span>
                      </label>
                    </div>
                  </fieldset>
                  <.document_dropzone
                    upload={@uploads.documents}
                    storage={@storage}
                    error={@upload_error}
                  />
                  <div class="mt-4 flex gap-2">
                    <.button
                      id="save-upload"
                      size="sm"
                      disabled={not uploadable?(@uploads.documents) or not is_nil(@upload_error)}
                      phx-disable-with="Uploading…"
                    >
                      Upload
                    </.button>
                    <.button type="button" size="sm" variant="ghost" phx-click="close_panel">
                      Cancel
                    </.button>
                  </div>
                </.form>
              <% end %>
            <% end %>

            <div class="space-y-5">
              <div>
                <p class="mb-1 text-xs font-medium tracking-wide text-muted uppercase">Current</p>
                <.document_list
                  id="documents-current"
                  documents={@current_documents}
                  removable={@removable}
                  tz={@tz}
                  empty="No current document yet."
                />
              </div>
              <div>
                <p class="mb-1 text-xs font-medium tracking-wide text-muted uppercase">
                  Supporting
                </p>
                <.document_list
                  id="documents-supporting"
                  documents={@supporting_documents}
                  removable={@removable}
                  tz={@tz}
                  empty="No supporting documents."
                />
              </div>
              <p :if={@cycles != []} class="text-xs text-muted">
                Documents from earlier cycles are kept under Previous cycles.
              </p>
            </div>
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

          <.card :if={@cycles != []} id="due-item-cycles" title="Previous cycles">
            <div id="cycles" class="-my-1 divide-y divide-line">
              <details :for={cycle <- @cycles} id={"cycle-#{cycle.id}"} class="group py-2.5">
                <summary class="flex cursor-pointer list-none items-center gap-3 text-sm">
                  <.icon
                    name="hero-chevron-right-mini"
                    class="size-4 shrink-0 text-zinc-400 transition group-open:rotate-90"
                  />
                  <span class="min-w-0 flex-1 truncate text-ink">
                    {cycle_label(cycle)}
                  </span>
                  <span class="shrink-0 text-xs text-muted">
                    {completion_verb(cycle)} {date(cycle.completed_on)}
                  </span>
                </summary>
                <dl class="mt-2 ml-7 grid gap-x-6 gap-y-1.5 text-xs sm:grid-cols-2">
                  <div>
                    <dt class="inline text-muted">Start:</dt>
                    <dd class="inline text-zinc-700">{date(cycle.start_date)}</dd>
                  </div>
                  <div>
                    <dt class="inline text-muted">Expiry:</dt>
                    <dd class="inline text-zinc-700">{date(cycle.expiry_date)}</dd>
                  </div>
                  <div>
                    <dt class="inline text-muted">{completion_verb(cycle)} by:</dt>
                    <dd class="inline text-zinc-700">{completed_by(cycle)}</dd>
                  </div>
                  <div :if={cycle.completion_type == "renewed"}>
                    <dt class="inline text-muted">Review:</dt>
                    <dd class="inline text-zinc-700">
                      {if cycle.reviewed_at, do: "Reviewed", else: "Not reviewed yet"}
                    </dd>
                  </div>
                  <div :if={cycle.completion_note} class="sm:col-span-2">
                    <dt class="text-muted">Note</dt>
                    <dd class="mt-0.5 whitespace-pre-line text-zinc-700">{cycle.completion_note}</dd>
                  </div>
                </dl>
                <div :if={cycle_documents(@documents_by_cycle, cycle) != []} class="mt-2 ml-7">
                  <p class="text-xs text-muted">Documents</p>
                  <.document_list
                    id={"cycle-documents-#{cycle.id}"}
                    documents={cycle_documents(@documents_by_cycle, cycle)}
                    removable={@removable}
                    tz={@tz}
                  />
                </div>
              </details>
            </div>
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
            <:action :if={@control? and @live? and @panel != :assign}>
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
                    :if={@control? and @live?}
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
         |> assign(:delete?, Permissions.can_delete_due_item?(scope))
         |> assign(:panel, nil)
         |> assign(:note_form, to_form(DueItems.change_note()))
         |> assign(:upload_form, upload_form("current"))
         |> assign(:upload_error, nil)
         |> allow_documents()
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

  def handle_event("open_panel", %{"panel" => "delete"}, socket) do
    if socket.assigns.delete? and socket.assigns.item.status == "archived" do
      {:noreply,
       socket
       |> assign(:panel, :delete)
       |> assign(:delete_form, to_form(%{"title" => ""}, as: :delete))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("open_panel", %{"panel" => "upload"}, socket) do
    if socket.assigns.can_upload? do
      {:noreply,
       socket
       |> assign(:panel, :upload)
       |> assign(:upload_form, upload_form("current"))
       |> assign(:upload_error, nil)
       |> refresh_storage()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_panel", _params, socket) do
    {:noreply, socket |> clear_selection() |> assign(:panel, nil)}
  end

  def handle_event("validate_upload", params, socket) do
    role = get_in(params, ["upload", "role"]) || socket.assigns.upload_form[:role].value

    {:noreply,
     socket
     |> assign(:upload_form, upload_form(role))
     |> then(&assign(&1, :upload_error, selection_error(&1)))}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    socket = cancel_document(socket, ref)
    {:noreply, assign(socket, :upload_error, selection_error(socket))}
  end

  def handle_event("upload", params, socket) do
    %{current_scope: scope, item: item} = socket.assigns
    role = get_in(params, ["upload", "role"]) || "current"

    with true <- documents_selected?(socket) || {:error, "Choose at least one file."},
         nil <- selection_error(socket),
         {:ok, uploads} <- consume_documents(socket) do
      case Documents.attach_documents(scope, item, role, uploads) do
        {:ok, documents} ->
          {:noreply,
           socket
           |> assign(:panel, nil)
           |> put_flash(:info, uploaded_message(documents))
           |> refresh_storage()
           |> reload()}

        {:error, {:limit_reached, info}} ->
          {:noreply,
           socket
           |> refresh_storage()
           |> assign(:upload_error, Billing.limit_message(scope, info))}

        {:error, :stale} ->
          {:noreply, socket |> assign(:panel, nil) |> put_flash(:error, @stale) |> reload()}

        {:error, _} ->
          {:noreply, not_available(socket)}
      end
    else
      {:error, message} -> {:noreply, assign(socket, :upload_error, message)}
      message when is_binary(message) -> {:noreply, assign(socket, :upload_error, message)}
    end
  end

  def handle_event("remove_document", %{"id" => id}, socket) do
    case Documents.delete_document(socket.assigns.current_scope, %Document{id: id}) do
      {:ok, document} ->
        {:noreply,
         socket
         |> put_flash(:info, "Removed “#{document.filename}”.")
         |> refresh_storage()
         |> reload()}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "This document can no longer be removed.")
         |> reload()}
    end
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

  def handle_event("delete", %{"delete" => %{"title" => title}}, socket) do
    %{current_scope: scope, item: item} = socket.assigns

    case DueItems.delete_due_item(scope, item, title) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "DueItem permanently deleted.")
         |> push_navigate(to: ~p"/due-items?view=archived")}

      {:error, :confirmation_mismatch} ->
        {:noreply,
         assign(
           socket,
           :delete_form,
           to_form(%{"title" => title},
             as: :delete,
             errors: [title: {"type the title exactly as shown", []}],
             action: :validate
           )
         )}

      {:error, :not_archived} ->
        {:noreply, socket |> assign(:panel, nil) |> reload()}

      {:error, _} ->
        {:noreply, not_available(socket)}
    end
  end

  def handle_event("dismiss_review", %{"id" => cycle_id}, socket) do
    case DueItems.dismiss_renewal_review(socket.assigns.current_scope, cycle_id) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Renewal marked as reviewed.") |> reload()}

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

    cycles = DueItems.list_cycles(scope, item)
    documents = Documents.list_documents(scope, item)
    open_cycle_id = if cycle && not Cycle.closed?(cycle), do: cycle.id
    open_documents = Enum.filter(documents, &(&1.cycle_id == open_cycle_id))

    socket
    |> assign(:page_title, item.title)
    |> assign(:item, item)
    |> assign(:cycle, cycle)
    |> assign(:can_act?, Permissions.can_act_on_due_item?(scope, item))
    |> assign(:recurring?, Recurrence.recurring?(item))
    |> assign(:awaiting, disposition_status(item))
    |> assign(:live?, item.status == "active" and is_nil(item.disposition_state))
    |> assign(:cycles, cycles)
    |> assign(:can_upload?, Permissions.can_upload_document?(scope, item))
    |> assign(:open_cycle?, not is_nil(open_cycle_id))
    |> assign(:current_documents, Enum.filter(open_documents, &(&1.role == "current")))
    |> assign(:supporting_documents, Enum.reject(open_documents, &(&1.role == "current")))
    |> assign(:documents_by_cycle, Enum.group_by(documents, & &1.cycle_id))
    |> assign(
      :removable,
      for(
        doc <- documents,
        Permissions.can_delete_document?(scope, item, doc),
        into: MapSet.new(),
        do: doc.id
      )
    )
    |> assign(
      :pending_review,
      Enum.find(cycles, &(&1.completion_type == "renewed" and is_nil(&1.reviewed_at)))
    )
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

  defp upload_form(role), do: to_form(%{"role" => role}, as: :upload)

  defp clear_selection(socket) do
    socket.assigns.uploads.documents.entries
    |> Enum.reduce(socket, &cancel_document(&2, &1.ref))
    |> assign(:upload_error, nil)
  end

  defp cycle_documents(_by_cycle, nil), do: []
  defp cycle_documents(by_cycle, %Cycle{id: id}), do: Map.get(by_cycle, id, [])

  defp storage_full_message(scope, storage) do
    Billing.limit_message(scope, %{
      plan: Billing.plan(scope),
      limit: storage.limit,
      resource: :storage,
      used: storage.used
    })
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

  defp awaiting_message(:needs_dates, cycle) do
    "Renewed by #{completed_by(cycle)} on #{date(cycle.completed_on)}. Set the next dates to make it active again."
  end

  defp awaiting_message(:awaiting, cycle) do
    "Completed on #{date(cycle.completed_on)} by #{completed_by(cycle)}. Decide what happens next: archive it, or re-date it and make it active again."
  end

  defp completed_by(%Cycle{completed_by_user: %{name: name}}), do: name
  defp completed_by(_cycle), do: "a former member"

  defp completion_verb(%Cycle{completion_type: "renewed"}), do: "Renewed"
  defp completion_verb(%Cycle{}), do: "Completed"

  defp cycle_label(%Cycle{} = cycle) do
    dates =
      cond do
        cycle.due_date -> "Due #{date(cycle.due_date)}"
        cycle.expiry_date -> "Expired #{date(cycle.expiry_date)}"
        true -> "No dates"
      end

    "Cycle #{cycle.sequence} · #{dates}"
  end

  defp has_details?(item),
    do: Enum.any?([item.reference_number, item.related_party, item.description])

  defp author_name(%{author_user: %{name: name}}), do: name
  defp author_name(_), do: "A former member"

  defp days_note(%DueItem{status: "active", disposition_state: nil}, %Cycle{} = cycle, today) do
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

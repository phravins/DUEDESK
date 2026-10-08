defmodule DueDeskWeb.DueItemLive.Complete do
  @moduledoc """
  Mark a DueItem that does not repeat as completed (UX spec §45). It then
  leaves Users' lists and waits for an Administrator to archive it or
  re-date and reactivate it.

  Anyone who can see the DueItem may complete it while it is active; the
  context checks the same.
  """
  use DueDeskWeb, :live_view

  alias DueDesk.{DueItems, Permissions}
  alias DueDesk.DueItems.Recurrence

  @not_available "This DueItem is not available to your account access."
  @stale "This DueItem has already been updated. Refresh to see the latest."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:due_items}>
      <.page_header eyebrow="DueItems" icon="hero-clipboard-document-list" title="Mark as completed">
        <:subtitle>{@item.title}</:subtitle>
      </.page_header>

      <div class="max-w-3xl">
        <.form for={@form} id="complete-form" phx-change="validate" phx-submit="save">
          <div class="space-y-4">
            <div
              id="complete-notice"
              class="flex items-start gap-2.5 rounded-lg border border-line bg-[#f6f6f4] px-4 py-3 text-sm text-zinc-600"
            >
              <.icon name="hero-information-circle" class="mt-px size-5 shrink-0 text-zinc-400" />
              <span>
                This DueItem will leave your active DueItems after completion. An Administrator
                will decide whether to archive or re-date it.
              </span>
            </div>

            <.card id="completion-details" title="Completion">
              <:subtitle>
                Due {date(@item.current_cycle.due_date)} · Expires {date(
                  @item.current_cycle.expiry_date
                )}
              </:subtitle>
              <div class="grid gap-x-4 sm:grid-cols-3">
                <.input field={@form[:completed_on]} type="date" label="Completed on" />
              </div>
              <.input
                field={@form[:note]}
                type="textarea"
                label="Note"
                placeholder="Optional. What was done and anything an Administrator should know."
                maxlength="2000"
                phx-debounce="300"
              />
            </.card>

            <div class="flex items-start gap-2.5 rounded-lg border border-dashed border-zinc-300 px-4 py-3 text-sm text-zinc-500">
              <.icon name="hero-paper-clip" class="mt-px size-5 shrink-0 text-zinc-400" />
              <span>Attaching documents to a completion arrives in an upcoming release.</span>
            </div>

            <div class="flex flex-wrap items-center gap-2 pt-1">
              <.button id="save-completion" phx-disable-with="Saving…">
                <.icon name="hero-check" class="size-4" /> Mark as completed
              </.button>
              <.button variant="ghost" navigate={~p"/due-items/#{@item}"}>Cancel</.button>
            </div>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with {:ok, item} <- DueItems.get_due_item(scope, id),
         true <- Permissions.can_act_on_due_item?(scope, item) do
      if Recurrence.recurring?(item) do
        {:ok, push_navigate(socket, to: ~p"/due-items/#{item}/renew")}
      else
        {:ok,
         socket
         |> assign(:page_title, "Complete #{item.title}")
         |> assign(:item, item)
         |> assign(:form, to_form(DueItems.change_completion(scope, item)))}
      end
    else
      _ -> {:ok, not_available(socket)}
    end
  end

  @impl true
  def handle_event("validate", %{"completion" => params}, socket) do
    %{current_scope: scope, item: item} = socket.assigns
    changeset = DueItems.change_completion(scope, item, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"completion" => params}, socket) do
    %{current_scope: scope, item: item} = socket.assigns

    case DueItems.complete_due_item(scope, item, params) do
      {:ok, completed} ->
        to =
          if Permissions.can_manage_due_items?(scope),
            do: ~p"/due-items/#{completed}",
            else: ~p"/due-items"

        {:noreply, socket |> put_flash(:info, "DueItem completed.") |> push_navigate(to: to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}

      {:error, :stale} ->
        {:noreply,
         socket
         |> put_flash(:error, @stale)
         |> push_navigate(to: ~p"/due-items/#{item}")}

      {:error, _} ->
        {:noreply, not_available(socket)}
    end
  end

  defp not_available(socket) do
    socket
    |> put_flash(:error, @not_available)
    |> push_navigate(to: ~p"/due-items")
  end
end

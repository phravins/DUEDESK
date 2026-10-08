defmodule DueDeskWeb.DueItemLive.Renew do
  @moduledoc """
  Renew a recurring DueItem (UX spec §40): record when it was done, see
  the next cycle's dates, and start that cycle. When the next date is set
  at each renewal, the dates are entered here, or left for an
  Administrator.

  Anyone who can see the DueItem may renew it while it is active; the
  context checks the same.
  """
  use DueDeskWeb, :live_view

  alias DueDesk.{DueItems, Permissions}
  alias DueDesk.DueItems.{DueItem, Recurrence}

  @not_available "This DueItem is not available to your account access."
  @stale "This DueItem has already been updated. Refresh to see the latest."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:due_items}>
      <.page_header eyebrow="DueItems" icon="hero-clipboard-document-list" title="Renew">
        <:subtitle>{@item.title} · {Recurrence.describe(@item)}</:subtitle>
      </.page_header>

      <div class="max-w-3xl">
        <.form for={@form} id="renew-form" phx-change="validate" phx-submit="save">
          <div class="space-y-4">
            <.card id="current-cycle" title="This cycle">
              <.cycle_dates cycle={@item.current_cycle} />
            </.card>

            <.card id="next-cycle" title="Next cycle">
              <:subtitle>
                {if @explicit?,
                  do: "Leave blank and an Administrator will set the dates.",
                  else: "Worked out from this cycle's dates."}
              </:subtitle>
              <%= if @explicit? do %>
                <div class="grid gap-x-4 sm:grid-cols-3">
                  <.input field={@form[:next_due_date]} type="date" label="Next Due Date" />
                  <.input field={@form[:next_expiry_date]} type="date" label="Next Expiry Date" />
                  <.input
                    field={@form[:next_start_date]}
                    type="date"
                    label="Next Start Date"
                    hint="Optional."
                  />
                </div>
              <% else %>
                <div id="next-dates">
                  <.cycle_dates cycle={@next} highlight />
                </div>
              <% end %>
            </.card>

            <.card id="renewal-details" title="Renewal">
              <div class="grid gap-x-4 sm:grid-cols-3">
                <.input field={@form[:completed_on]} type="date" label="Renewed on" />
              </div>
              <.input
                field={@form[:note]}
                type="textarea"
                label="Note"
                placeholder="Optional. Receipt number, what was filed, anything useful next time."
                maxlength="2000"
                phx-debounce="300"
              />
            </.card>

            <div class="flex items-start gap-2.5 rounded-lg border border-dashed border-zinc-300 px-4 py-3 text-sm text-zinc-500">
              <.icon name="hero-paper-clip" class="mt-px size-5 shrink-0 text-zinc-400" />
              <span>Attaching documents to a renewal arrives in an upcoming release.</span>
            </div>

            <div class="flex flex-wrap items-center gap-2 pt-1">
              <.button id="save-renewal" phx-disable-with="Recording…">
                <.icon name="hero-arrow-path" class="size-4" /> Record renewal
              </.button>
              <.button variant="ghost" navigate={~p"/due-items/#{@item}"}>Cancel</.button>
            </div>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  attr :cycle, :map, required: true
  attr :highlight, :boolean, default: false

  defp cycle_dates(assigns) do
    ~H"""
    <div class="grid gap-4 sm:grid-cols-3">
      <div
        :for={
          {label, key} <- [
            {"Due Date", :due_date},
            {"Expiry Date", :expiry_date},
            {"Start Date", :start_date}
          ]
        }
        class={[
          "rounded-md px-3.5 py-3",
          if(@highlight,
            do: "bg-emerald-50/70 ring-1 ring-inset ring-emerald-200/70",
            else: "bg-[#f6f6f4]"
          )
        ]}
      >
        <p class="text-xs text-muted">{if @highlight, do: "Next #{label}", else: label}</p>
        <p class="mt-0.5 text-base font-semibold text-ink">{date(Map.get(@cycle, key))}</p>
      </div>
    </div>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with {:ok, item} <- DueItems.get_due_item(scope, id),
         true <- Permissions.can_act_on_due_item?(scope, item) do
      if Recurrence.recurring?(item) do
        {:ok,
         socket
         |> assign(:page_title, "Renew #{item.title}")
         |> assign(:item, item)
         |> assign(:explicit?, Recurrence.interval(item) == :explicit)
         |> assign(:next, next_dates(scope, item))
         |> assign(:form, to_form(DueItems.change_completion(scope, item)))}
      else
        {:ok, push_navigate(socket, to: ~p"/due-items/#{item}/complete")}
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

    case DueItems.renew_due_item(scope, item, params) do
      {:ok, %DueItem{disposition_state: "awaiting_new_dates"} = renewed} ->
        if Permissions.can_manage_due_items?(scope) do
          {:noreply,
           socket
           |> put_flash(:info, "Renewal recorded. Set the next dates to make it active again.")
           |> push_navigate(to: ~p"/due-items/#{renewed}")}
        else
          {:noreply,
           socket
           |> put_flash(:info, "Renewal recorded. An Administrator will set the next dates.")
           |> push_navigate(to: ~p"/due-items")}
        end

      {:ok, renewed} ->
        {:noreply,
         socket
         |> put_flash(:info, "Renewal recorded. The next cycle has been created.")
         |> push_navigate(to: ~p"/due-items/#{renewed}")}

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

  defp next_dates(scope, item) do
    case DueItems.next_dates(scope, item) do
      {:ok, dates} -> dates
      _ -> %{start_date: nil, due_date: nil, expiry_date: nil}
    end
  end

  defp not_available(socket) do
    socket
    |> put_flash(:error, @not_available)
    |> push_navigate(to: ~p"/due-items")
  end
end

defmodule DueDeskWeb.DueItemLive.Reactivate do
  @moduledoc """
  Make an inactive DueItem active again (UX spec §50): re-date and
  reactivate one that was completed, set new dates for one renewed
  without them, or restore an archived one. Dates, responsibility and
  reminders are reviewed first. Administrators and Super Admins only.

  Restoring an archived DueItem needs room in the plan; at the limit the
  form is replaced by the limit notice.
  """
  use DueDeskWeb, :live_view

  import DueDeskWeb.DueItemFormComponents

  alias DueDesk.{Billing, DueItems, Permissions}
  alias DueDesk.DueItems.{Cycle, DueItem}

  @not_available "This DueItem is not available to your account access."
  @stale "This DueItem has already been updated. Refresh to see the latest."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:due_items}>
      <.page_header eyebrow="DueItems" icon="hero-clipboard-document-list" title={@page_title}>
        <:subtitle>{@item.title}</:subtitle>
      </.page_header>

      <div class="max-w-3xl">
        <%= if @limit_message do %>
          <.limit_notice message={@limit_message} plans_link={@plans_link?} />
          <.button variant="secondary" navigate={~p"/due-items/#{@item}"}>
            <.icon name="hero-arrow-left-mini" class="size-4" /> Back to DueItem
          </.button>
        <% else %>
          <.form for={@form} id="reactivate-form" phx-change="validate" phx-submit="save">
            <div class="space-y-4">
              <div
                id="reactivate-notice"
                class="flex items-start gap-2.5 rounded-lg border border-line bg-[#f6f6f4] px-4 py-3 text-sm text-zinc-600"
              >
                <.icon name="hero-information-circle" class="mt-px size-5 shrink-0 text-zinc-400" />
                <span>
                  Check the dates, responsibility and reminders before this DueItem becomes
                  active again.
                </span>
              </div>

              <.dates_section form={@form} both_dates?={@both_dates?} subtitle={@dates_subtitle} />

              <.responsibility_section
                form={@form}
                member_options={@member_options}
                primary_id={@primary_id}
                primary_selected?={@primary_selected?}
                additional_ids={@additional_ids}
              />

              <.reminders_section
                form={@form}
                reminder_choices={@reminder_choices}
                offsets={@offsets}
                custom={@custom}
                custom_error={@custom_error}
              />

              <div class="flex flex-wrap items-center gap-2 pt-1">
                <.button id="save-reactivation" phx-disable-with="Saving…">
                  {@submit_label}
                </.button>
                <.button variant="ghost" navigate={~p"/due-items/#{@item}"}>Cancel</.button>
              </div>
            </div>
          </.form>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with true <- Permissions.can_manage_due_items?(scope),
         {:ok, item} <- DueItems.get_due_item(scope, id),
         true <- inactive?(item) do
      item = DueItems.prepare_reactivate(item)
      {title, submit} = labels(item)

      socket =
        socket
        |> assign(:page_title, title)
        |> assign(:submit_label, submit)
        |> assign(:item, item)
        |> assign(:dates_subtitle, dates_subtitle(item.current_cycle))
        |> assign(:member_options, member_options(scope))
        |> assign(:params, %{})
        |> assign(:custom, %{"days" => nil, "direction" => "before"})
        |> assign(:custom_error, nil)
        |> assign(:extra_offsets, [])
        |> assign(:limit_message, nil)
        |> assign(:plans_link?, false)
        |> assign_form(DueItems.change_reactivation(scope, item))

      {:ok, check_limit(socket)}
    else
      _ -> {:ok, not_available(socket)}
    end
  end

  @impl true
  def handle_event("validate", %{"due_item" => params} = all, socket) do
    %{current_scope: scope, item: item} = socket.assigns

    {:noreply,
     socket
     |> assign(:params, params)
     |> assign(:custom, Map.get(all, "custom_reminder", socket.assigns.custom))
     |> assign_form(DueItems.change_reactivation(scope, item, params), :validate)}
  end

  def handle_event("add_reminder", _params, socket) do
    %{current_scope: scope, item: item, custom: custom, offsets: offsets} = socket.assigns

    case parse_custom_reminder(custom) do
      {:ok, offset} ->
        params =
          Map.put(
            socket.assigns.params,
            "reminder_offsets",
            Enum.map(Enum.uniq(offsets ++ [offset]), &to_string/1)
          )

        {:noreply,
         socket
         |> assign(:params, params)
         |> update(:extra_offsets, &Enum.uniq([offset | &1]))
         |> assign(:custom, %{"days" => nil, "direction" => custom["direction"]})
         |> assign(:custom_error, nil)
         |> assign_form(DueItems.change_reactivation(scope, item, params))}

      :error ->
        {:noreply, assign(socket, :custom_error, custom_reminder_error())}
    end
  end

  def handle_event("save", %{"due_item" => params}, socket) do
    %{current_scope: scope, item: item} = socket.assigns

    case DueItems.reactivate_due_item(scope, item, params) do
      {:ok, _} ->
        message =
          if item.status == "archived", do: "DueItem restored.", else: "DueItem reactivated."

        {:noreply,
         socket
         |> put_flash(:info, message)
         |> push_navigate(to: ~p"/due-items/#{item}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset, :validate)}

      {:error, {:limit_reached, info}} ->
        {:noreply, limit_reached(socket, info)}

      {:error, reason} when reason in [:stale, :not_inactive] ->
        {:noreply,
         socket
         |> put_flash(:error, @stale)
         |> push_navigate(to: ~p"/due-items/#{item}")}

      {:error, _} ->
        {:noreply, not_available(socket)}
    end
  end

  defp assign_form(socket, changeset, action \\ nil) do
    changeset = if action, do: Map.put(changeset, :action, action), else: changeset
    assign_due_item_form(socket, changeset, socket.assigns.extra_offsets)
  end

  # Awaiting items already count toward the plan; archived ones do not.
  defp check_limit(%{assigns: %{item: %DueItem{status: "archived"}}} = socket) do
    case Billing.check(socket.assigns.current_scope, :due_item) do
      :ok -> socket
      {:error, {:limit_reached, info}} -> limit_reached(socket, info)
    end
  end

  defp check_limit(socket), do: socket

  defp limit_reached(socket, info) do
    scope = socket.assigns.current_scope

    socket
    |> assign(:limit_message, Billing.limit_message(scope, info))
    |> assign(:plans_link?, Permissions.can_manage_billing?(scope))
  end

  defp inactive?(%DueItem{status: "archived"}), do: true
  defp inactive?(%DueItem{disposition_state: state}), do: is_binary(state)

  defp labels(%DueItem{status: "archived"}), do: {"Restore DueItem", "Restore DueItem"}

  defp labels(%DueItem{disposition_state: "awaiting_new_dates"}),
    do: {"Set new dates", "Save and reactivate"}

  defp labels(%DueItem{}), do: {"Re-date and reactivate", "Reactivate DueItem"}

  defp dates_subtitle(%Cycle{} = cycle) do
    if Cycle.closed?(cycle) do
      previous =
        cond do
          cycle.due_date -> "The last Due Date was #{date(cycle.due_date)}. "
          cycle.expiry_date -> "The last Expiry Date was #{date(cycle.expiry_date)}. "
          true -> ""
        end

      previous <> "Enter the dates for the new cycle."
    else
      "Enter a Due Date, an Expiry Date, or both."
    end
  end

  defp dates_subtitle(_), do: "Enter a Due Date, an Expiry Date, or both."

  defp member_options(scope) do
    scope
    |> DueItems.assignable_members()
    |> Enum.map(&{&1.user.name, &1.user.id})
  end

  defp not_available(socket) do
    socket
    |> put_flash(:error, @not_available)
    |> push_navigate(to: ~p"/due-items")
  end
end

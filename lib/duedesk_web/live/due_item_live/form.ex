defmodule DueDeskWeb.DueItemLive.Form do
  @moduledoc """
  Create a DueItem (any member) or edit one (Administrators and Super
  Admins), per UX spec §30.

  Administrators see every section: Basic, Dates, Responsibility,
  Recurrence and Reminders. Users see Basic and Dates only; they become
  Primary Responsible and the default reminders apply. The context
  enforces the same split, so hiding sections is only presentation.
  """
  use DueDeskWeb, :live_view

  alias DueDesk.{Billing, Categories, DueItems, Organisations, Permissions}
  alias DueDesk.DueItems.{DueItem, Recurrence, ReminderRule}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:due_items}>
      <.page_header eyebrow="DueItems" icon="hero-clipboard-document-list" title={@page_title}>
        <:subtitle :if={@live_action == :edit}>{@item.title}</:subtitle>
      </.page_header>

      <div class="max-w-3xl">
        <%= cond do %>
          <% @limit_message -> %>
            <.limit_notice message={@limit_message} plans_link={@plans_link?} />
            <.button variant="secondary" navigate={~p"/due-items"}>
              <.icon name="hero-arrow-left-mini" class="size-4" /> Back to DueItems
            </.button>
          <% @organisation_options == [] -> %>
            <.empty_state
              id="no-organisations"
              icon="hero-building-office-2"
              title="Add an Organisation first"
            >
              <%= if @control? do %>
                Every DueItem belongs to one of your Organisations.
              <% else %>
                Every DueItem belongs to an Organisation. Ask an Administrator to add one.
              <% end %>
              <:action :if={@control?}>
                <.button navigate={~p"/organisations/new"}>
                  <.icon name="hero-plus" class="size-4" /> Add Organisation
                </.button>
              </:action>
            </.empty_state>
          <% true -> %>
            <.form for={@form} id="due-item-form" phx-change="validate" phx-submit="save">
              <div class="space-y-4">
                <.card id="section-basic" title="Basic details">
                  <.input
                    field={@form[:title]}
                    label="Title"
                    placeholder="e.g. Trade Licence renewal"
                    maxlength="160"
                    phx-debounce="300"
                  />
                  <div class="grid gap-x-4 sm:grid-cols-2">
                    <.input
                      field={@form[:organisation_id]}
                      type="select"
                      label="Organisation"
                      prompt="Choose an Organisation"
                      options={@organisation_options}
                    />
                    <.input
                      field={@form[:category_id]}
                      type="select"
                      label="Category"
                      prompt="Choose a category"
                      options={@category_options}
                    />
                    <.input
                      field={@form[:reference_number]}
                      label="Reference Number"
                      hint="Optional. Licence, policy or registration number."
                      phx-debounce="300"
                    />
                    <.input
                      :if={@control?}
                      field={@form[:related_party]}
                      label="Related Party"
                      hint="Optional. The authority, insurer or landlord."
                      phx-debounce="300"
                    />
                  </div>
                  <.input
                    field={@form[:description]}
                    type="textarea"
                    label="Description"
                    placeholder="Optional. What needs doing, and anything useful to know."
                    phx-debounce="300"
                  />
                </.card>

                <.card id="section-dates" title="Dates">
                  <:subtitle>Enter a Due Date, an Expiry Date, or both.</:subtitle>
                  <div class="grid gap-x-4 sm:grid-cols-3">
                    <.input field={@form[:due_date]} type="date" label="Due Date" />
                    <.input field={@form[:expiry_date]} type="date" label="Expiry Date" />
                    <.input
                      field={@form[:start_date]}
                      type="date"
                      label="Start Date"
                      hint="Optional."
                    />
                  </div>
                  <p
                    :if={@both_dates?}
                    id="dates-hint"
                    class="flex items-start gap-2 rounded-md bg-[#f6f6f4] px-3 py-2.5 text-xs text-zinc-600"
                  >
                    <.icon name="hero-information-circle-mini" class="mt-px size-4 shrink-0" />
                    Due Date controls operational status. Expiry Date records the actual expiry.
                  </p>
                </.card>

                <.card
                  :if={@control? and @live_action == :new}
                  id="section-responsibility"
                  title="Responsibility"
                >
                  <:subtitle>
                    The Primary Responsible gets reminders and keeps it up to date. Leave it
                    empty to assign later.
                  </:subtitle>
                  <.input
                    field={@form[:primary_user_id]}
                    type="select"
                    label="Primary Responsible"
                    prompt="Unassigned"
                    options={@member_options}
                  />
                  <fieldset :if={@primary_selected?} id="additional-assignees">
                    <legend class="mb-2 text-[13px] font-medium text-zinc-600">
                      Additional Assignees <span class="font-normal text-zinc-400">(optional)</span>
                    </legend>
                    <input type="hidden" name={@form[:additional_user_ids].name <> "[]"} value="" />
                    <div class="grid gap-x-4 gap-y-2 sm:grid-cols-2">
                      <label
                        :for={{name, id} <- @member_options}
                        :if={id != @primary_id}
                        class="inline-flex cursor-pointer items-center gap-2.5 text-sm text-zinc-700"
                      >
                        <input
                          type="checkbox"
                          id={"additional-#{id}"}
                          name={@form[:additional_user_ids].name <> "[]"}
                          value={id}
                          checked={id in @additional_ids}
                          class="size-4 rounded border-zinc-300 accent-navy"
                        />
                        {name}
                      </label>
                    </div>
                  </fieldset>
                </.card>

                <.card :if={@control?} id="section-recurrence" title="Recurrence">
                  <:subtitle>How often this comes round again. Used when it is renewed.</:subtitle>
                  <div class="grid gap-x-4 sm:grid-cols-3">
                    <.input
                      field={@form[:recurrence]}
                      type="select"
                      label="Repeats"
                      options={Recurrence.options()}
                    />
                    <.input
                      :if={@recurrence == "custom"}
                      field={@form[:recurrence_unit]}
                      type="select"
                      label="Unit"
                      prompt="Choose"
                      options={Recurrence.unit_options()}
                    />
                    <.input
                      :if={@recurrence == "custom" and @recurrence_unit in ["day", "month"]}
                      field={@form[:recurrence_interval]}
                      type="number"
                      label={"Every how many #{@recurrence_unit}s"}
                      min="1"
                      max="3650"
                    />
                  </div>
                </.card>

                <.card :if={@control?} id="section-reminders" title="Reminders">
                  <:subtitle>
                    Sent to the people responsible, counted from the Due Date (or the Expiry
                    Date when there is no Due Date).
                  </:subtitle>
                  <input type="hidden" name={@form[:reminder_offsets].name <> "[]"} value="" />
                  <div class="grid gap-x-4 gap-y-2.5 sm:grid-cols-2">
                    <label
                      :for={offset <- @reminder_choices}
                      class="inline-flex cursor-pointer items-center gap-2.5 text-sm text-zinc-700"
                    >
                      <input
                        type="checkbox"
                        id={"reminder-#{offset}"}
                        name={@form[:reminder_offsets].name <> "[]"}
                        value={offset}
                        checked={offset in @offsets}
                        class="size-4 rounded border-zinc-300 accent-navy"
                      />
                      {ReminderRule.describe(offset)}
                    </label>
                  </div>
                  <p
                    :for={msg <- Enum.map(@form[:reminder_offsets].errors, &translate_error/1)}
                    class="mt-2 text-xs text-rose-600"
                  >
                    {msg}
                  </p>

                  <div class="mt-5 border-t border-line pt-4">
                    <p class="mb-2 text-[13px] font-medium text-zinc-600">Add Custom Reminder</p>
                    <div class="flex flex-wrap items-start gap-2">
                      <div class="w-24">
                        <.input
                          id="custom-reminder-days"
                          name="custom_reminder[days]"
                          type="number"
                          value={@custom["days"]}
                          min="1"
                          max={ReminderRule.max_days()}
                          placeholder="Days"
                          aria-label="Days"
                        />
                      </div>
                      <div class="w-36">
                        <.input
                          id="custom-reminder-direction"
                          name="custom_reminder[direction]"
                          type="select"
                          value={@custom["direction"]}
                          options={[{"days before", "before"}, {"days after", "after"}]}
                          aria-label="Before or after"
                        />
                      </div>
                      <.button
                        id="add-reminder"
                        type="button"
                        variant="secondary"
                        phx-click="add_reminder"
                      >
                        <.icon name="hero-plus-mini" class="size-4" /> Add
                      </.button>
                    </div>
                    <p :if={@custom_error} id="custom-reminder-error" class="text-xs text-rose-600">
                      {@custom_error}
                    </p>
                  </div>
                </.card>

                <div
                  :if={!@control?}
                  id="user-create-note"
                  class="flex items-start gap-2.5 rounded-lg border border-line bg-white px-4 py-3 text-sm text-zinc-600"
                >
                  <.icon name="hero-user-circle" class="mt-px size-5 shrink-0 text-zinc-400" />
                  <span>
                    You will be the Primary Responsible. Reminders go out 90, 30 and 7 days
                    before, on the Due Date and a day after. An Administrator can change this.
                  </span>
                </div>

                <div
                  :if={@live_action == :new}
                  class="flex items-start gap-2.5 rounded-lg border border-dashed border-zinc-300 px-4 py-3 text-sm text-zinc-500"
                >
                  <.icon name="hero-paper-clip" class="mt-px size-5 shrink-0 text-zinc-400" />
                  <span>Documents can be attached after you save this DueItem.</span>
                </div>

                <div class="flex flex-wrap items-center gap-2 pt-1">
                  <.button id="save-due-item" phx-disable-with="Saving…">
                    {if @live_action == :new, do: "Create DueItem", else: "Save changes"}
                  </.button>
                  <.button variant="ghost" navigate={@return_to}>Cancel</.button>
                </div>
              </div>
            </.form>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    scope = socket.assigns.current_scope

    socket =
      socket
      |> assign(:control?, Permissions.can_manage_due_items?(scope))
      |> assign(:limit_message, nil)
      |> assign(:plans_link?, false)
      |> assign(:custom, %{"days" => nil, "direction" => "before"})
      |> assign(:custom_error, nil)
      |> assign(:extra_offsets, [])

    case apply_action(socket, socket.assigns.live_action, params) do
      {:ok, socket} -> {:ok, socket}
      {:error, socket} -> {:ok, socket}
    end
  end

  defp apply_action(socket, :new, _params) do
    scope = socket.assigns.current_scope
    item = DueItems.new_due_item()

    socket =
      socket
      |> assign(:page_title, "New DueItem")
      |> assign(:item, item)
      |> assign(:return_to, ~p"/due-items")
      |> assign_options(item)
      |> assign(:params, %{})
      |> assign_form(DueItems.change_new_due_item(scope, item))

    case Billing.check(scope, :due_item) do
      :ok ->
        {:ok, socket}

      {:error, {:limit_reached, info}} ->
        {:ok,
         socket
         |> assign(:limit_message, Billing.limit_message(scope, info))
         |> assign(:plans_link?, Permissions.can_manage_billing?(scope))}
    end
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    scope = socket.assigns.current_scope

    with true <- socket.assigns.control?,
         {:ok, item} <- DueItems.get_due_item(scope, id) do
      item = DueItems.prepare_edit(item)

      {:ok,
       socket
       |> assign(:page_title, "Edit DueItem")
       |> assign(:item, item)
       |> assign(:return_to, ~p"/due-items/#{item}")
       |> assign_options(item)
       |> assign(:params, %{})
       |> assign_form(DueItems.change_due_item(item))}
    else
      _ ->
        {:error,
         socket
         |> put_flash(:error, "This DueItem is not available to your account access.")
         |> push_navigate(to: ~p"/due-items")}
    end
  end

  @impl true
  def handle_event("validate", %{"due_item" => params} = all, socket) do
    socket =
      socket
      |> assign(:params, params)
      |> assign(:custom, Map.get(all, "custom_reminder", socket.assigns.custom))
      |> assign_form(changeset(socket, params), :validate)

    {:noreply, socket}
  end

  def handle_event("add_reminder", _params, socket) do
    %{custom: custom, offsets: offsets} = socket.assigns

    case parse_offset(custom) do
      {:ok, offset} ->
        params =
          socket.assigns.params
          |> Map.put("reminder_offsets", Enum.map(Enum.uniq(offsets ++ [offset]), &to_string/1))

        {:noreply,
         socket
         |> assign(:params, params)
         |> update(:extra_offsets, &Enum.uniq([offset | &1]))
         |> assign(:custom, %{"days" => nil, "direction" => custom["direction"]})
         |> assign(:custom_error, nil)
         |> assign_form(changeset(socket, params))}

      :error ->
        {:noreply,
         assign(
           socket,
           :custom_error,
           "Enter a number of days from 1 to #{ReminderRule.max_days()}."
         )}
    end
  end

  def handle_event("save", %{"due_item" => params}, socket) do
    save(socket, socket.assigns.live_action, params)
  end

  defp save(socket, :new, params) do
    scope = socket.assigns.current_scope

    case DueItems.create_due_item(scope, params) do
      {:ok, item} ->
        {:noreply,
         socket
         |> put_flash(:info, "DueItem created.")
         |> push_navigate(to: ~p"/due-items/#{item}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, {:limit_reached, info}} ->
        {:noreply,
         socket
         |> assign(:limit_message, Billing.limit_message(scope, info))
         |> assign(:plans_link?, Permissions.can_manage_billing?(scope))}

      {:error, :unauthorized} ->
        {:noreply, not_available(socket)}
    end
  end

  defp save(socket, :edit, params) do
    %{current_scope: scope, item: item} = socket.assigns

    case DueItems.update_due_item(scope, item, params) do
      {:ok, _item} ->
        {:noreply,
         socket
         |> put_flash(:info, "DueItem updated.")
         |> push_navigate(to: ~p"/due-items/#{item}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, :unauthorized} ->
        {:noreply, not_available(socket)}
    end
  end

  defp not_available(socket) do
    socket
    |> put_flash(:error, "This DueItem is not available to your account access.")
    |> push_navigate(to: ~p"/due-items")
  end

  defp changeset(socket, params) do
    %{current_scope: scope, item: item, live_action: action} = socket.assigns

    case action do
      :new -> DueItems.change_new_due_item(scope, item, params)
      :edit -> DueItems.change_due_item(item, params)
    end
  end

  defp assign_form(socket, changeset, action \\ nil) do
    changeset = if action, do: Map.put(changeset, :action, action), else: changeset
    get = &Ecto.Changeset.get_field(changeset, &1)
    offsets = List.wrap(get.(:reminder_offsets))
    primary_id = get.(:primary_user_id)

    socket
    |> assign(:form, to_form(changeset))
    |> assign(:both_dates?, not is_nil(get.(:due_date)) and not is_nil(get.(:expiry_date)))
    |> assign(:recurrence, get.(:recurrence))
    |> assign(:recurrence_unit, get.(:recurrence_unit))
    |> assign(:primary_id, primary_id)
    |> assign(:primary_selected?, not is_nil(primary_id))
    |> assign(:additional_ids, List.wrap(get.(:additional_user_ids)))
    |> assign(:offsets, offsets)
    |> assign(
      :reminder_choices,
      Enum.sort(Enum.uniq(ReminderRule.defaults() ++ offsets ++ socket.assigns.extra_offsets))
    )
  end

  # Active Organisations and categories, plus the item's own when it was
  # archived since, so editing keeps the current value.
  defp assign_options(socket, %DueItem{} = item) do
    scope = socket.assigns.current_scope
    organisations = Organisations.list_organisations(scope, status: "active")
    categories = Categories.list_categories(scope, status: "active")

    organisations = keep_current(organisations, item.organisation_id, item.organisation)
    categories = keep_current(categories, item.category_id, item.category)

    socket
    |> assign(:organisation_options, Enum.map(organisations, &{&1.name, &1.id}))
    |> assign(:category_options, Enum.map(categories, &{&1.name, &1.id}))
    |> assign(:member_options, member_options(socket))
  end

  defp keep_current(records, nil, _current), do: records

  defp keep_current(records, id, current) do
    if Enum.any?(records, &(&1.id == id)) or not is_struct(current),
      do: records,
      else: records ++ [current]
  end

  defp member_options(%{assigns: %{control?: false}}), do: []

  defp member_options(socket) do
    socket.assigns.current_scope
    |> DueItems.assignable_members()
    |> Enum.map(&{&1.user.name, &1.user.id})
  end

  defp parse_offset(%{"days" => days, "direction" => direction}) when is_binary(days) do
    case Integer.parse(String.trim(days)) do
      {n, ""} when n >= 1 ->
        offset = if direction == "after", do: n, else: -n
        if ReminderRule.valid_offset?(offset), do: {:ok, offset}, else: :error

      _ ->
        :error
    end
  end

  defp parse_offset(_), do: :error
end

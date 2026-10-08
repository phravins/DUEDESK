defmodule DueDeskWeb.DueItemFormComponents do
  @moduledoc """
  The Dates, Responsibility and Reminders sections of the DueItem forms,
  shared by the create and edit form and the reactivate form, plus the
  helpers that derive their assigns from a changeset.
  """
  use DueDeskWeb, :html

  alias DueDesk.DueItems.ReminderRule

  @doc """
  Assigns the form and the values the sections read from it: whether both
  dates are set, the recurrence, the chosen assignees and the reminder
  offsets. `extra_offsets` are custom reminders added on this page.
  """
  def assign_due_item_form(socket, changeset, extra_offsets \\ []) do
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
      Enum.sort(Enum.uniq(ReminderRule.defaults() ++ offsets ++ extra_offsets))
    )
  end

  @doc """
  Parses the Add Custom Reminder inputs into an offset in days: negative
  before the date, positive after it.
  """
  def parse_custom_reminder(%{"days" => days, "direction" => direction}) when is_binary(days) do
    case Integer.parse(String.trim(days)) do
      {n, ""} when n >= 1 ->
        offset = if direction == "after", do: n, else: -n
        if ReminderRule.valid_offset?(offset), do: {:ok, offset}, else: :error

      _ ->
        :error
    end
  end

  def parse_custom_reminder(_), do: :error

  @doc "The message shown when a custom reminder cannot be added."
  def custom_reminder_error,
    do: "Enter a number of days from 1 to #{ReminderRule.max_days()}."

  @doc "Due, Expiry and Start Dates."
  attr :form, Phoenix.HTML.Form, required: true
  attr :both_dates?, :boolean, default: false
  attr :subtitle, :string, default: "Enter a Due Date, an Expiry Date, or both."

  def dates_section(assigns) do
    ~H"""
    <.card id="section-dates" title="Dates">
      <:subtitle>{@subtitle}</:subtitle>
      <div class="grid gap-x-4 sm:grid-cols-3">
        <.input field={@form[:due_date]} type="date" label="Due Date" />
        <.input field={@form[:expiry_date]} type="date" label="Expiry Date" />
        <.input field={@form[:start_date]} type="date" label="Start Date" hint="Optional." />
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
    """
  end

  @doc """
  Primary Responsible and Additional Assignees. The empty additional
  input is always sent, so choosing nobody clears any Additional
  Assignees.
  """
  attr :form, Phoenix.HTML.Form, required: true
  attr :member_options, :list, required: true
  attr :primary_id, :string, default: nil
  attr :primary_selected?, :boolean, default: false
  attr :additional_ids, :list, default: []

  def responsibility_section(assigns) do
    ~H"""
    <.card id="section-responsibility" title="Responsibility">
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
      <input type="hidden" name={@form[:additional_user_ids].name <> "[]"} value="" />
      <fieldset :if={@primary_selected?} id="additional-assignees">
        <legend class="mb-2 text-[13px] font-medium text-zinc-600">
          Additional Assignees <span class="font-normal text-zinc-400">(optional)</span>
        </legend>
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
    """
  end

  @doc """
  Reminder checkboxes with an Add Custom Reminder row. The page handles
  the `add_reminder` event.
  """
  attr :form, Phoenix.HTML.Form, required: true
  attr :reminder_choices, :list, required: true
  attr :offsets, :list, required: true
  attr :custom, :map, required: true
  attr :custom_error, :string, default: nil

  def reminders_section(assigns) do
    ~H"""
    <.card id="section-reminders" title="Reminders">
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
          <.button id="add-reminder" type="button" variant="secondary" phx-click="add_reminder">
            <.icon name="hero-plus-mini" class="size-4" /> Add
          </.button>
        </div>
        <p :if={@custom_error} id="custom-reminder-error" class="text-xs text-rose-600">
          {@custom_error}
        </p>
      </div>
    </.card>
    """
  end
end

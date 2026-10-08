defmodule DueDeskWeb.DueItemLive.Index do
  @moduledoc """
  The DueItems list (UX spec §20). Filters live in the query string, so
  dashboard cards and the sidebar search link straight to a filtered
  list. Administrators see every DueItem with Unassigned, Awaiting
  action, Renewal reviews and Archived tabs; Users see the DueItems they
  are responsible for.
  """
  use DueDeskWeb, :live_view

  import DueDeskWeb.DueItemComponents

  alias DueDesk.{Categories, DueItems, Organisations, Permissions, Tenancy}
  alias DueDesk.DueItems.Status

  @filter_keys ~w(q status organisation_id category_id primary_user_id assignee_user_id
                  due_from due_to expiry_from expiry_to)
  @more_filter_keys ~w(primary_user_id assignee_user_id due_from due_to expiry_from expiry_to)
  @tab_keys ~w(view assignment)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:due_items}>
      <.page_header
        eyebrow={if @admin?, do: "Account", else: "Your work"}
        icon="hero-clipboard-document-list"
        title={@page_title}
      >
        <:subtitle>
          <%= if @admin? do %>
            Every renewal, filing and obligation in your account, soonest first.
          <% else %>
            The DueItems you are responsible for, soonest first.
          <% end %>
        </:subtitle>
        <:actions>
          <.button id="new-due-item" navigate={~p"/due-items/new"}>
            <.icon name="hero-plus" class="size-4" /> New DueItem
          </.button>
        </:actions>
      </.page_header>

      <.tabs :if={@admin?} id="due-item-tabs">
        <:tab id="tab-active" patch={tab_path(@params, :active)} active={@tab == :active}>
          Active
        </:tab>
        <:tab
          id="tab-unassigned"
          patch={tab_path(@params, :unassigned)}
          active={@tab == :unassigned}
          count={@unassigned_count}
        >
          Unassigned
        </:tab>
        <:tab
          id="tab-awaiting"
          patch={tab_path(@params, :awaiting)}
          active={@tab == :awaiting}
          count={@awaiting_count}
        >
          Awaiting action
        </:tab>
        <:tab
          id="tab-reviews"
          patch={tab_path(@params, :reviews)}
          active={@tab == :reviews}
          count={@reviews_count}
        >
          Renewal reviews
        </:tab>
        <:tab id="tab-archived" patch={tab_path(@params, :archived)} active={@tab == :archived}>
          Archived
        </:tab>
      </.tabs>

      <.form
        :if={@tab != :reviews}
        for={@filter_form}
        id="due-item-filters"
        phx-change="filter"
        phx-submit="filter"
        class="mb-4"
      >
        <div class="flex flex-col gap-2 sm:flex-row sm:flex-wrap sm:items-start">
          <div class="sm:w-72">
            <.input
              field={@filter_form[:q]}
              type="search"
              icon="hero-magnifying-glass"
              placeholder="Search title, reference, Organisation…"
              phx-debounce="300"
              aria-label="Search DueItems"
              messages={false}
              class={filter_class("pl-9")}
            />
          </div>
          <div :if={@tab not in [:archived, :awaiting]} class="sm:w-40">
            <.input
              field={@filter_form[:status]}
              type="select"
              prompt="Any status"
              options={status_options()}
              aria-label="Status"
              messages={false}
              class={filter_class("appearance-none pr-10")}
            />
          </div>
          <%= if @admin? do %>
            <div class="sm:w-48">
              <.input
                field={@filter_form[:organisation_id]}
                type="select"
                prompt="All Organisations"
                options={@organisation_options}
                aria-label="Organisation"
                messages={false}
                class={filter_class("appearance-none pr-10")}
              />
            </div>
            <div class="sm:w-48">
              <.input
                field={@filter_form[:category_id]}
                type="select"
                prompt="All categories"
                options={@category_options}
                aria-label="Category"
                messages={false}
                class={filter_class("appearance-none pr-10")}
              />
            </div>
            <button
              type="button"
              id="toggle-more-filters"
              class="inline-flex h-9 items-center gap-1.5 rounded-md px-2.5 text-sm text-zinc-600 transition hover:bg-[#efefed] hover:text-ink"
              phx-click={JS.toggle(to: "#more-filters")}
            >
              <.icon name="hero-adjustments-horizontal" class="size-4" /> More filters
              <span
                :if={@more_count > 0}
                class="rounded-full bg-navy px-1.5 py-px text-[11px] tabular-nums text-white"
              >
                {@more_count}
              </span>
            </button>
          <% end %>
          <button
            :if={@filtered?}
            type="button"
            id="clear-filters"
            phx-click="clear_filters"
            class="inline-flex h-9 items-center gap-1 rounded-md px-2.5 text-sm text-zinc-500 transition hover:bg-[#efefed] hover:text-ink"
          >
            <.icon name="hero-x-mark-mini" class="size-4" /> Clear
          </button>
        </div>

        <div
          :if={@admin?}
          id="more-filters"
          class={[
            "mt-2 grid gap-x-3 rounded-lg border border-line bg-white p-4 pb-0 sm:grid-cols-2 lg:grid-cols-4",
            @more_count == 0 && "hidden"
          ]}
        >
          <.input
            field={@filter_form[:primary_user_id]}
            type="select"
            label="Primary Responsible"
            prompt="Anyone"
            options={@member_options}
          />
          <.input
            field={@filter_form[:assignee_user_id]}
            type="select"
            label="Assigned to (any role)"
            prompt="Anyone"
            options={@member_options}
          />
          <div class="grid grid-cols-2 gap-2 lg:col-span-2">
            <.input field={@filter_form[:due_from]} type="date" label="Due from" />
            <.input field={@filter_form[:due_to]} type="date" label="Due to" />
          </div>
          <div class="grid grid-cols-2 gap-2 lg:col-span-2">
            <.input field={@filter_form[:expiry_from]} type="date" label="Expires from" />
            <.input field={@filter_form[:expiry_to]} type="date" label="Expires to" />
          </div>
        </div>
      </.form>

      <ul
        :if={@tab == :reviews}
        id="renewal-reviews"
        phx-update="stream"
        class="divide-y divide-line overflow-hidden rounded-lg border border-line bg-white"
      >
        <li id="renewal-reviews-empty" class="hidden px-6 py-12 text-center only:block">
          <span class="mx-auto flex size-10 items-center justify-center rounded-full bg-[#efefed] text-zinc-500">
            <.icon name="hero-check-badge" class="size-5" />
          </span>
          <p class="mt-3 text-sm font-medium text-ink">No renewals to review</p>
          <p class="mt-1 text-sm text-muted">
            When a User renews a DueItem, it appears here so you can check the new dates.
          </p>
        </li>
        <li
          :for={{dom_id, cycle} <- @streams.renewal_reviews}
          id={dom_id}
          class="flex flex-col gap-3 px-4 py-3.5 md:flex-row md:items-center md:gap-4"
        >
          <div class="min-w-0 flex-1">
            <.link
              navigate={~p"/due-items/#{cycle.due_item}"}
              class="block truncate text-sm font-medium text-ink hover:underline hover:underline-offset-2"
            >
              {cycle.due_item.title}
            </.link>
            <p class="truncate text-xs text-muted">
              {cycle.due_item.organisation.name} · Renewed by {renewed_by(cycle)} on {date(
                cycle.completed_on
              )}
            </p>
          </div>
          <span class="shrink-0 text-sm tabular-nums text-zinc-700">
            {next_dates_label(cycle.due_item)}
          </span>
          <div class="flex shrink-0 flex-wrap gap-2">
            <.button
              id={"review-#{cycle.id}"}
              size="sm"
              variant="outline"
              navigate={~p"/due-items/#{cycle.due_item}"}
            >
              Review
            </.button>
            <.button
              :if={is_nil(cycle.due_item.disposition_state)}
              id={"edit-dates-#{cycle.id}"}
              size="sm"
              variant="outline"
              navigate={~p"/due-items/#{cycle.due_item}/edit"}
            >
              Edit dates
            </.button>
            <.button
              id={"dismiss-#{cycle.id}"}
              size="sm"
              variant="ghost"
              phx-click="dismiss_review"
              phx-value-id={cycle.id}
            >
              Dismiss
            </.button>
          </div>
        </li>
      </ul>

      <.empty_state
        :if={@empty? and @tab != :reviews}
        id="due-items-empty"
        icon={if @filtered?, do: "hero-funnel", else: "hero-clipboard-document-list"}
        title={empty_title(@tab, @filtered?, @admin?)}
      >
        {empty_text(@tab, @filtered?, @admin?)}
        <:action :if={@filtered?}>
          <.button variant="secondary" phx-click="clear_filters">Clear filters</.button>
        </:action>
        <:action :if={!@filtered? and @tab == :active}>
          <.button navigate={~p"/due-items/new"}>
            <.icon name="hero-plus" class="size-4" /> New DueItem
          </.button>
        </:action>
      </.empty_state>

      <div
        :if={!@empty? and @tab != :reviews}
        class="overflow-hidden rounded-lg border border-line bg-white"
      >
        <div class="hidden border-b border-line bg-[#fafaf9] px-4 py-3 text-xs font-medium text-zinc-500 md:grid md:grid-cols-[minmax(0,2.4fr)_minmax(0,1.3fr)_minmax(0,1.2fr)_minmax(0,1.3fr)_6.5rem_6.5rem_8.5rem] md:gap-4">
          <span>DueItem</span>
          <span>Organisation</span>
          <span>Category</span>
          <span>Primary Responsible</span>
          <span>Due Date</span>
          <span>Expiry Date</span>
          <span>Status</span>
        </div>
        <ul id="due-items" phx-update="stream" class="divide-y divide-line">
          <li
            :for={{dom_id, item} <- @streams.due_items}
            id={dom_id}
            class="group cursor-pointer transition hover:bg-[#fafaf9]"
            phx-click={JS.navigate(~p"/due-items/#{item}")}
          >
            <div class="grid gap-2 px-4 py-3.5 md:grid-cols-[minmax(0,2.4fr)_minmax(0,1.3fr)_minmax(0,1.2fr)_minmax(0,1.3fr)_6.5rem_6.5rem_8.5rem] md:items-center md:gap-4">
              <div class="min-w-0">
                <.link
                  navigate={~p"/due-items/#{item}"}
                  class="block truncate text-sm font-medium text-ink group-hover:underline group-hover:underline-offset-2"
                >
                  {item.title}
                </.link>
                <p
                  :if={item.reference_number}
                  class="truncate font-mono text-[12px] text-zinc-400"
                >
                  {item.reference_number}
                </p>
                <p class="truncate text-xs text-muted md:hidden">
                  {item.organisation.name} · {item.category.name}
                </p>
              </div>
              <span class="hidden truncate text-sm text-zinc-600 md:block">
                {item.organisation.name}
              </span>
              <span class="hidden truncate text-sm text-zinc-600 md:block">
                {item.category.name}
              </span>
              <span class="text-sm"><.responsibility item={item} /></span>
              <span class="text-sm tabular-nums text-zinc-700">
                <span class="text-xs text-muted md:hidden">Due </span>{date(
                  item.current_cycle.due_date
                )}
              </span>
              <span class="text-sm tabular-nums text-zinc-500">
                <span class="text-xs text-muted md:hidden">Expires </span>{date(
                  item.current_cycle.expiry_date
                )}
              </span>
              <span>
                <.due_item_status
                  item={item}
                  status={item_status(item, @today, @due_soon_days)}
                />
              </span>
            </div>
          </li>
        </ul>
      </div>

      <div :if={@has_more?} class="mt-4 flex justify-center">
        <.button
          id="load-more"
          variant="secondary"
          phx-click="load_more"
          phx-disable-with="Loading…"
        >
          Load more
        </.button>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    admin? = Permissions.can_view_all_due_items?(scope)

    socket =
      socket
      |> assign(:page_title, if(admin?, do: "DueItems", else: "My DueItems"))
      |> assign(:admin?, admin?)
      |> assign(:today, Tenancy.today(scope))
      |> assign(:due_soon_days, scope.customer_account.due_soon_days)
      |> stream(:due_items, [])
      |> stream(:renewal_reviews, [])

    socket =
      if admin? do
        socket
        |> assign(
          :organisation_options,
          options(
            Organisations.list_organisations(scope) ++
              Organisations.list_organisations(scope, status: "archived")
          )
        )
        |> assign(:category_options, options(Categories.list_categories(scope)))
        |> assign(:member_options, member_options(scope))
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    params = clean(params)

    tab =
      cond do
        !socket.assigns.admin? -> :active
        params["view"] == "archived" -> :archived
        params["view"] == "awaiting" -> :awaiting
        params["view"] == "reviews" -> :reviews
        params["assignment"] == "unassigned" -> :unassigned
        true -> :active
      end

    filters = Map.take(params, @filter_keys)

    socket =
      socket
      |> assign(:params, params)
      |> assign(:tab, tab)
      |> assign(:filtered?, filters != %{})
      |> assign(:more_count, map_size(Map.take(filters, @more_filter_keys)))
      |> assign(:filter_form, to_form(filters))
      |> assign(:offset, 0)
      |> assign_counts()
      |> load_tab()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter", form_params, socket) do
    filters = form_params |> Map.take(@filter_keys) |> clean()
    tab = Map.take(socket.assigns.params, @tab_keys)

    filters =
      if tab["view"] in ["archived", "awaiting"], do: Map.delete(filters, "status"), else: filters

    {:noreply, push_patch(socket, to: list_path(Map.merge(tab, filters)))}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, push_patch(socket, to: list_path(Map.take(socket.assigns.params, @tab_keys)))}
  end

  def handle_event("dismiss_review", %{"id" => id}, socket) do
    case DueItems.dismiss_renewal_review(socket.assigns.current_scope, id) do
      {:ok, cycle} ->
        {:noreply,
         socket
         |> put_flash(:info, "Renewal marked as reviewed.")
         |> stream_delete(:renewal_reviews, cycle)
         |> assign_counts()}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("load_more", _params, socket) do
    {:noreply,
     socket
     |> update(:offset, &(&1 + DueItems.per_page()))
     |> load_page(reset: false)}
  end

  defp assign_counts(%{assigns: %{admin?: false}} = socket), do: socket

  defp assign_counts(socket) do
    scope = socket.assigns.current_scope

    socket
    |> assign(:unassigned_count, DueItems.count_by_status(scope).unassigned)
    |> assign(:awaiting_count, DueItems.count_awaiting(scope))
    |> assign(:reviews_count, DueItems.count_renewal_reviews(scope))
  end

  defp load_tab(%{assigns: %{tab: :reviews}} = socket) do
    socket
    |> assign(:has_more?, false)
    |> assign(:empty?, false)
    |> stream(:due_items, [], reset: true)
    |> stream(
      :renewal_reviews,
      DueItems.list_renewal_reviews(socket.assigns.current_scope),
      reset: true
    )
  end

  defp load_tab(socket), do: load_page(socket, reset: true)

  defp load_page(socket, reset: reset?) do
    %{current_scope: scope, params: params, offset: offset} = socket.assigns
    per_page = DueItems.per_page()
    items = DueItems.list_due_items(scope, params, limit: per_page + 1, offset: offset)
    {page, more} = Enum.split(items, per_page)

    socket
    |> assign(:has_more?, more != [])
    |> then(fn socket ->
      if reset?, do: assign(socket, :empty?, page == []), else: socket
    end)
    |> stream(:due_items, page, reset: reset?)
  end

  defp clean(params) do
    params
    |> Map.take(@filter_keys ++ @tab_keys)
    |> Enum.reject(fn {_k, v} -> not is_binary(v) or String.trim(v) == "" end)
    |> Map.new()
  end

  defp list_path(params) when params == %{}, do: ~p"/due-items"
  defp list_path(params), do: ~p"/due-items?#{params}"

  defp tab_path(params, tab) do
    params
    |> Map.drop(@tab_keys)
    |> then(fn params ->
      case tab do
        :active -> params
        :unassigned -> Map.put(params, "assignment", "unassigned")
        :archived -> params |> Map.delete("status") |> Map.put("view", "archived")
        :awaiting -> params |> Map.delete("status") |> Map.put("view", "awaiting")
        :reviews -> %{"view" => "reviews"}
      end
    end)
    |> list_path()
  end

  defp renewed_by(%{completed_by_user: %{name: name}}), do: name
  defp renewed_by(_cycle), do: "a former member"

  defp next_dates_label(%{disposition_state: "awaiting_new_dates"}), do: "Next dates pending"

  defp next_dates_label(%{current_cycle: cycle}) do
    cond do
      cycle.due_date -> "Next due #{date(cycle.due_date)}"
      cycle.expiry_date -> "Next expiry #{date(cycle.expiry_date)}"
      true -> "—"
    end
  end

  defp status_options do
    for status <- [:overdue, :due_soon, :up_to_date],
        do: {Status.label(status), Atom.to_string(status)}
  end

  defp options(records), do: Enum.map(records, &{&1.name, &1.id})

  defp member_options(scope) do
    scope
    |> DueItems.assignable_members()
    |> Enum.map(&{&1.user.name, &1.user.id})
  end

  # Compact filter-bar fields: same look as the form fields, a little shorter.
  defp filter_class(extra) do
    [
      "block h-9 w-full rounded-md border border-transparent bg-field px-3 text-sm text-ink",
      "placeholder:text-zinc-400 transition duration-150 hover:bg-[#ededeb]",
      "focus:border-zinc-300 focus:bg-white focus:outline-none focus:ring-3 focus:ring-zinc-900/5",
      extra
    ]
  end

  defp empty_title(_tab, true, _admin?), do: "No DueItems match these filters"
  defp empty_title(:archived, _, _), do: "No archived DueItems"
  defp empty_title(:awaiting, _, _), do: "Nothing awaiting action"
  defp empty_title(:unassigned, _, _), do: "Everything has someone responsible"
  defp empty_title(:active, _, true), do: "No DueItems yet"
  defp empty_title(:active, _, false), do: "Nothing assigned to you yet"

  defp empty_text(_tab, true, _admin?), do: "Try a different search, or clear the filters."

  defp empty_text(:archived, _, _),
    do: "DueItems you archive appear here with their history, and can be restored."

  defp empty_text(:awaiting, _, _),
    do:
      "Completed DueItems, and renewals still needing dates, wait here for you to decide what happens next."

  defp empty_text(:unassigned, _, _),
    do: "Every active DueItem has a Primary Responsible."

  defp empty_text(:active, _, true),
    do: "Add the licences, registrations, filings and renewals your Organisations must keep up."

  defp empty_text(:active, _, false),
    do: "DueItems you create or are assigned to appear here."
end

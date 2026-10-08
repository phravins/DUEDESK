defmodule DueDeskWeb.CategoryLive.Index do
  @moduledoc """
  Account categories for DueItems. Default categories are read-only;
  custom categories can be added, renamed, archived and restored.
  Administrators and Super Admins only.
  """
  use DueDeskWeb, :live_view

  on_mount {DueDeskWeb.UserAuth, :require_admin}

  alias DueDesk.Categories
  alias DueDesk.DueItems.Category

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:categories}>
      <.page_header eyebrow="Account" icon="hero-tag" title="Categories">
        <:subtitle>
          Categories group DueItems so they are easier to find and filter. Archived categories
          stay on existing DueItems but cannot be chosen for new ones.
        </:subtitle>
      </.page_header>

      <div class="grid gap-4 lg:grid-cols-2">
        <.card id="custom-categories-card" title="Your categories">
          <:subtitle>Added by your team.</:subtitle>

          <.form
            for={@form}
            id="category-form"
            phx-change="validate"
            phx-submit="create"
            class="mb-4 flex items-start gap-2 [&>div:first-child]:mb-0 [&>div:first-child]:flex-1"
          >
            <.input
              field={@form[:name]}
              type="text"
              placeholder="New category, e.g. Trademarks"
              aria-label="Category name"
              autocomplete="off"
            />
            <.button id="add-category" phx-disable-with="Adding...">
              <.icon name="hero-plus" class="size-4" /> Add
            </.button>
          </.form>

          <ul id="custom-categories" phx-update="stream" class="divide-y divide-line">
            <li
              id="custom-categories-empty"
              class="hidden py-8 text-center text-sm text-muted only:block"
            >
              No custom categories yet.
            </li>
            <li
              :for={{dom_id, category} <- @streams.custom_categories}
              id={dom_id}
              class="group flex min-h-12 items-center gap-3 py-2"
            >
              <%= if @editing_id == category.id do %>
                <.form
                  for={@rename_form}
                  id={"rename-form-#{category.id}"}
                  phx-submit="rename"
                  phx-value-id={category.id}
                  class="flex flex-1 items-start gap-2 [&>div:first-child]:mb-0 [&>div:first-child]:flex-1"
                >
                  <.input
                    field={@rename_form[:name]}
                    type="text"
                    aria-label="Category name"
                    autocomplete="off"
                    phx-mounted={JS.focus()}
                  />
                  <.button size="sm" class="mt-0.5">Save</.button>
                  <.button
                    type="button"
                    size="sm"
                    variant="ghost"
                    class="mt-0.5"
                    phx-click="cancel_edit"
                    phx-value-id={category.id}
                  >
                    Cancel
                  </.button>
                </.form>
              <% else %>
                <span class={[
                  "min-w-0 flex-1 truncate text-sm",
                  if(category.status == "archived", do: "text-zinc-400", else: "text-ink")
                ]}>
                  {category.name}
                </span>
                <.status_badge :if={category.status == "archived"} status={:archived} />
                <div class="flex shrink-0 items-center gap-1 opacity-100 transition sm:opacity-0 sm:group-hover:opacity-100 sm:group-focus-within:opacity-100">
                  <%= if category.status == "active" do %>
                    <.button
                      id={"rename-#{category.id}"}
                      type="button"
                      size="sm"
                      variant="ghost"
                      phx-click="edit"
                      phx-value-id={category.id}
                    >
                      Rename
                    </.button>
                    <.button
                      id={"archive-#{category.id}"}
                      type="button"
                      size="sm"
                      variant="ghost"
                      phx-click="archive"
                      phx-value-id={category.id}
                      data-confirm="Archive this category? DueItems keep it, but it cannot be chosen for new ones."
                    >
                      Archive
                    </.button>
                  <% else %>
                    <.button
                      id={"restore-#{category.id}"}
                      type="button"
                      size="sm"
                      variant="ghost"
                      phx-click="restore"
                      phx-value-id={category.id}
                    >
                      Restore
                    </.button>
                  <% end %>
                </div>
              <% end %>
            </li>
          </ul>
        </.card>

        <.card id="system-categories-card" title="Default categories">
          <:subtitle>Included in every DueDesk account. They cannot be changed.</:subtitle>
          <ul id="system-categories" phx-update="stream" class="divide-y divide-line">
            <li
              :for={{dom_id, category} <- @streams.system_categories}
              id={dom_id}
              class="flex min-h-11 items-center gap-3 py-2"
            >
              <span class="min-w-0 flex-1 truncate text-sm text-ink">{category.name}</span>
              <.icon name="hero-lock-closed-mini" class="size-4 text-zinc-300" />
            </li>
          </ul>
        </.card>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {system, custom} =
      socket.assigns.current_scope
      |> Categories.list_categories()
      |> Enum.split_with(& &1.system)

    {:ok,
     socket
     |> assign(:page_title, "Categories")
     |> assign(:editing_id, nil)
     |> assign(:rename_form, nil)
     |> assign_new_form()
     |> stream(:system_categories, system)
     |> stream(:custom_categories, custom)}
  end

  @impl true
  def handle_event("validate", %{"category" => params}, socket) do
    changeset = Categories.change_category(%Category{}, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("create", %{"category" => params}, socket) do
    case Categories.create_category(socket.assigns.current_scope, params) do
      {:ok, category} ->
        {:noreply,
         socket
         |> put_flash(:info, "Category added.")
         |> assign_new_form()
         |> stream_insert(:custom_categories, category)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, reason} ->
        {:noreply, put_error(socket, reason)}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    category = Categories.get_category!(socket.assigns.current_scope, id)
    socket = reset_editing(socket)

    {:noreply,
     socket
     |> assign(:editing_id, category.id)
     |> assign(:rename_form, rename_form(Categories.change_category(category)))
     |> stream_insert(:custom_categories, category)}
  end

  def handle_event("cancel_edit", %{"id" => id}, socket) do
    category = Categories.get_category!(socket.assigns.current_scope, id)

    {:noreply,
     socket
     |> assign(:editing_id, nil)
     |> stream_insert(:custom_categories, category)}
  end

  def handle_event("rename", %{"id" => id, "category" => params}, socket) do
    scope = socket.assigns.current_scope
    category = Categories.get_category!(scope, id)

    case Categories.rename_category(scope, category, params) do
      {:ok, category} ->
        {:noreply,
         socket
         |> put_flash(:info, "Category renamed.")
         |> assign(:editing_id, nil)
         |> stream_insert(:custom_categories, category)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:rename_form, rename_form(changeset))
         |> stream_insert(:custom_categories, category)}

      {:error, reason} ->
        {:noreply, put_error(socket, reason)}
    end
  end

  def handle_event("archive", %{"id" => id}, socket) do
    change_status(socket, id, &Categories.archive_category/2, "Category archived.")
  end

  def handle_event("restore", %{"id" => id}, socket) do
    change_status(socket, id, &Categories.restore_category/2, "Category restored.")
  end

  defp change_status(socket, id, fun, message) do
    scope = socket.assigns.current_scope
    category = Categories.get_category!(scope, id)

    case fun.(scope, category) do
      {:ok, category} ->
        {:noreply,
         socket
         |> put_flash(:info, message)
         |> stream_insert(:custom_categories, category)}

      {:error, reason} ->
        {:noreply, put_error(socket, reason)}
    end
  end

  # Re-renders the category being edited, so only one row is in edit mode.
  defp reset_editing(%{assigns: %{editing_id: nil}} = socket), do: socket

  defp reset_editing(socket) do
    category = Categories.get_category!(socket.assigns.current_scope, socket.assigns.editing_id)

    socket
    |> assign(:editing_id, nil)
    |> stream_insert(:custom_categories, category)
  end

  # Its own id keeps the inputs apart from the add form's.
  defp rename_form(changeset), do: to_form(changeset, id: "rename_category")

  defp assign_new_form(socket) do
    assign(socket, :form, to_form(Categories.change_category(%Category{})))
  end

  defp put_error(socket, :system_category),
    do: put_flash(socket, :error, "Default categories cannot be changed.")

  defp put_error(socket, _reason),
    do: put_flash(socket, :error, "This category could not be changed.")
end

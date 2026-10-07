defmodule DueDeskWeb.Layouts do
  @moduledoc """
  Layouts for DueDesk.

    * `auth/1` — sign up, log in, password reset and onboarding
    * `app/1` — the signed-in shell with the sidebar
  """
  use DueDeskWeb, :html

  alias DueDesk.Accounts.Scope
  alias DueDesk.Permissions
  alias DueDesk.Tenancy.Membership

  embed_templates "layouts/*"

  @doc """
  The DueDesk mark and word logo.
  """
  attr :class, :string, default: "h-8"

  def logo(assigns) do
    ~H"""
    <span class={["inline-flex items-center gap-2.5 font-semibold tracking-[-0.02em]", @class]}>
      <svg viewBox="0 0 32 32" class="h-full w-auto" aria-hidden="true">
        <rect x="1" y="1" width="30" height="30" rx="10" class="fill-ink" />
        <path
          d="M9.5 16.5l4.5 4.5 8.5-9"
          fill="none"
          stroke-width="3"
          stroke-linecap="round"
          stroke-linejoin="round"
          class="stroke-white"
        />
        <circle cx="24.5" cy="7.5" r="3" class="fill-brand" />
      </svg>
      <span class="text-xl text-ink">DueDesk</span>
    </span>
    """
  end

  @doc """
  Layout for sign up, log in, password reset and onboarding: a plain white
  page with the logo top-left and a narrow centred form.
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :wide, :boolean, default: false
  slot :header_action, doc: "the prompt at the top right, e.g. a link to sign up"
  slot :inner_block, required: true

  def auth(assigns) do
    ~H"""
    <div class="auth-shell flex min-h-screen flex-col bg-white">
      <header class="flex h-16 items-center justify-between gap-4 px-5 sm:h-20 sm:px-10">
        <.link navigate={~p"/"} aria-label="DueDesk"><.logo class="h-8" /></.link>
        <div class="text-right text-sm text-muted">
          <%= cond do %>
            <% @header_action != [] -> %>
              {render_slot(@header_action)}
            <% @current_scope && @current_scope.user -> %>
              <.link
                href={~p"/users/log-out"}
                method="delete"
                class="font-medium text-zinc-600 transition hover:text-ink"
              >
                Log out
              </.link>
            <% true -> %>
          <% end %>
        </div>
      </header>

      <main class="flex flex-1 justify-center px-5 pb-16 pt-8 sm:pt-[12vh]">
        <div class={["w-full", if(@wide, do: "max-w-[440px]", else: "max-w-[360px]")]}>
          {render_slot(@inner_block)}
        </div>
      </main>

      <footer class="flex flex-col items-center justify-between gap-2 border-t border-line px-5 py-5 text-xs text-zinc-400 sm:flex-row sm:px-10">
        <p>© {Date.utc_today().year} REALSME Solutions Pvt Ltd</p>
        <p class="inline-flex items-center gap-1.5">
          <.icon name="hero-lock-closed-mini" class="size-3.5" />
          Your data stays private to your account
        </p>
      </footer>
    </div>
    <.flash_group flash={@flash} />
    """
  end

  @doc """
  The signed-in application shell: a left sidebar with the navigation, a
  Create DueItem button and the account menu.

  Navigation is built from the scope's role:

    * User: Dashboard, My DueItems, Support
    * Administrator / Super Admin: Dashboard, DueItems, Organisations,
      Users, Categories, Account, Support
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  attr :active, :atom, default: nil, doc: "the nav item to highlight"
  slot :inner_block, required: true

  def app(assigns) do
    {main, footer} =
      assigns.current_scope
      |> nav_items()
      |> Enum.split_with(&(&1.key not in [:account, :support]))

    assigns = assign(assigns, main_nav: main, footer_nav: footer)

    ~H"""
    <div class="min-h-screen bg-white">
      <header class="sticky top-0 z-30 flex h-14 items-center justify-between border-b border-line bg-white/90 px-4 backdrop-blur lg:hidden">
        <.link navigate={~p"/dashboard"} aria-label="Dashboard"><.logo class="h-7" /></.link>
        <button
          type="button"
          id="mobile-nav-button"
          class="flex size-9 items-center justify-center rounded-md text-zinc-600 transition hover:bg-zinc-100 hover:text-ink"
          phx-click={toggle_sidebar()}
          aria-label="Open menu"
        >
          <.icon name="hero-bars-3" class="size-5" />
        </button>
      </header>

      <div
        id="sidebar-backdrop"
        class="fixed inset-0 z-40 hidden bg-zinc-900/20 backdrop-blur-[2px] lg:hidden"
        phx-click={toggle_sidebar()}
        aria-hidden="true"
      />

      <aside
        id="sidebar"
        class="fixed inset-y-0 left-0 z-50 flex w-64 flex-col border-r border-line bg-[#fbfbfa] transition-transform duration-200 ease-out max-lg:-translate-x-full"
      >
        <div class="flex h-16 shrink-0 items-center justify-between px-5">
          <.link navigate={~p"/dashboard"} aria-label="Dashboard"><.logo class="h-7" /></.link>
          <button
            type="button"
            class="flex size-8 items-center justify-center rounded-md text-zinc-500 hover:bg-zinc-100 lg:hidden"
            phx-click={toggle_sidebar()}
            aria-label="Close menu"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <form action={~p"/due-items"} method="get" role="search" class="px-3 pb-3">
          <label class="relative block">
            <span class="sr-only">Search DueItems</span>
            <.icon
              name="hero-magnifying-glass"
              class="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-zinc-400"
            />
            <input
              id="search-input"
              type="search"
              name="q"
              placeholder="Search"
              class="h-9 w-full rounded-md border border-transparent bg-[#efefed] pl-9 pr-3 text-sm placeholder:text-zinc-500 transition focus:border-zinc-300 focus:bg-white focus:outline-none"
            />
          </label>
        </form>

        <nav id="main-nav" aria-label="Main" class="flex-1 space-y-0.5 overflow-y-auto px-3">
          <.nav_link :for={item <- @main_nav} item={item} active={@active} />
        </nav>

        <div class="space-y-0.5 px-3 pb-3">
          <.button navigate={~p"/due-items/new"} size="lg" class="mb-3 w-full">
            <.icon name="hero-plus" class="size-4" /> Create DueItem
          </.button>
          <.nav_link :for={item <- @footer_nav} item={item} active={@active} small />
          <.link
            navigate={~p"/users/settings"}
            class={[nav_class(@active == :profile), "py-1.5 text-sm"]}
          >
            <.icon name="hero-user-circle" class="size-[18px] text-zinc-500" /> My profile
          </.link>
        </div>

        <div class="relative border-t border-line p-3">
          <button
            type="button"
            id="user-menu-button"
            class="flex w-full items-center gap-3 rounded-md p-2 text-left transition hover:bg-zinc-100"
            phx-click={toggle_menu("#user-menu")}
            aria-haspopup="true"
          >
            <span class={[
              "flex size-9 shrink-0 items-center justify-center rounded-full text-xs font-semibold text-white",
              avatar_colour(@current_scope.customer_account.name)
            ]}>
              {initials(@current_scope.customer_account.name)}
            </span>
            <span class="min-w-0 flex-1">
              <span id="account-name" class="block truncate text-sm font-medium text-ink">
                {@current_scope.customer_account.name}
              </span>
              <span class="block truncate text-xs text-muted">{role_label(@current_scope)}</span>
            </span>
            <.icon name="hero-chevron-up-down-mini" class="size-4 shrink-0 text-zinc-400" />
          </button>
          <div
            id="user-menu"
            class="absolute inset-x-3 bottom-full mb-1 hidden rounded-lg border border-line bg-white p-1.5 text-sm shadow-float"
            phx-click-away={hide("#user-menu")}
          >
            <div class="px-2.5 py-2">
              <p class="truncate font-medium text-ink">{@current_scope.user.name}</p>
              <p class="truncate text-xs text-muted">{@current_scope.user.email}</p>
            </div>
            <div class="my-1 border-t border-line" />
            <.link navigate={~p"/users/settings"} class={menu_item()}>
              <.icon name="hero-user-circle" class="size-4 text-zinc-400" /> My profile
            </.link>
            <.link href={~p"/users/log-out"} method="delete" class={menu_item()}>
              <.icon name="hero-arrow-right-start-on-rectangle" class="size-4 text-zinc-400" />
              Log out
            </.link>
          </div>
        </div>
      </aside>

      <main class="lg:pl-64">
        <div class="mx-auto max-w-[1280px] px-4 pb-16 pt-6 sm:px-8 lg:px-10 lg:pt-8">
          {render_slot(@inner_block)}
        </div>
      </main>
    </div>
    <.flash_group flash={@flash} />
    """
  end

  attr :item, :map, required: true
  attr :active, :atom, default: nil
  attr :small, :boolean, default: false

  defp nav_link(assigns) do
    ~H"""
    <.link
      navigate={@item.path}
      aria-current={@item.key == @active && "page"}
      class={[nav_class(@item.key == @active), if(@small, do: "py-1.5 text-sm", else: "text-[15px]")]}
    >
      <.icon
        name={@item.icon}
        class={[
          if(@small, do: "size-[18px]", else: "size-5"),
          if(@item.key == @active, do: "text-ink", else: "text-zinc-500")
        ]}
      />
      {@item.label}
    </.link>
    """
  end

  defp nav_class(true),
    do: "flex items-center gap-3 rounded-md bg-[#ececea] px-3 py-2 font-medium text-ink"

  defp nav_class(false) do
    "flex items-center gap-3 rounded-md px-3 py-2 font-medium text-zinc-600 transition hover:bg-[#f1f1ef] hover:text-ink"
  end

  defp menu_item do
    "flex items-center gap-2.5 rounded-md px-2.5 py-2 text-zinc-700 transition hover:bg-zinc-100 hover:text-ink"
  end

  defp toggle_sidebar do
    "max-lg:-translate-x-full"
    |> JS.toggle_class(to: "#sidebar")
    |> JS.toggle(
      to: "#sidebar-backdrop",
      in: {"transition-opacity duration-200", "opacity-0", "opacity-100"},
      out: {"transition-opacity duration-150", "opacity-100", "opacity-0"}
    )
  end

  defp toggle_menu(selector) do
    JS.toggle(
      to: selector,
      in:
        {"transition ease-out duration-150", "opacity-0 translate-y-1",
         "opacity-100 translate-y-0"},
      out:
        {"transition ease-in duration-100", "opacity-100 translate-y-0",
         "opacity-0 translate-y-1"}
    )
  end

  @avatar_colours ~w(bg-rose-500 bg-violet-500 bg-sky-600 bg-emerald-600 bg-amber-500 bg-indigo-500)

  defp avatar_colour(name),
    do: Enum.at(@avatar_colours, :erlang.phash2(name, length(@avatar_colours)))

  defp nav_items(%Scope{} = scope) do
    if Permissions.admin?(scope) do
      [
        %{key: :dashboard, label: "Dashboard", icon: "hero-squares-2x2", path: ~p"/dashboard"},
        %{
          key: :due_items,
          label: "DueItems",
          icon: "hero-clipboard-document-list",
          path: ~p"/due-items"
        },
        %{
          key: :organisations,
          label: "Organisations",
          icon: "hero-building-office-2",
          path: ~p"/organisations"
        },
        %{key: :users, label: "Users", icon: "hero-users", path: ~p"/users"},
        %{key: :categories, label: "Categories", icon: "hero-tag", path: ~p"/categories"},
        %{key: :support, label: "Help & Support", icon: "hero-lifebuoy", path: ~p"/support"},
        %{key: :account, label: "Account", icon: "hero-cog-6-tooth", path: ~p"/account"}
      ]
    else
      [
        %{key: :dashboard, label: "Dashboard", icon: "hero-squares-2x2", path: ~p"/dashboard"},
        %{
          key: :due_items,
          label: "My DueItems",
          icon: "hero-clipboard-document-list",
          path: ~p"/due-items"
        },
        %{key: :support, label: "Help & Support", icon: "hero-lifebuoy", path: ~p"/support"}
      ]
    end
  end

  defp role_label(%Scope{membership: %{role: role}}), do: Membership.role_label(role)

  defp initials(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end

  @doc """
  Shows the flash notices and the connection-lost notices.
  """
  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div
      id={@id}
      aria-live="polite"
      class="pointer-events-none fixed right-4 top-4 z-50 flex w-[calc(100%-2rem)] flex-col gap-2 sm:w-96"
    >
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end

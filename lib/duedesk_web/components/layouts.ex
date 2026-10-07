defmodule DueDeskWeb.Layouts do
  @moduledoc """
  Layouts for DueDesk.

    * `public/1` — marketing pages (home, pricing)
    * `auth/1` — sign up, log in, onboarding: a centred card
    * `app/1` — the signed-in shell: sidebar, top bar and mobile navigation
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
    <span class={["inline-flex items-center gap-2 font-semibold tracking-tight", @class]}>
      <svg viewBox="0 0 32 32" class="h-full w-auto" aria-hidden="true">
        <rect x="2" y="5" width="28" height="25" rx="6" class="fill-primary" />
        <rect x="8" y="2" width="3" height="7" rx="1.5" class="fill-primary" />
        <rect x="21" y="2" width="3" height="7" rx="1.5" class="fill-primary" />
        <path
          d="M10 18.5l4 4 8-8.5"
          fill="none"
          stroke="white"
          stroke-width="3"
          stroke-linecap="round"
          stroke-linejoin="round"
        />
      </svg>
      <span class="text-lg">DueDesk</span>
    </span>
    """
  end

  @doc """
  Layout for public marketing pages.
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  slot :inner_block, required: true

  def public(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col bg-base-100">
      <header class="border-b border-base-300/70">
        <nav class="mx-auto max-w-6xl flex items-center justify-between gap-4 px-4 sm:px-6 h-16">
          <.link navigate={~p"/"}><.logo class="h-8" /></.link>
          <div class="flex items-center gap-1 sm:gap-2 text-sm">
            <.link
              navigate={~p"/"}
              class="hidden sm:inline-flex px-3 py-2 rounded-lg hover:bg-base-200"
            >
              Product
            </.link>
            <.link navigate={~p"/pricing"} class="px-3 py-2 rounded-lg hover:bg-base-200">
              Pricing
            </.link>
            <%= if @current_scope && @current_scope.user do %>
              <.link
                navigate={~p"/dashboard"}
                class="px-4 py-2 rounded-lg bg-primary text-primary-content font-medium hover:opacity-90 transition"
              >
                Open DueDesk
              </.link>
            <% else %>
              <.link navigate={~p"/users/log-in"} class="px-3 py-2 rounded-lg hover:bg-base-200">
                Log in
              </.link>
              <.link
                navigate={~p"/users/register"}
                class="px-4 py-2 rounded-lg bg-primary text-primary-content font-medium hover:opacity-90 transition"
              >
                Sign up
              </.link>
            <% end %>
          </div>
        </nav>
      </header>

      <main class="flex-1">
        {render_slot(@inner_block)}
      </main>

      <footer class="border-t border-base-300/70 text-sm text-base-content/60">
        <div class="mx-auto max-w-6xl px-4 sm:px-6 py-8 flex flex-col sm:flex-row gap-2 justify-between">
          <p>© {Date.utc_today().year} REALSME Solutions Pvt Ltd. DueDesk is made in India.</p>
          <p>
            <a href="mailto:support@duedesk.in" class="hover:text-base-content">
              support@duedesk.in
            </a>
          </p>
        </div>
      </footer>
    </div>
    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Layout for sign up, log in, password reset and onboarding.
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :wide, :boolean, default: false
  slot :inner_block, required: true

  def auth(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col bg-base-200">
      <header class="px-4 sm:px-6 h-16 flex items-center justify-between">
        <.link navigate={~p"/"}><.logo class="h-8" /></.link>
        <.link
          :if={@current_scope && @current_scope.user}
          href={~p"/users/log-out"}
          method="delete"
          class="text-sm text-base-content/70 hover:text-base-content"
        >
          Log out
        </.link>
      </header>
      <main class="flex-1 flex items-start sm:items-center justify-center px-4 py-8">
        <div class={[
          "w-full bg-base-100 rounded-2xl border border-base-300 shadow-sm p-6 sm:p-8",
          if(@wide, do: "max-w-xl", else: "max-w-md")
        ]}>
          {render_slot(@inner_block)}
        </div>
      </main>
    </div>
    <.flash_group flash={@flash} />
    """
  end

  @doc """
  The signed-in application shell.

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
    assigns = assign(assigns, :nav, nav_items(assigns.current_scope))

    ~H"""
    <div class="min-h-screen bg-base-200 lg:flex">
      <%!-- Desktop sidebar --%>
      <aside class="hidden lg:flex lg:w-64 lg:flex-col lg:fixed lg:inset-y-0 bg-base-100 border-r border-base-300">
        <div class="h-16 flex items-center px-5 border-b border-base-300">
          <.link navigate={~p"/dashboard"}><.logo class="h-7" /></.link>
        </div>
        <.nav_list nav={@nav} active={@active} />
      </aside>

      <%!-- Mobile drawer --%>
      <div id="mobile-nav" class="lg:hidden fixed inset-0 z-40 hidden" role="dialog" aria-modal="true">
        <div class="absolute inset-0 bg-black/40" phx-click={hide_mobile_nav()}></div>
        <aside class="absolute inset-y-0 left-0 w-72 max-w-[85%] bg-base-100 shadow-xl flex flex-col">
          <div class="h-16 flex items-center justify-between px-5 border-b border-base-300">
            <.logo class="h-7" />
            <button
              type="button"
              class="p-2 rounded-lg hover:bg-base-200"
              phx-click={hide_mobile_nav()}
              aria-label="Close menu"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>
          <.nav_list nav={@nav} active={@active} />
        </aside>
      </div>

      <div class="flex-1 lg:pl-64 flex flex-col min-h-screen">
        <%!-- Top bar --%>
        <header class="sticky top-0 z-30 h-16 bg-base-100/95 backdrop-blur border-b border-base-300 flex items-center gap-3 px-4 sm:px-6">
          <button
            type="button"
            class="lg:hidden p-2 -ml-2 rounded-lg hover:bg-base-200"
            phx-click={show_mobile_nav()}
            aria-label="Open menu"
          >
            <.icon name="hero-bars-3" class="size-6" />
          </button>

          <div class="min-w-0">
            <p class="text-sm font-semibold truncate" id="account-name">
              {@current_scope.customer_account.name}
            </p>
            <p class="text-xs text-base-content/60">{role_label(@current_scope)}</p>
          </div>

          <form
            action={~p"/due-items"}
            method="get"
            class="hidden md:flex flex-1 max-w-md ml-auto"
            role="search"
          >
            <label class="relative w-full">
              <span class="sr-only">Search DueItems</span>
              <.icon
                name="hero-magnifying-glass"
                class="size-4 absolute left-3 top-1/2 -translate-y-1/2 text-base-content/50"
              />
              <input
                type="search"
                name="q"
                placeholder="Search DueItems"
                class="w-full h-10 pl-9 pr-3 rounded-lg bg-base-200 border border-transparent focus:border-primary focus:bg-base-100 outline-none text-sm transition"
              />
            </label>
          </form>

          <div class="flex items-center gap-1 ml-auto md:ml-2">
            <.link
              navigate={~p"/dashboard"}
              class="p-2 rounded-lg hover:bg-base-200 relative"
              aria-label="Notifications"
            >
              <.icon name="hero-bell" class="size-5" />
            </.link>

            <div class="relative">
              <button
                type="button"
                id="user-menu-button"
                class="flex items-center gap-2 p-1.5 rounded-lg hover:bg-base-200"
                phx-click={JS.toggle(to: "#user-menu")}
                aria-haspopup="true"
              >
                <span class="size-8 rounded-full bg-primary/15 text-primary font-semibold text-sm flex items-center justify-center">
                  {initials(@current_scope.user.name)}
                </span>
                <.icon name="hero-chevron-down-mini" class="size-4 hidden sm:block" />
              </button>
              <div
                id="user-menu"
                class="hidden absolute right-0 mt-2 w-60 rounded-xl bg-base-100 border border-base-300 shadow-lg py-2 text-sm"
                phx-click-away={JS.hide(to: "#user-menu")}
              >
                <div class="px-4 py-2 border-b border-base-300 mb-1">
                  <p class="font-medium truncate">{@current_scope.user.name}</p>
                  <p class="text-base-content/60 truncate">{@current_scope.user.email}</p>
                </div>
                <.link navigate={~p"/users/settings"} class="block px-4 py-2 hover:bg-base-200">
                  My profile
                </.link>
                <.link
                  href={~p"/users/log-out"}
                  method="delete"
                  class="block px-4 py-2 hover:bg-base-200"
                >
                  Log out
                </.link>
              </div>
            </div>
          </div>
        </header>

        <main class="flex-1 px-4 sm:px-6 lg:px-8 py-6 pb-24 lg:pb-8">
          <div class="mx-auto max-w-6xl">
            {render_slot(@inner_block)}
          </div>
        </main>
      </div>

      <%!-- Mobile bottom bar: Dashboard and DueItems always one tap away --%>
      <nav class="lg:hidden fixed bottom-0 inset-x-0 z-30 bg-base-100 border-t border-base-300 grid grid-cols-3 text-xs">
        <.link
          navigate={~p"/dashboard"}
          class={[
            "flex flex-col items-center gap-1 py-2",
            if(@active == :dashboard, do: "text-primary", else: "text-base-content/70")
          ]}
        >
          <.icon name="hero-home" class="size-5" /> Dashboard
        </.link>
        <.link
          navigate={~p"/due-items"}
          class={[
            "flex flex-col items-center gap-1 py-2",
            if(@active == :due_items, do: "text-primary", else: "text-base-content/70")
          ]}
        >
          <.icon name="hero-clipboard-document-list" class="size-5" />
          {if Permissions.admin?(@current_scope), do: "DueItems", else: "My DueItems"}
        </.link>
        <button
          type="button"
          class="flex flex-col items-center gap-1 py-2 text-base-content/70"
          phx-click={show_mobile_nav()}
        >
          <.icon name="hero-bars-3" class="size-5" /> Menu
        </button>
      </nav>
    </div>
    <.flash_group flash={@flash} />
    """
  end

  attr :nav, :list, required: true
  attr :active, :atom, default: nil

  defp nav_list(assigns) do
    ~H"""
    <nav class="flex-1 overflow-y-auto px-3 py-4 space-y-1" aria-label="Main">
      <.link
        :for={item <- @nav}
        navigate={item.path}
        class={[
          "flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium transition",
          if(item.key == @active,
            do: "bg-primary/10 text-primary",
            else: "text-base-content/75 hover:bg-base-200 hover:text-base-content"
          )
        ]}
        aria-current={item.key == @active && "page"}
      >
        <.icon name={item.icon} class="size-5" />
        {item.label}
      </.link>
    </nav>
    """
  end

  defp nav_items(%Scope{} = scope) do
    if Permissions.admin?(scope) do
      [
        %{key: :dashboard, label: "Dashboard", icon: "hero-home", path: ~p"/dashboard"},
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
        %{key: :account, label: "Account", icon: "hero-cog-6-tooth", path: ~p"/account"},
        %{key: :support, label: "Support", icon: "hero-lifebuoy", path: ~p"/support"}
      ]
    else
      [
        %{key: :dashboard, label: "Dashboard", icon: "hero-home", path: ~p"/dashboard"},
        %{
          key: :due_items,
          label: "My DueItems",
          icon: "hero-clipboard-document-list",
          path: ~p"/due-items"
        },
        %{key: :support, label: "Support", icon: "hero-lifebuoy", path: ~p"/support"}
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

  defp show_mobile_nav, do: JS.show(to: "#mobile-nav")
  defp hide_mobile_nav, do: JS.hide(to: "#mobile-nav")

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
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

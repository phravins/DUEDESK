defmodule DueDeskWeb.PlaceholderLive do
  @moduledoc """
  Temporary page for sections delivered in later build phases. Each phase
  replaces its routes with the real LiveView. Role checks still apply.
  """
  use DueDeskWeb, :live_view

  alias DueDesk.Permissions

  @sections %{
    due_items: %{title: "DueItems", phase: 2, nav: :due_items, admin_only?: false},
    new_due_item: %{title: "Create DueItem", phase: 2, nav: :due_items, admin_only?: false},
    users: %{title: "Users", phase: 5, nav: :users, admin_only?: true},
    account: %{title: "Account", phase: 7, nav: :account, admin_only?: true},
    support: %{title: "Support", phase: 7, nav: :support, admin_only?: false}
  }

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={@section.nav}>
      <.page_header eyebrow="DueDesk" title={@section.title} />
      <.empty_state id="coming-soon" icon="hero-wrench-screwdriver" title="Coming soon">
        This part of DueDesk is being built and arrives in phase {@section.phase}.
        <:action>
          <.button variant="secondary" navigate={~p"/dashboard"}>
            <.icon name="hero-arrow-left-mini" class="size-4" /> Back to dashboard
          </.button>
        </:action>
      </.empty_state>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    section = Map.fetch!(@sections, socket.assigns.live_action)

    if section.admin_only? and not Permissions.admin?(socket.assigns.current_scope) do
      {:ok,
       socket
       |> put_flash(:error, "This page is not available to your account access.")
       |> push_navigate(to: ~p"/dashboard")}
    else
      {:ok, assign(socket, section: section, page_title: section.title)}
    end
  end
end

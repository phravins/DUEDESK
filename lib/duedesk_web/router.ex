defmodule DueDeskWeb.Router do
  use DueDeskWeb, :router

  import DueDeskWeb.UserAuth
  import DueDeskAdmin.OperatorAuth, only: [fetch_current_operator: 2, require_operator: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DueDeskWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :operator do
    plug :fetch_current_operator
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", DueDeskWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  if Application.compile_env(:duedesk, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: DueDeskWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Signed-in application
  #
  # Every page in the app needs a confirmed user with an active Customer
  # Account, so they share the `:account` live_session whose on_mount loads
  # the account and role into `current_scope`.

  scope "/", DueDeskWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :account, on_mount: [{DueDeskWeb.UserAuth, :require_account}] do
      live "/dashboard", DashboardLive, :index

      live "/due-items", DueItemLive.Index, :index
      live "/due-items/new", DueItemLive.Form, :new
      live "/due-items/:id", DueItemLive.Show, :show
      live "/due-items/:id/edit", DueItemLive.Form, :edit
      live "/organisations", OrganisationLive.Index, :index
      live "/organisations/new", OrganisationLive.Form, :new
      live "/organisations/:id", OrganisationLive.Show, :show
      live "/organisations/:id/edit", OrganisationLive.Form, :edit
      live "/categories", CategoryLive.Index, :index
      live "/users", PlaceholderLive, :users
      live "/account", PlaceholderLive, :account
      live "/account/plans", AccountLive.Plans, :index
      live "/support", PlaceholderLive, :support

      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email

      # Onboarding step 4: the account exists by now.
      live "/onboarding/organisation", OnboardingLive.Organisation, :new
    end

    # Onboarding: signed in, but no Customer Account yet.
    live_session :onboarding,
      on_mount: [
        {DueDeskWeb.UserAuth, :require_authenticated},
        {DueDeskWeb.UserAuth, :require_no_account}
      ] do
      live "/onboarding/account", OnboardingLive.Account, :new
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  ## Authentication (public)

  scope "/", DueDeskWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{DueDeskWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/confirm/:token", UserLive.Confirmation, :confirm
      live "/users/reset-password", UserLive.ForgotPassword, :new
      live "/users/reset-password/:token", UserLive.ResetPassword, :edit
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  ## Internal operator console

  scope "/admin", DueDeskAdmin do
    pipe_through [:browser, :operator]

    get "/log-in", SessionController, :new
    post "/log-in", SessionController, :create
    delete "/log-out", SessionController, :delete
  end

  scope "/admin", DueDeskAdmin do
    pipe_through [:browser, :operator, :require_operator]

    live_session :operator, on_mount: [{DueDeskAdmin.OperatorAuth, :require_operator}] do
      live "/", AccountsLive, :index
    end
  end
end

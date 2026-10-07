import Config

config :duedesk, :scopes,
  user: [
    default: true,
    module: DueDesk.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :binary_id,
    schema_table: :users,
    test_data_fixture: DueDesk.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :elixir, :time_zone_database, Tz.TimeZoneDatabase

config :duedesk, :mail_from, {"DueDesk", "no-reply@duedesk.in"}

config :duedesk,
  namespace: DueDesk,
  ecto_repos: [DueDesk.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

config :duedesk, DueDeskWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: DueDeskWeb.ErrorHTML, json: DueDeskWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: DueDesk.PubSub,
  live_view: [signing_salt: "WpsO4Q6+"]

config :phoenix_live_view, root_tag_attribute: "phx-r"

config :duedesk, DueDesk.Mailer, adapter: Swoosh.Adapters.Local

config :esbuild,
  version: "0.25.4",
  duedesk: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

config :tailwind,
  version: "4.3.0",
  duedesk: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

# Request params whose names contain these are logged as [FILTERED].
config :phoenix, :filter_parameters, ["password", "token", "secret", "signature", "otp", "key"]

import_config "#{config_env()}.exs"

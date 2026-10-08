import Config

# Local credentials live in `.env` (gitignored, see `.env.example`). In dev
# and test its KEY=value lines are loaded into the environment; variables
# already set in the shell win. Production reads the real environment only.
dotenv = Path.expand("../.env", __DIR__)

if config_env() in [:dev, :test] and File.regular?(dotenv) do
  for line <- File.stream!(dotenv),
      line = String.trim(line),
      line != "" and not String.starts_with?(line, "#"),
      [key, value] <- [String.split(String.replace_prefix(line, "export ", ""), "=", parts: 2)],
      key = String.trim(key),
      value = value |> String.trim() |> String.trim("\"") |> String.trim("'"),
      value != "" and System.get_env(key) == nil do
    System.put_env(key, value)
  end
end

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

# Documents are stored on local disk in development (uploads/, ignored by
# git). Production uses an S3 or R2 bucket, set in config/runtime.exs.
config :duedesk, DueDesk.Documents.Storage,
  adapter: DueDesk.Documents.Storage.Local,
  root: Path.expand("../uploads", __DIR__)

config :duedesk, :document_max_file_size, 30 * 1024 * 1024

# Background jobs. The reminder scan runs every 15 minutes; storage
# counters are reconciled nightly (both in the account timezone of India).
config :duedesk, Oban,
  engine: Oban.Engines.Basic,
  repo: DueDesk.Repo,
  queues: [reminders: 5, email: 10, whatsapp: 5, maintenance: 1],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 7 * 24 * 60 * 60},
    Oban.Plugins.Lifeline,
    {Oban.Plugins.Cron,
     timezone: "Asia/Kolkata",
     crontab: [
       {"*/15 * * * *", DueDesk.Notifications.Workers.ReminderScanWorker},
       {"30 2 * * *", DueDesk.Notifications.Workers.StorageReconcileWorker}
     ]}
  ]

# WhatsApp reminders go out through a signed webhook when N8N_WEBHOOK_URL
# is set (config/runtime.exs); otherwise the channel is unavailable.
config :duedesk, DueDesk.Notifications.WhatsApp, adapter: DueDesk.Notifications.WhatsApp.Disabled

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

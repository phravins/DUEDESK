import Config

config :duedesk, DueDesk.Repo,
  username: System.get_env("DB_USERNAME", "postgres"),
  password: System.get_env("DB_PASSWORD", "postgres"),
  hostname: System.get_env("DB_HOST", "localhost"),
  port: String.to_integer(System.get_env("DB_PORT", "5432")),
  database: "duedesk_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :duedesk, DueDeskWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "GCAhsEEYPq3vXnhGqKnMPMic+OxGRU1MttVULVtJzRjoUm8Vfdaj16LnDaqbrnVN",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:duedesk, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:duedesk, ~w(--watch)]}
  ]

config :duedesk, DueDeskWeb.Endpoint,
  live_reload: [
    web_console_logger: true,
    patterns: [
      ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*\.po$",
      ~r"lib/duedesk_web/router\.ex$",
      ~r"lib/duedesk_web/(controllers|live|components)/.*\.(ex|heex)$",
      ~r"lib/duedesk_admin/.*\.(ex|heex)$"
    ]
  ]

config :duedesk, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true

config :swoosh, :api_client, false

import Config

config :bcrypt_elixir, :log_rounds, 1

config :duedesk, DueDesk.Repo,
  username: System.get_env("DB_USERNAME", "postgres"),
  password: System.get_env("DB_PASSWORD", "postgres"),
  hostname: System.get_env("DB_HOST", "localhost"),
  port: String.to_integer(System.get_env("DB_PORT", "5432")),
  database: "duedesk_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :duedesk, DueDeskWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "0Ho3BFwEgnu+bL2X8bzhfSqYOumBXGo10dimp36gFjpeOcLp96CF5z5tLnTokEn1",
  server: false

config :duedesk, DueDesk.Mailer, adapter: Swoosh.Adapters.Test

config :duedesk, DueDesk.Documents.Storage,
  adapter: DueDesk.Documents.Storage.Local,
  root:
    Path.join(
      System.tmp_dir!(),
      "duedesk_test_uploads#{System.get_env("MIX_TEST_PARTITION")}"
    )

# Small enough that "too large" can be tested without a 30 MB fixture.
config :duedesk, :document_max_file_size, 100_000

config :swoosh, :api_client, false

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view, enable_expensive_runtime_checks: true

config :phoenix, sort_verified_routes_query_params: true

# Jobs are inserted but only run when a test performs them.
config :duedesk, Oban, testing: :manual

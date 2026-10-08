import Config

if System.get_env("PHX_SERVER") do
  config :duedesk, DueDeskWeb.Endpoint, server: true
end

config :duedesk, DueDeskWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :duedesk, DueDesk.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "duedesk.in"

  config :duedesk, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # Documents: a private S3 or R2 bucket when S3_BUCKET is set, otherwise
  # a directory on a persistent disk (UPLOADS_DIR). One of them is required.
  env = fn name -> if System.get_env(name, "") != "", do: System.get_env(name) end

  cond do
    bucket = env.("S3_BUCKET") ->
      fetch = fn name ->
        env.(name) || raise "environment variable #{name} is missing (S3_BUCKET is set)"
      end

      config :duedesk, DueDesk.Documents.Storage, adapter: DueDesk.Documents.Storage.S3

      config :duedesk, DueDesk.Documents.Storage.S3,
        bucket: bucket,
        region: env.("S3_REGION") || "auto",
        endpoint: env.("S3_ENDPOINT"),
        access_key_id: fetch.("S3_ACCESS_KEY_ID"),
        secret_access_key: fetch.("S3_SECRET_ACCESS_KEY")

    dir = env.("UPLOADS_DIR") ->
      config :duedesk, DueDesk.Documents.Storage,
        adapter: DueDesk.Documents.Storage.Local,
        root: dir

    true ->
      raise """
      document storage is not configured.
      Set S3_BUCKET (with S3_REGION, S3_ENDPOINT, S3_ACCESS_KEY_ID and
      S3_SECRET_ACCESS_KEY) or UPLOADS_DIR.
      """
  end

  config :duedesk, DueDeskWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}],
    secret_key_base: secret_key_base
end

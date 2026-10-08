import Config

if System.get_env("PHX_SERVER") do
  config :duedesk, DueDeskWeb.Endpoint, server: true
end

config :duedesk, DueDeskWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# WhatsApp reminders: a signed webhook to the messaging workflow. Without
# N8N_WEBHOOK_URL the channel shows as unavailable. Not used in tests.
if config_env() != :test and System.get_env("N8N_WEBHOOK_URL", "") != "" do
  config :duedesk, DueDesk.Notifications.WhatsApp,
    adapter: DueDesk.Notifications.WhatsApp.N8n,
    url: System.fetch_env!("N8N_WEBHOOK_URL"),
    signing_secret:
      System.get_env("N8N_SIGNING_SECRET", "") |> then(&if(&1 == "", do: nil, else: &1)) ||
        raise("environment variable N8N_SIGNING_SECRET is missing (N8N_WEBHOOK_URL is set)")
end

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

  # Email: one of the Swoosh API adapters (they use Req; no extra deps).
  mail_adapters = %{
    "postmark" => Swoosh.Adapters.Postmark,
    "brevo" => Swoosh.Adapters.Brevo,
    "resend" => Swoosh.Adapters.Resend,
    "mailgun" => Swoosh.Adapters.Mailgun
  }

  mail_adapter =
    Map.get(mail_adapters, env.("MAIL_ADAPTER") || "") ||
      raise """
      environment variable MAIL_ADAPTER is missing or unknown.
      Use one of: #{Enum.join(Map.keys(mail_adapters), ", ")}
      """

  mail_api_key = env.("MAIL_API_KEY") || raise "environment variable MAIL_API_KEY is missing"

  config :duedesk,
         DueDesk.Mailer,
         [adapter: mail_adapter, api_key: mail_api_key] ++
           if(mail_adapter == Swoosh.Adapters.Mailgun,
             do: [
               domain:
                 env.("MAIL_DOMAIN") ||
                   raise("environment variable MAIL_DOMAIN is missing (needed for mailgun)")
             ],
             else: []
           )

  if from = env.("MAIL_FROM") do
    config :duedesk, :mail_from, {"DueDesk", from}
  end

  config :duedesk, DueDeskWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}],
    secret_key_base: secret_key_base
end

defmodule DueDesk.Notifications.WhatsApp.N8n do
  @moduledoc """
  Posts a WhatsApp message request as JSON to a webhook (`N8N_WEBHOOK_URL`).

  The request is signed so the receiver can reject forgeries and replays:

      x-duedesk-signature: t=<unix seconds>,v1=<hex HMAC-SHA256>

  where the HMAC is computed with `N8N_SIGNING_SECRET` over
  `"<t>.<raw body>"`. The secret is never part of the body. Req does not
  retry; the delivery job does, with backoff.
  """
  @behaviour DueDesk.Notifications.WhatsApp

  @impl true
  def deliver(payload, config) do
    body = Jason.encode!(payload)
    timestamp = Integer.to_string(System.system_time(:second))

    [
      url: Keyword.fetch!(config, :url),
      body: body,
      headers: [
        {"content-type", "application/json"},
        {"x-duedesk-signature",
         signature(timestamp, body, Keyword.fetch!(config, :signing_secret))}
      ],
      retry: false,
      receive_timeout: 15_000
    ]
    |> Keyword.merge(Keyword.get(config, :req_options, []))
    |> Req.post()
    |> case do
      {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
      {:ok, %Req.Response{status: status}} -> {:error, "http_#{status}"}
      {:error, %Req.TransportError{reason: :timeout}} -> {:error, "timeout"}
      {:error, %Req.TransportError{}} -> {:error, "connection_failed"}
      {:error, _} -> {:error, "request_failed"}
    end
  end

  @doc "The signature header value for `body` sent at `timestamp`."
  def signature(timestamp, body, secret) do
    mac = :crypto.mac(:hmac, :sha256, secret, timestamp <> "." <> body)
    "t=#{timestamp},v1=#{Base.encode16(mac, case: :lower)}"
  end
end

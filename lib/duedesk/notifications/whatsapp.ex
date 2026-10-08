defmodule DueDesk.Notifications.WhatsApp do
  @moduledoc """
  Sends WhatsApp reminders through the configured adapter:

    * `DueDesk.Notifications.WhatsApp.N8n` posts a signed webhook, which
      a workflow turns into a WhatsApp template message;
    * `DueDesk.Notifications.WhatsApp.Disabled` (the default) sends
      nothing; the channel is then unavailable.

  Adapters return `:ok` or `{:error, code}` with a short code such as
  `"timeout"` or `"http_500"`. They never log message contents or full
  mobile numbers.
  """

  @callback deliver(payload :: map(), config :: keyword()) :: :ok | {:error, String.t()}

  @doc "Sends `payload` (template, recipient and values) to one person."
  @spec deliver(map()) :: :ok | {:error, String.t()}
  def deliver(payload) do
    config = config()
    Keyword.fetch!(config, :adapter).deliver(payload, config)
  end

  @doc "Whether WhatsApp messages can be sent at all."
  def enabled?, do: Keyword.fetch!(config(), :adapter) != __MODULE__.Disabled

  @doc "Masks a mobile number for logs: `******3210`."
  def mask(nil), do: "none"
  def mask(number) when is_binary(number), do: "******" <> String.slice(number, -4, 4)

  defp config, do: Application.fetch_env!(:duedesk, __MODULE__)
end

defmodule DueDesk.Notifications.WhatsApp.Disabled do
  @moduledoc """
  Used when no WhatsApp webhook is configured. Nothing is sent; members
  see "WhatsApp delivery unavailable".
  """
  @behaviour DueDesk.Notifications.WhatsApp

  @impl true
  def deliver(_payload, _config), do: {:error, "unavailable"}
end

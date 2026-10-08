defmodule DueDesk.Notifications.Workers.EmailDeliveryWorker do
  @moduledoc "Sends one email delivery. See `DueDesk.Notifications.deliver/3`."
  use Oban.Worker, queue: :email, max_attempts: 5

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"delivery_id" => id}, attempt: attempt, max_attempts: max}),
    do: DueDesk.Notifications.deliver(id, attempt, max)
end

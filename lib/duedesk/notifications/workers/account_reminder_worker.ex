defmodule DueDesk.Notifications.Workers.AccountReminderWorker do
  @moduledoc """
  Queues the reminders of one account that fall due today in the
  account's timezone. Safe to run any number of times: reminders that
  were queued before are not queued again.
  """
  use Oban.Worker, queue: :reminders, max_attempts: 3

  alias DueDesk.{Notifications, Repo}
  alias DueDesk.Tenancy.CustomerAccount

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id}}) do
    case Repo.get(CustomerAccount, account_id) do
      %CustomerAccount{status: "active"} = account ->
        {:ok, _queued} = Notifications.queue_reminders(account)
        :ok

      _ ->
        :ok
    end
  end
end

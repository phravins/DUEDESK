defmodule DueDesk.Notifications.Workers.ReminderScanWorker do
  @moduledoc """
  Runs every 15 minutes (see the Oban cron in `config/config.exs`) and
  queues one `AccountReminderWorker` per active account, so a problem in
  one account cannot hold up the others.
  """
  use Oban.Worker, queue: :reminders, max_attempts: 3

  import Ecto.Query, warn: false

  alias DueDesk.Repo
  alias DueDesk.Notifications.Workers.AccountReminderWorker
  alias DueDesk.Tenancy.CustomerAccount

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    from(a in CustomerAccount, where: a.status == "active", select: a.id)
    |> Repo.all()
    |> Enum.map(&AccountReminderWorker.new(%{account_id: &1}))
    |> Oban.insert_all()

    :ok
  end
end

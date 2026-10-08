defmodule DueDesk.Notifications.Workers.StorageReconcileWorker do
  @moduledoc """
  Nightly: recomputes every account's stored-document bytes and corrects
  counters that drifted (see `DueDesk.Documents.reconcile_storage/1`).
  """
  use Oban.Worker, queue: :maintenance, max_attempts: 3

  import Ecto.Query, warn: false

  alias DueDesk.{Documents, Repo}
  alias DueDesk.Tenancy.CustomerAccount

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    from(a in CustomerAccount, where: a.status != "closed", select: a.id)
    |> Repo.all()
    |> Enum.each(&({:ok, _} = Documents.reconcile_storage(&1)))

    :ok
  end
end

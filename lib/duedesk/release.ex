defmodule DueDesk.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :duedesk

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Recomputes every account's stored-document bytes from its documents
  and corrects counters that drifted. Run with
  `bin/duedesk eval "DueDesk.Release.reconcile_storage()"`.
  """
  def reconcile_storage do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(DueDesk.Repo, fn repo ->
        import Ecto.Query

        repo.all(from(a in DueDesk.Tenancy.CustomerAccount, select: a.id))
        |> Enum.each(&DueDesk.Documents.reconcile_storage/1)
      end)

    :ok
  end

  @doc """
  Queues today's reminders for every active account now, without waiting
  for the 15-minute schedule. Run with
  `bin/duedesk eval "DueDesk.Release.run_reminders()"` (or
  `mix run -e "DueDesk.Release.run_reminders()"` in development, with the
  server running so the queued emails are sent).
  """
  def run_reminders do
    load_app()
    {:ok, _} = Application.ensure_all_started(@app)

    import Ecto.Query

    DueDesk.Repo.all(from(a in DueDesk.Tenancy.CustomerAccount, where: a.status == "active"))
    |> Enum.map(fn account ->
      {:ok, queued} = DueDesk.Notifications.queue_reminders(account)
      queued
    end)
    |> Enum.sum()
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end

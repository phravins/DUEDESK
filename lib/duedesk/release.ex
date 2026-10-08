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

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end

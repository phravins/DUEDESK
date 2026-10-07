defmodule DueDesk.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      DueDeskWeb.Telemetry,
      DueDesk.Repo,
      {DNSCluster, query: Application.get_env(:duedesk, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: DueDesk.PubSub},
      DueDeskWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: DueDesk.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    DueDeskWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

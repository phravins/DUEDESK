defmodule DueDesk.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      DueDeskWeb.Telemetry,
      DueDesk.Repo,
      {DNSCluster, query: Application.get_env(:duedesk, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: DueDesk.PubSub},
      # Start a worker by calling: DueDesk.Worker.start_link(arg)
      # {DueDesk.Worker, arg},
      # Start to serve requests, typically the last entry
      DueDeskWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: DueDesk.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DueDeskWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

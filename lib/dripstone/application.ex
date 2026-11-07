defmodule Dripstone.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      DripstoneWeb.Telemetry,
      Dripstone.Repo,
      {DNSCluster, query: Application.get_env(:dripstone, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Dripstone.PubSub},
      # Start a worker by calling: Dripstone.Worker.start_link(arg)
      # {Dripstone.Worker, arg},
      # Start to serve requests, typically the last entry
      DripstoneWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Dripstone.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DripstoneWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

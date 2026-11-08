defmodule Dripstone.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        DripstoneWeb.Telemetry,
        Dripstone.Repo,
        {Phoenix.PubSub, name: Dripstone.PubSub},
        {Oban, Application.fetch_env!(:dripstone, Oban)},
        DripstoneWeb.LoginThrottle
      ] ++
        simulator() ++
        [
          # Start to serve requests, typically the last entry
          DripstoneWeb.Endpoint
        ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Dripstone.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Dev-only fake detection; see Dripstone.Tracker.Simulator.
  defp simulator do
    if Application.get_env(:dripstone, :simulate_alerts, false),
      do: [Dripstone.Tracker.Simulator],
      else: []
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DripstoneWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

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
        Dripstone.Tracker.Writer,
        # Owns the politeness layer's rate slots and robots.txt cache.
        Dripstone.Adapters.Polite.Gate,
        # Live discovery's assessment caps (groups per hour, re-assessment interval).
        Dripstone.Discovery.Caps,
        # The Demo dataset (memory-only) and its simulator start here on demand.
        {DynamicSupervisor, name: Dripstone.Tracker.DemoSupervisor, strategy: :one_for_one},
        DripstoneWeb.LoginThrottle
      ] ++
        simulator() ++
        discovery() ++
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
  # Live discovery's Bluesky stream consumer, when enabled (prod; DRIPSTONE_DISCOVERY=1).
  defp discovery do
    if Dripstone.Discovery.Jetstream.enabled?(), do: [Dripstone.Discovery.Jetstream], else: []
  end

  # DRIPSTONE_SIMULATE=1 (dev) warms up Demo at boot; otherwise Demo and its
  # simulator start the first time someone switches to Demo.
  defp simulator do
    if Application.get_env(:dripstone, :simulate_alerts, false),
      do: [{Task, fn -> Dripstone.Tracker.DemoStore.ensure_started() end}],
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

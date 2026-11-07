defmodule Dripstone.Tracker.Simulator do
  @moduledoc """
  Dev-only stand-in for detection: every `interval` ms it reports a generated
  finding through `Dripstone.Tracker.report_finding/1`, so live updates (new alerts,
  badge counts, toasts) can be seen in the UI.

  Started only when `config :dripstone, :simulate_alerts` is true, which `dev.exs`
  sets from `DRIPSTONE_SIMULATE=1`. Each tick picks a network and trigger with no
  open alert, so it raises a new alert rather than merging into one.

  It also stands in for ingestion: each tick marks the Healthy sample feeds as having
  just received an item, so they don't go quiet (and turn Degraded) while the app runs.
  Down and Degraded feeds are left as they are.
  """

  use GenServer

  require Logger

  alias Dripstone.Tracker
  alias Dripstone.Tracker.SampleStore

  @default_interval 45_000
  @triggers ~w(network_growth network_reactivation promotion_shift)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, @default_interval)
    schedule(interval)
    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:tick, %{interval: interval} = state) do
    with {:ok, finding} <- next_finding(),
         {:ok, %{action: action, alert: alert}} <- Tracker.report_finding(finding) do
      Logger.debug("Simulator #{action} #{alert && alert.id} (#{finding.trigger})")
    end

    {:ok, _} = SampleStore.change(&refresh_feeds/1)
    schedule(interval)
    {:noreply, state}
  end

  defp refresh_feeds(state) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    feed_health =
      Enum.map(state.feed_health, fn
        %{status: :healthy} = health ->
          %{health | last_item_at: now, items_24h: health.items_24h + 1}

        health ->
          health
      end)

    {:ok, :refreshed, %{state | feed_health: feed_health}, []}
  end

  defp schedule(interval), do: Process.send_after(self(), :tick, interval)

  defp next_finding do
    SampleStore.read(fn state ->
      open =
        for {_, a} <- state.alerts,
            a.status == :open,
            into: MapSet.new(),
            do: {a.network_id, a.trigger_id}

      candidates =
        for {_, n} <- state.networks,
            is_nil(n.retired_into),
            trigger <- @triggers,
            {n.id, trigger} not in open,
            do: {n, trigger}

      case candidates do
        [] -> :none
        _ -> {:ok, candidates |> Enum.random() |> build(state)}
      end
    end)
  end

  defp build({network, "network_growth"}, state) do
    members = MapSet.new(network.member_ids)

    new_ids =
      state.accounts
      |> Map.values()
      |> Enum.filter(&(&1.feed_id in network.platforms and &1.id not in members))
      |> Enum.take_random(Enum.random(2..5))
      |> Enum.map(& &1.id)

    base(
      network,
      "network_growth",
      "#{network.name} gained #{length(new_ids)} accounts",
      "medium",
      evidence: [
        ev(
          "near_duplicate",
          "strong",
          "#{length(new_ids)} new accounts post the network's promo copy.",
          new_ids
        )
      ],
      comparison: %{
        label: "Members",
        before: "#{length(network.member_ids)}",
        after: "#{length(network.member_ids) + length(new_ids)}"
      },
      network_updates: %{add_member_ids: new_ids}
    )
  end

  defp build({network, "network_reactivation"}, _state) do
    woke = Enum.take_random(network.member_ids, min(4, length(network.member_ids)))

    base(network, "network_reactivation", "#{network.name} is posting again", "medium",
      evidence: [
        ev(
          "synced_posting",
          "strong",
          "#{length(woke)} accounts posted within an hour after a quiet spell.",
          woke
        )
      ]
    )
  end

  defp build({network, "promotion_shift"}, _state) do
    domain = "#{Enum.random(~w(promo deals bonus gift offer))}-#{Enum.random(100..999)}.example"

    base(network, "promotion_shift", "#{network.name} switched its main promoted domain", "high",
      evidence: [
        ev(
          "shared_link",
          "strong",
          "Links to #{domain} jumped to over half of the network's posts.",
          Enum.take(network.member_ids, 6)
        )
      ],
      comparison: %{
        label: "Main promoted domain",
        before: network.main_domain || "none",
        after: domain
      },
      network_updates: %{main_domain: domain}
    )
  end

  defp base(network, trigger, title, severity, extra) do
    now = DateTime.utc_now()

    Map.merge(
      %{
        trigger: trigger,
        severity: severity,
        title: title,
        observed_at: now,
        network_id: network.id,
        ai_rationale: %{text: "Simulated finding for local development.", generated_at: now}
      },
      Map.new(extra)
    )
  end

  defp ev(kind, strength, explanation, ids),
    do: %{kind: kind, strength: strength, explanation: explanation, account_ids: ids}
end

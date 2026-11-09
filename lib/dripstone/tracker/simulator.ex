defmodule Dripstone.Tracker.Simulator do
  @moduledoc """
  Dev-only driver for detection, so live updates (new alerts, badge counts,
  toasts) can be seen in the UI.

  Every `assess_interval` ms (2 minutes by default, first run after
  `first_assess` ms) it queues a `Dripstone.Workers.AssessWorker` job for one of a
  few stub handles. The job runs the real pipeline: stub adapter → `Scorer.assess`
  (which calls the AI if `OPENCODE_API_KEY` is set, otherwise heuristics only) →
  `Tracker.report_finding/1` (an account finding).

  Every `interval` ms (45 seconds by default) it also reports a generated finding
  with canned answers (model `"simulator"`, no AI call) through
  `Tracker.report_finding/1`, so network alerts keep arriving through the real
  rules: a trend finding for a live network, two new accounts joining one, or a few
  new accounts forming a new network. `kinds:` limits the choice (for tests).

  It also stands in for ingestion: on the same tick it marks the Healthy sample
  feeds as having just received an item, so they don't go quiet (and turn
  Degraded) while the app runs. Down and Degraded feeds are left as they are.

  Started only when `config :dripstone, :simulate_alerts` is true, which `dev.exs`
  sets from `DRIPSTONE_SIMULATE=1`. Tests pass `enqueue:` to capture jobs instead
  of inserting them.
  """

  use GenServer

  require Logger

  alias Dripstone.Tracker
  alias Dripstone.Tracker.Store
  alias Dripstone.Workers.AssessWorker

  @default_interval 45_000
  @default_assess_interval 120_000
  @default_first_assess 5_000

  # Fixed pool of simulator handles so overnight ticks reuse accounts
  # instead of growing `accounts` without bound.
  @sim_pool_size 200

  @handles [
    {"stub_x", "promo_daily"},
    {"stub_x", "deal_hunter_88"},
    {"stub_x", "crypto_signals_now"},
    {"stub_reddit", "free_gift_cards"},
    {"stub_reddit", "daily_deals_bot"}
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "The `{adapter, handle}` pairs the simulator assesses."
  def handles, do: @handles

  @impl true
  def init(opts) do
    # The simulator only ever feeds the dataset it was started for: Demo when
    # started by DemoStore, Live by default (tests).
    dataset = Keyword.get(opts, :dataset, :live)
    :ok = Dripstone.Tracker.put_dataset(dataset)

    state = %{
      dataset: dataset,
      interval: Keyword.get(opts, :interval, @default_interval),
      assess_interval: Keyword.get(opts, :assess_interval, @default_assess_interval),
      enqueue: Keyword.get(opts, :enqueue, &Oban.insert/1),
      kinds: Keyword.get(opts, :kinds, [:trend, :growth, :new])
    }

    Process.send_after(self(), :tick, state.interval)
    Process.send_after(self(), :assess, Keyword.get(opts, :first_assess, @default_first_assess))
    {:ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    {:ok, _} = apply_change(&refresh_feeds/1)
    report_canned(state.kinds)
    Process.send_after(self(), :tick, state.interval)
    {:noreply, state}
  end

  def handle_info(:assess, state) do
    {adapter, handle} = Enum.random(@handles)

    args = %{"adapter" => adapter, "handle" => handle, "dataset" => to_string(state.dataset)}

    case state.enqueue.(AssessWorker.new(args)) do
      {:ok, _job} -> Logger.debug("Simulator queued an assessment of #{handle} (#{adapter})")
      {:error, reason} -> Logger.warning("Simulator could not queue a job: #{inspect(reason)}")
    end

    Process.send_after(self(), :assess, state.assess_interval)
    {:noreply, state}
  end

  # Simulator mutations save straight to the rows (no broadcasts needed for a
  # feed refresh; canned findings broadcast through `report_finding`).
  defp apply_change(fun) do
    Store.write(fn ->
      with {:ok, loaded} <- Store.load(),
           {:ok, reply, new_state, _messages} <- fun.(loaded) do
        :ok = Store.save(new_state)
        {:ok, reply}
      end
    end)
  end

  ## Canned findings

  @relations ~w(repost-ring shared-link timing-sync audience-overlap)
  @trajectories ~w(forming stable fading)

  defp report_canned(kinds) do
    {:ok, loaded} = Store.load()
    finding = canned_finding(loaded, kinds)

    case Tracker.report_finding(finding) do
      {:ok, %{alerts: alerts}} ->
        for %{action: action, alert: alert} <- alerts,
            do: Logger.debug("Simulator #{action} #{alert.id} (#{alert.trigger_id})")

      {:error, errors} ->
        Logger.warning("Simulator finding was rejected: #{inspect(errors)}")
    end
  end

  # A random finding of one of `kinds`; with no live network, a new one is formed.
  defp canned_finding(state, kinds) do
    networks =
      for {_, n} <- state.networks, is_nil(n.retired_into), n.member_ids != [], do: n

    kind = if networks == [], do: :new, else: Enum.random(kinds)
    base = %{observed_at: DateTime.utc_now(), model: "simulator"}

    case kind do
      :trend ->
        network = Enum.random(networks)

        Map.merge(base, %{
          kind: "trend",
          network_id: network.id,
          answers: %{
            "increasing" => noul(Enum.random(50..95) / 100),
            "trajectory" => choice(Enum.random(@trajectories))
          }
        })

      :growth ->
        network = Enum.random(networks)
        feed = List.first(network.platforms) || "x"

        members =
          network.member_ids
          |> Enum.take_random(3)
          |> Enum.map(&%{feed_id: state.accounts[&1].feed_id, handle: state.accounts[&1].handle})

        group(base, members ++ new_accounts(feed, 2), network.id)

      :new ->
        group(base, new_accounts(Enum.random(~w(x reddit bluesky)), Enum.random(3..5)), nil)
    end
  end

  defp group(base, accounts, network_id) do
    base
    |> Map.merge(%{
      kind: "group",
      accounts: accounts,
      answers: %{
        "coordinated" => noul(Enum.random(75..97) / 100),
        "relation" => choice(Enum.random(@relations))
      }
    })
    |> then(&if(network_id, do: Map.put(&1, :network_id, network_id), else: &1))
  end

  defp new_accounts(feed, n),
    do: for(_ <- 1..n, do: %{feed_id: feed, handle: "sim_#{:rand.uniform(@sim_pool_size)}"})

  defp noul(p), do: %{"type" => "noul", "noul" => p}

  defp choice(label),
    do: %{"type" => "choice", "choice" => label, "confidence" => Enum.random(55..95) / 100}

  @window_seconds 24 * 3_600

  defp refresh_feeds(state) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    feed_health =
      Enum.map(state.feed_health, fn
        %{status: :healthy} = health ->
          # Rolling 24h window: reset the count once the window expires.
          health =
            if expired?(health.window_started_at, now),
              do: %{health | items_24h: 0, window_started_at: now},
              else: health

          window_started_at = health.window_started_at || now

          %{
            health
            | last_item_at: now,
              items_24h: health.items_24h + 1,
              window_started_at: window_started_at
          }

        health ->
          health
      end)

    {:ok, :refreshed, %{state | feed_health: feed_health}, []}
  end

  # Unknown window start: keep the existing count and start the window now.
  defp expired?(nil, _now), do: false
  defp expired?(started_at, now), do: DateTime.diff(now, started_at) >= @window_seconds
end

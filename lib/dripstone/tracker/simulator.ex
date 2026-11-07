defmodule Dripstone.Tracker.Simulator do
  @moduledoc """
  Dev-only driver for detection, so live updates (new alerts, badge counts,
  toasts) can be seen in the UI.

  Every `assess_interval` ms (2 minutes by default, first run after
  `first_assess` ms) it queues a `Dripstone.Workers.AssessWorker` job for one of a
  few stub handles. The job runs the real pipeline: stub adapter → `Scorer.assess`
  (which calls the AI if `OPENCODE_API_KEY` is set, otherwise heuristics only) →
  `Tracker.record_assessment/1`.

  It also stands in for ingestion: every `interval` ms it marks the Healthy sample
  feeds as having just received an item, so they don't go quiet (and turn
  Degraded) while the app runs. Down and Degraded feeds are left as they are.

  Started only when `config :dripstone, :simulate_alerts` is true, which `dev.exs`
  sets from `DRIPSTONE_SIMULATE=1`. Tests pass `enqueue:` to capture jobs instead
  of inserting them.
  """

  use GenServer

  require Logger

  alias Dripstone.Tracker.SampleStore
  alias Dripstone.Workers.AssessWorker

  @default_interval 45_000
  @default_assess_interval 120_000
  @default_first_assess 5_000

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
    state = %{
      interval: Keyword.get(opts, :interval, @default_interval),
      assess_interval: Keyword.get(opts, :assess_interval, @default_assess_interval),
      enqueue: Keyword.get(opts, :enqueue, &Oban.insert/1)
    }

    Process.send_after(self(), :tick, state.interval)
    Process.send_after(self(), :assess, Keyword.get(opts, :first_assess, @default_first_assess))
    {:ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    {:ok, _} = SampleStore.change(&refresh_feeds/1)
    Process.send_after(self(), :tick, state.interval)
    {:noreply, state}
  end

  def handle_info(:assess, state) do
    {adapter, handle} = Enum.random(@handles)

    case state.enqueue.(AssessWorker.new(%{"adapter" => adapter, "handle" => handle})) do
      {:ok, _job} -> Logger.debug("Simulator queued an assessment of #{handle} (#{adapter})")
      {:error, reason} -> Logger.warning("Simulator could not queue a job: #{inspect(reason)}")
    end

    Process.send_after(self(), :assess, state.assess_interval)
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
end

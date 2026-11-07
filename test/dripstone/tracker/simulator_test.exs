defmodule Dripstone.Tracker.SimulatorTest do
  # Reports findings into the app-wide store, so it must not run alongside other tests.
  use ExUnit.Case, async: false

  alias Dripstone.Tracker
  alias Dripstone.Tracker.{SampleStore, Simulator}

  setup do
    previous = SampleStore.get_state()
    on_exit(fn -> SampleStore.put_state(previous) end)
    Tracker.reset_sample_data!()
    :ok = Tracker.subscribe()
    :ok
  end

  test "is not started by default" do
    refute Application.get_env(:dripstone, :simulate_alerts)
    assert Process.whereis(Simulator) == nil
  end

  test "reports generated findings that raise new alerts" do
    before = length(Tracker.list_alerts())
    start_supervised!({Simulator, interval: 10, name: :test_simulator})

    assert_receive {:alert_raised, alert}, 2_000
    assert alert.trigger_id in ~w(network_growth network_reactivation promotion_shift)
    assert alert.status == :open

    _ = :sys.get_state(:test_simulator)
    assert length(Tracker.list_alerts()) > before
  end

  test "keeps healthy sample feeds fresh, leaving down and degraded ones alone" do
    stale = DateTime.add(DateTime.utc_now(), -3_600) |> DateTime.truncate(:second)
    state = SampleStore.get_state()

    :ok =
      SampleStore.put_state(%{
        state
        | feed_health: Enum.map(state.feed_health, &%{&1 | last_item_at: stale})
      })

    start_supervised!({Simulator, interval: 10, name: :test_simulator})
    assert_receive {:alert_raised, _}, 2_000
    _ = :sys.get_state(:test_simulator)

    health = Map.new(SampleStore.get_state().feed_health, &{&1.feed_id, &1})
    assert DateTime.after?(health["x"].last_item_at, stale)
    assert health["telegram"].last_item_at == stale
    assert health["facebook"].last_item_at == stale
    assert Enum.find(Tracker.feed_health(), &(&1.feed.id() == "x")).health.status == :healthy
  end
end
